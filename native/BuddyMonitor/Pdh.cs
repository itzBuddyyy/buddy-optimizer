using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace BuddyMonitor
{
    /// <summary>
    /// Thin wrapper over the Windows PDH API. Uses PdhAddEnglishCounter so the
    /// same counter paths work on every Windows display language (the old
    /// scripts broke on Italian Windows because names are localized).
    /// No WMI involved - PDH reads the kernel performance data directly.
    /// </summary>
    internal sealed class PdhQuery : IDisposable
    {
        const uint PDH_FMT_DOUBLE = 0x00000200;
        const uint PDH_FMT_NOCAP100 = 0x00008000;
        const uint PDH_MORE_DATA = 0x800007D2;
        const uint ERROR_SUCCESS = 0;

        [StructLayout(LayoutKind.Explicit)]
        struct PDH_FMT_COUNTERVALUE
        {
            [FieldOffset(0)] public uint CStatus;
            [FieldOffset(8)] public double doubleValue;
        }

        [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
        static extern uint PdhOpenQuery(string dataSource, IntPtr userData, out IntPtr query);
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
        static extern uint PdhAddEnglishCounter(IntPtr query, string path, IntPtr userData, out IntPtr counter);
        [DllImport("pdh.dll")]
        static extern uint PdhCollectQueryData(IntPtr query);
        [DllImport("pdh.dll")]
        static extern uint PdhGetFormattedCounterValue(IntPtr counter, uint format, out uint type, out PDH_FMT_COUNTERVALUE value);
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
        static extern uint PdhGetFormattedCounterArray(IntPtr counter, uint format, ref uint bufferSize, out uint itemCount, IntPtr buffer);
        [DllImport("pdh.dll")]
        static extern uint PdhCloseQuery(IntPtr query);

        readonly IntPtr _query;
        readonly Dictionary<string, IntPtr> _counters = new Dictionary<string, IntPtr>();

        public PdhQuery()
        {
            if (PdhOpenQuery(null, IntPtr.Zero, out _query) != ERROR_SUCCESS)
                throw new InvalidOperationException("PdhOpenQuery failed");
        }

        /// <summary>Adds a counter; returns false when it doesn't exist on this system.</summary>
        public bool Add(string key, string englishPath)
        {
            IntPtr c;
            if (PdhAddEnglishCounter(_query, englishPath, IntPtr.Zero, out c) != ERROR_SUCCESS) return false;
            _counters[key] = c;
            return true;
        }

        public bool Has(string key) { return _counters.ContainsKey(key); }

        public void Collect() { PdhCollectQueryData(_query); }

        public double? Value(string key)
        {
            IntPtr c;
            if (!_counters.TryGetValue(key, out c)) return null;
            uint type;
            PDH_FMT_COUNTERVALUE v;
            if (PdhGetFormattedCounterValue(c, PDH_FMT_DOUBLE | PDH_FMT_NOCAP100, out type, out v) != ERROR_SUCCESS) return null;
            if (v.CStatus != 0 && v.CStatus != 1) return null; // PDH_CSTATUS_VALID_DATA / NEW_DATA
            return v.doubleValue;
        }

        /// <summary>Returns instance name -> value for a wildcard counter.</summary>
        public Dictionary<string, double> Array(string key)
        {
            var result = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
            IntPtr c;
            if (!_counters.TryGetValue(key, out c)) return result;
            uint size = 0, count;
            uint rc = PdhGetFormattedCounterArray(c, PDH_FMT_DOUBLE | PDH_FMT_NOCAP100, ref size, out count, IntPtr.Zero);
            if (rc != PDH_MORE_DATA || size == 0) return result;
            IntPtr buf = Marshal.AllocHGlobal((int)size);
            try
            {
                rc = PdhGetFormattedCounterArray(c, PDH_FMT_DOUBLE | PDH_FMT_NOCAP100, ref size, out count, buf);
                if (rc != ERROR_SUCCESS) return result;
                // PDH_FMT_COUNTERVALUE_ITEM_W on x64: name ptr (8) + value struct (16) = 24 bytes
                int stride = IntPtr.Size + 16;
                for (int i = 0; i < count; i++)
                {
                    IntPtr item = buf + i * stride;
                    string name = Marshal.PtrToStringUni(Marshal.ReadIntPtr(item));
                    uint status = (uint)Marshal.ReadInt32(item + IntPtr.Size);
                    if (status != 0 && status != 1) continue;
                    double val = BitConverter.Int64BitsToDouble(Marshal.ReadInt64(item + IntPtr.Size + 8));
                    if (name == null) continue;
                    double existing;
                    // duplicate instance names (e.g. two identical NICs) get summed
                    result[name] = result.TryGetValue(name, out existing) ? existing + val : val;
                }
            }
            finally { Marshal.FreeHGlobal(buf); }
            return result;
        }

        public void Dispose() { PdhCloseQuery(_query); }
    }
}
