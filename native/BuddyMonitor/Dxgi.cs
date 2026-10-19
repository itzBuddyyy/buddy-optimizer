using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace BuddyMonitor
{
    internal sealed class GpuAdapter
    {
        public string Name;
        public string Luid;          // "0x00000000_0x0000C1A2" - same format as PDH instance names
        public uint VendorId;
        public ulong DedicatedBytes;
        public ulong SharedBytes;
    }

    /// <summary>
    /// Enumerates GPUs through DXGI so the PDH "GPU Engine" counters (which only
    /// carry an adapter LUID) can be matched to a real name and VRAM size.
    /// Works for NVIDIA, AMD and Intel without vendor SDKs.
    /// </summary>
    internal static class Dxgi
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DXGI_ADAPTER_DESC1
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
            public uint VendorId, DeviceId, SubSysId, Revision;
            public UIntPtr DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
            public uint LuidLow;
            public int LuidHigh;
            public uint Flags;
        }

        [ComImport, Guid("29038f61-3839-4626-91fd-086879011a05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IDXGIAdapter1
        {
            // IDXGIObject
            void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
            // IDXGIAdapter
            void EnumOutputs(); void GetDesc(); void CheckInterfaceSupport();
            // IDXGIAdapter1
            [PreserveSig] int GetDesc1(out DXGI_ADAPTER_DESC1 desc);
        }

        [ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IDXGIFactory1
        {
            void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
            void EnumAdapters(); void MakeWindowAssociation(); void GetWindowAssociation(); void CreateSwapChain(); void CreateSoftwareAdapter();
            [PreserveSig] int EnumAdapters1(uint index, out IDXGIAdapter1 adapter);
            [PreserveSig] bool IsCurrent();
        }

        [DllImport("dxgi.dll")]
        static extern int CreateDXGIFactory1([In] ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IDXGIFactory1 factory);

        public static List<GpuAdapter> Enumerate()
        {
            var list = new List<GpuAdapter>();
            try
            {
                Guid iid = typeof(IDXGIFactory1).GUID;
                IDXGIFactory1 f;
                if (CreateDXGIFactory1(ref iid, out f) != 0 || f == null) return list;
                for (uint i = 0; ; i++)
                {
                    IDXGIAdapter1 a;
                    if (f.EnumAdapters1(i, out a) != 0 || a == null) break;   // DXGI_ERROR_NOT_FOUND
                    DXGI_ADAPTER_DESC1 d;
                    if (a.GetDesc1(out d) == 0 && (d.Flags & 2) == 0)           // skip software adapters
                    {
                        // Skip duplicates (same LUID shows once per output on some drivers)
                        string luid = string.Format("0x{0:X8}_0x{1:X8}", (uint)d.LuidHigh, d.LuidLow);
                        if (!list.Exists(x => x.Luid == luid))
                            list.Add(new GpuAdapter
                            {
                                Name = (d.Description ?? "GPU").Trim(),
                                Luid = luid,
                                VendorId = d.VendorId,
                                DedicatedBytes = d.DedicatedVideoMemory.ToUInt64(),
                                SharedBytes = d.SharedSystemMemory.ToUInt64()
                            });
                    }
                    Marshal.ReleaseComObject(a);
                }
                Marshal.ReleaseComObject(f);
            }
            catch { }
            // Discrete GPUs first (more VRAM)
            list.Sort((x, y) => y.DedicatedBytes.CompareTo(x.DedicatedBytes));
            return list;
        }
    }
}
