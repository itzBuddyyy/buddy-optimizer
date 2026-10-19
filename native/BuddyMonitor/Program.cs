using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32;

namespace BuddyMonitor
{
    /// <summary>
    /// Buddy Optimizer hardware monitor.
    /// stdout: one JSON object per line ({"type":"info"} once, then {"type":"tick"}).
    /// stdin commands: "interval 1000", "ping 1.1.1.1", "sensors off|on", "quit".
    /// </summary>
    internal static class Program
    {
        static volatile int _interval = 1000;
        internal static volatile string PingHost = "1.1.1.1";
        static volatile bool _sensorsOn = true;
        static readonly object _out = new object();

        [STAThread]
        static int Main(string[] args)
        {
            Console.OutputEncoding = new System.Text.UTF8Encoding(false);
            for (int i = 0; i < args.Length - 1; i++)
            {
                if (args[i] == "--interval") { int iv; if (int.TryParse(args[i + 1], out iv)) _interval = iv; }
                if (args[i] == "--ping") PingHost = args[i + 1];
                if (args[i] == "--no-sensors") _sensorsOn = false;
            }
            if (args.Contains("--no-sensors")) _sensorsOn = false;
            _interval = Math.Max(250, Math.Min(5000, _interval));

            new Thread(ReadCommands) { IsBackground = true, Name = "stdin" }.Start();

            var gpus = Dxgi.Enumerate();
            var disks = DiskInfo.Read();
            Emit(BuildInfo(gpus, disks));

            Sensors sensors = null;
            if (_sensorsOn) { sensors = new Sensors { IntervalMs = _interval }; sensors.Start(); }
            var ping = new PingProbe(); ping.Start();

            using (var q = new PdhQuery())
            {
                bool utility = q.Add("cpu", @"\Processor Information(_Total)\% Processor Utility");
                if (!utility) q.Add("cpu", @"\Processor Information(_Total)\% Processor Time");
                q.Add("cores", utility ? @"\Processor Information(*)\% Processor Utility" : @"\Processor Information(*)\% Processor Time");
                q.Add("perf", @"\Processor Information(_Total)\% Processor Performance");
                q.Add("procs", @"\System\Processes");
                q.Add("threads", @"\System\Threads");
                q.Add("ctx", @"\System\Context Switches/sec");
                q.Add("pages", @"\Memory\Pages/sec");
                q.Add("commit", @"\Memory\Committed Bytes");
                q.Add("commitLimit", @"\Memory\Commit Limit");
                q.Add("cache", @"\Memory\Cache Bytes");
                q.Add("standby", @"\Memory\Standby Cache Normal Priority Bytes");
                q.Add("gpuEng", @"\GPU Engine(*)\Utilization Percentage");
                q.Add("gpuDed", @"\GPU Adapter Memory(*)\Dedicated Usage");
                q.Add("gpuShr", @"\GPU Adapter Memory(*)\Shared Usage");
                q.Add("dR", @"\PhysicalDisk(*)\Disk Read Bytes/sec");
                q.Add("dW", @"\PhysicalDisk(*)\Disk Write Bytes/sec");
                q.Add("dIdle", @"\PhysicalDisk(*)\% Idle Time");
                q.Add("nR", @"\Network Interface(*)\Bytes Received/sec");
                q.Add("nS", @"\Network Interface(*)\Bytes Sent/sec");
                q.Add("nBw", @"\Network Interface(*)\Current Bandwidth");

                q.Collect();
                Thread.Sleep(Math.Min(_interval, 1000));
                double baseMhz = RegInt(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0", "~MHz");
                int tickN = 0;

                while (true)
                {
                    var started = DateTime.UtcNow;
                    if (sensors != null) sensors.IntervalMs = _interval;
                    q.Collect();
                    var snap = sensors != null ? sensors.Snapshot : null;
                    if (tickN++ % 30 == 0) disks = DiskInfo.Read();   // refresh free space every ~30 ticks
                    Emit(BuildTick(q, gpus, disks, snap, ping, baseMhz));
                    var wait = _interval - (int)(DateTime.UtcNow - started).TotalMilliseconds;
                    if (wait > 0) Thread.Sleep(wait);
                }
            }
        }

        static void ReadCommands()
        {
            try
            {
                string line;
                while ((line = Console.ReadLine()) != null)
                {
                    var p = line.Trim().Split(new[] { ' ' }, 2);
                    switch (p[0].ToLowerInvariant())
                    {
                        case "interval": int ms; if (p.Length > 1 && int.TryParse(p[1], out ms)) _interval = Math.Max(250, Math.Min(5000, ms)); break;
                        case "ping": if (p.Length > 1 && p[1].Length < 256) PingHost = p[1].Trim(); break;
                        case "quit": Environment.Exit(0); break;
                    }
                }
            }
            catch { }
            Environment.Exit(0);   // parent closed our stdin -> exit with it
        }

        static void Emit(string json)
        {
            lock (_out) { Console.Out.Write(json); Console.Out.Write('\n'); Console.Out.Flush(); }
        }

        // ------------------------------------------------------------ info

        static string BuildInfo(List<GpuAdapter> gpus, List<DiskInfo> disks)
        {
            var j = new Json().Obj();
            j.P("type", "info");
            var cpuKey = @"HARDWARE\DESCRIPTION\System\CentralProcessor\0";
            j.Obj("cpu")
                .P("name", (RegStr(cpuKey, "ProcessorNameString") ?? "CPU").Trim())
                .P("vendor", RegStr(cpuKey, "VendorIdentifier"))
                .P("cores", Native.PhysicalCores(), 0)
                .P("threads", Environment.ProcessorCount, 0)
                .P("baseMhz", RegInt(cpuKey, "~MHz"), 0)
                .EndObj();
            j.Arr("gpus");
            foreach (var g in gpus)
                j.Obj().P("name", g.Name).P("luid", g.Luid).P("vendor", Vendor(g.VendorId)).P("vram", g.DedicatedBytes, 0).P("shared", g.SharedBytes, 0).EndObj();
            j.EndArr();
            var mem = Native.Memory();
            // "installed" = what's on the sticks (32 GB), "total" = usable after hardware reservations (31.4 GB)
            ulong installedKb;
            double? installed = Native.GetPhysicallyInstalledSystemMemory(out installedKb) ? installedKb * 1024.0 : (double?)null;
            j.Obj("mem").P("total", mem.ullTotalPhys, 0).P("installed", installed, 0).EndObj();
            var nt = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion";
            int build = (int)RegInt(nt, "CurrentBuildNumber");
            string product = RegStr(nt, "ProductName") ?? "Windows";
            if (build >= 22000) product = product.Replace("Windows 10", "Windows 11");
            j.Obj("os").P("name", product).P("version", RegStr(nt, "DisplayVersion")).P("build", build, 0).P("ubr", RegInt(nt, "UBR"), 0).EndObj();
            var bios = @"HARDWARE\DESCRIPTION\System\BIOS";
            j.Obj("board")
                .P("vendor", RegStr(bios, "BaseBoardManufacturer"))
                .P("model", RegStr(bios, "BaseBoardProduct"))
                .P("bios", RegStr(bios, "BIOSVersion"))
                .P("system", RegStr(bios, "SystemProductName"))
                .EndObj();
            j.Arr("disks");
            foreach (var d in disks) d.Write(j);
            j.EndArr();
            j.P("computer", Environment.MachineName);
            j.EndObj();
            return j.ToString();
        }

        static string Vendor(uint id)
        {
            switch (id) { case 0x10DE: return "NVIDIA"; case 0x1002: return "AMD"; case 0x8086: return "Intel"; default: return "Other"; }
        }

        // ------------------------------------------------------------ tick

        static readonly Regex CoreRx = new Regex(@"^\d+,\d+$");
        static readonly Regex EngRx = new Regex(@"luid_(0x[0-9a-f]+_0x[0-9a-f]+).*engtype_(.+)$", RegexOptions.IgnoreCase);
        static readonly Regex MemRx = new Regex(@"luid_(0x[0-9a-f]+_0x[0-9a-f]+)", RegexOptions.IgnoreCase);

        static string BuildTick(PdhQuery q, List<GpuAdapter> gpus, List<DiskInfo> disks, SensorSnapshot snap, PingProbe ping, double baseMhz)
        {
            var j = new Json().Obj();
            j.P("type", "tick");
            j.P("t", (DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalMilliseconds, 0);

            // ---- CPU
            j.Obj("cpu");
            j.P("load", Clamp(q.Value("cpu")));
            j.Arr("cores");
            var cores = q.Array("cores").Where(kv => CoreRx.IsMatch(kv.Key))
                         .OrderBy(kv => int.Parse(kv.Key.Split(',')[0])).ThenBy(kv => int.Parse(kv.Key.Split(',')[1]));
            foreach (var kv in cores) j.V(Math.Min(100, Math.Max(0, kv.Value)));
            j.EndArr();
            var perf = q.Value("perf");
            j.P("mhz", perf.HasValue && baseMhz > 0 ? baseMhz * perf.Value / 100.0 : (double?)null, 0);
            j.P("mhzMax", snap?.CpuClockMax, 0);
            j.P("temp", snap?.CpuTemp);
            j.P("power", snap?.CpuPower);
            j.P("procs", q.Value("procs"), 0);
            j.P("threads", q.Value("threads"), 0);
            j.P("ctx", q.Value("ctx"), 0);
            j.P("uptime", Native.GetTickCount64() / 1000.0, 0);
            j.EndObj();

            // ---- GPU (per adapter: busiest engine type like Task Manager)
            var engines = new Dictionary<string, Dictionary<string, double>>(StringComparer.OrdinalIgnoreCase);
            foreach (var kv in q.Array("gpuEng"))
            {
                var m = EngRx.Match(kv.Key);
                if (!m.Success) continue;
                string luid = m.Groups[1].Value, eng = m.Groups[2].Value;
                Dictionary<string, double> e;
                if (!engines.TryGetValue(luid, out e)) engines[luid] = e = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
                double cur; e[eng] = (e.TryGetValue(eng, out cur) ? cur : 0) + kv.Value;
            }
            var ded = SumByLuid(q.Array("gpuDed"));
            var shr = SumByLuid(q.Array("gpuShr"));
            j.Arr("gpus");
            int gi = 0;
            foreach (var g in gpus)
            {
                Dictionary<string, double> e;
                engines.TryGetValue(g.Luid, out e);
                e = e ?? new Dictionary<string, double>();
                double load = e.Count > 0 ? Math.Min(100, e.Values.Max()) : 0;
                var s = MatchSensors(snap, g, gi++);
                j.Obj()
                    .P("name", g.Name)
                    .P("load", load)
                    .P("load3d", Eng(e, "3D"))
                    .P("compute", Math.Max(Eng(e, "Compute_0"), Eng(e, "Compute_1")))
                    .P("copy", Eng(e, "Copy"))
                    .P("decode", Math.Max(Eng(e, "VideoDecode"), Eng(e, "Video Decode")))
                    .P("encode", Math.Max(Eng(e, "VideoEncode"), Eng(e, "Video Encode")))
                    .P("vramUsed", Get(ded, g.Luid), 0)
                    .P("vramTotal", g.DedicatedBytes, 0)
                    .P("sharedUsed", Get(shr, g.Luid), 0)
                    .P("temp", s?.Temp).P("hotspot", s?.HotSpot).P("memTemp", s?.MemTemp)
                    .P("clock", s?.CoreClock, 0).P("memClock", s?.MemClock, 0)
                    .P("fan", s?.Fan, 0).P("fanPct", s?.FanPct, 0).P("power", s?.Power)
                    .EndObj();
            }
            j.EndArr();

            // ---- Memory
            var mem = Native.Memory();
            j.Obj("mem")
                .P("total", mem.ullTotalPhys, 0)
                .P("avail", mem.ullAvailPhys, 0)
                .P("used", mem.ullTotalPhys - mem.ullAvailPhys, 0)
                .P("load", mem.dwMemoryLoad, 0)
                .P("commit", q.Value("commit"), 0)
                .P("commitLimit", q.Value("commitLimit"), 0)
                .P("cache", q.Value("cache"), 0)
                .P("standby", q.Value("standby"), 0)
                .P("pages", q.Value("pages"), 0)
                .EndObj();

            // ---- Disks
            var dR = q.Array("dR"); var dW = q.Array("dW"); var dIdle = q.Array("dIdle");
            j.Arr("disks");
            foreach (var kv in dR.Where(k => k.Key != "_Total").OrderBy(k => k.Key))
            {
                int idx; int.TryParse(kv.Key.Split(' ')[0], out idx);
                var info = disks.FirstOrDefault(d => d.Index == idx);
                double idle; dIdle.TryGetValue(kv.Key, out idle);
                double w; dW.TryGetValue(kv.Key, out w);
                double? temp = null;
                if (snap != null && info != null)
                    foreach (var dt in snap.DiskTemps)
                        if (info.Model != null && (dt.Key.IndexOf(info.Model, StringComparison.OrdinalIgnoreCase) >= 0 || info.Model.IndexOf(dt.Key, StringComparison.OrdinalIgnoreCase) >= 0)) temp = dt.Value;
                j.Obj()
                    .P("index", idx, 0)
                    .P("label", kv.Key.Substring(kv.Key.IndexOf(' ') + 1))
                    .P("model", info?.Model)
                    .P("read", kv.Value, 0).P("write", w, 0)
                    .P("active", Clamp(100 - idle))
                    .P("size", info?.Size, 0).P("free", info?.Free, 0)
                    .P("temp", temp)
                    .EndObj();
            }
            j.EndArr();

            // ---- Network (active adapter = has a gateway; falls back to busiest)
            var nR = q.Array("nR"); var nS = q.Array("nS"); var nBw = q.Array("nBw");
            string primary = PrimaryAdapter(nR.Keys);
            j.Obj("net");
            if (primary == null && nR.Count > 0) primary = nR.OrderByDescending(k => k.Value + (nS.ContainsKey(k.Key) ? nS[k.Key] : 0)).First().Key;
            double rx = 0, tx = 0, bw = 0;
            if (primary != null) { nR.TryGetValue(primary, out rx); nS.TryGetValue(primary, out tx); nBw.TryGetValue(primary, out bw); }
            j.P("adapter", primary).P("rx", rx, 0).P("tx", tx, 0).P("link", bw / 1e6, 0);
            j.P("rxAll", nR.Values.Sum(), 0).P("txAll", nS.Values.Sum(), 0);
            var pr = ping.Stats();
            j.P("pingHost", PingHost).P("ping", pr.Last).P("pingAvg", pr.Avg).P("jitter", pr.Jitter).P("loss", pr.Loss);
            j.EndObj();

            j.Obj("sensors").P("ready", snap != null && snap.Ready).P("note", snap?.Note).P("cpuTemp", snap?.CpuTemp.HasValue == true).EndObj();
            j.EndObj();
            return j.ToString();
        }

        static GpuSensors MatchSensors(SensorSnapshot snap, GpuAdapter g, int index)
        {
            if (snap == null || snap.Gpus.Count == 0) return null;
            // match by name tokens ("AMD Radeon RX 7800 XT" vs LHM name), else by order
            var byName = snap.Gpus.FirstOrDefault(s => Norm(s.Name).Contains(Norm(g.Name)) || Norm(g.Name).Contains(Norm(s.Name)));
            return byName ?? (index < snap.Gpus.Count ? snap.Gpus[index] : null);
        }

        static string Norm(string s) { return Regex.Replace((s ?? "").ToLowerInvariant(), @"[^a-z0-9]", ""); }

        static double Eng(Dictionary<string, double> e, string key)
        {
            double v; return e.TryGetValue(key, out v) ? Math.Min(100, v) : 0;
        }

        static Dictionary<string, double> SumByLuid(Dictionary<string, double> src)
        {
            var r = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
            foreach (var kv in src)
            {
                var m = MemRx.Match(kv.Key);
                if (!m.Success) continue;
                double cur; r[m.Groups[1].Value] = (r.TryGetValue(m.Groups[1].Value, out cur) ? cur : 0) + kv.Value;
            }
            return r;
        }

        static double? Get(Dictionary<string, double> d, string k) { double v; return d.TryGetValue(k, out v) ? v : (double?)null; }
        static double? Clamp(double? v) { if (!v.HasValue) return null; return Math.Max(0, Math.Min(100, v.Value)); }

        // PDH sanitizes adapter names: ( -> [   ) -> ]   # / \ -> _
        static string PdhName(string d) { return d.Replace('(', '[').Replace(')', ']').Replace('#', '_').Replace('/', '_').Replace('\\', '_'); }

        static string PrimaryAdapter(IEnumerable<string> pdhNames)
        {
            try
            {
                var up = NetworkInterface.GetAllNetworkInterfaces()
                    .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback
                             && n.GetIPProperties().GatewayAddresses.Any(g => !g.Address.Equals(System.Net.IPAddress.Any)))
                    .OrderByDescending(n => n.Speed);
                var names = pdhNames.ToList();
                foreach (var n in up)
                {
                    var p = PdhName(n.Description);
                    var hit = names.FirstOrDefault(x => string.Equals(x, p, StringComparison.OrdinalIgnoreCase));
                    if (hit != null) return hit;
                }
            }
            catch { }
            return null;
        }

        static string RegStr(string path, string name)
        {
            try { using (var k = Registry.LocalMachine.OpenSubKey(path)) return k?.GetValue(name) as string; } catch { return null; }
        }
        static double RegInt(string path, string name)
        {
            try { using (var k = Registry.LocalMachine.OpenSubKey(path)) { var v = k?.GetValue(name); return v == null ? 0 : Convert.ToDouble(v); } } catch { return 0; }
        }
    }

    // ------------------------------------------------------------ disks

    internal sealed class DiskInfo
    {
        public int Index;
        public string Model;
        public string Letters;
        public double? Size, Free;

        public static List<DiskInfo> Read()
        {
            var list = new List<DiskInfo>();
            try
            {
                using (var k = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Services\disk\Enum"))
                {
                    int count = Convert.ToInt32(k?.GetValue("Count") ?? 0);
                    for (int i = 0; i < count; i++)
                    {
                        var id = k.GetValue(i.ToString()) as string;
                        string model = null;
                        if (id != null)
                            using (var dev = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Enum\" + id))
                                model = dev?.GetValue("FriendlyName") as string;
                        list.Add(new DiskInfo { Index = i, Model = model });
                    }
                }
            }
            catch { }
            // Volume sizes: map drive letters to disk numbers via IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS
            foreach (var drive in DriveInfo.GetDrives())
            {
                try
                {
                    if (drive.DriveType != DriveType.Fixed || !drive.IsReady) continue;
                    int disk = Native.DiskNumberOf(drive.Name.Substring(0, 2));
                    var d = list.FirstOrDefault(x => x.Index == disk);
                    if (d == null) continue;
                    d.Letters = (d.Letters == null ? "" : d.Letters + " ") + drive.Name.Substring(0, 2);
                    d.Size = (d.Size ?? 0) + drive.TotalSize;
                    d.Free = (d.Free ?? 0) + drive.AvailableFreeSpace;
                }
                catch { }
            }
            return list;
        }

        public void Write(Json j)
        {
            j.Obj().P("index", Index, 0).P("model", Model).P("letters", Letters).P("size", Size, 0).P("free", Free, 0).EndObj();
        }
    }

    // ------------------------------------------------------------ ping

    internal sealed class PingProbe
    {
        readonly Queue<double?> _hist = new Queue<double?>();
        readonly object _lock = new object();

        public struct Result { public double? Last, Avg, Jitter, Loss; }

        public void Start()
        {
            new Thread(() =>
            {
                using (var p = new Ping())
                    while (true)
                    {
                        double? ms = null;
                        try
                        {
                            var host = Program.PingHost;
                            var r = p.Send(host, 1000);
                            if (r.Status == IPStatus.Success) ms = r.RoundtripTime;
                        }
                        catch { }
                        lock (_lock) { _hist.Enqueue(ms); while (_hist.Count > 30) _hist.Dequeue(); }
                        Thread.Sleep(1000);
                    }
            }) { IsBackground = true, Name = "ping" }.Start();
        }

        public Result Stats()
        {
            lock (_lock)
            {
                var r = new Result();
                if (_hist.Count == 0) return r;
                var all = _hist.ToArray();
                var ok = all.Where(x => x.HasValue).Select(x => x.Value).ToArray();
                r.Last = all[all.Length - 1];
                r.Loss = 100.0 * (all.Length - ok.Length) / all.Length;
                if (ok.Length > 0) r.Avg = ok.Average();
                if (ok.Length > 1)
                {
                    double sum = 0;
                    for (int i = 1; i < ok.Length; i++) sum += Math.Abs(ok[i] - ok[i - 1]);
                    r.Jitter = sum / (ok.Length - 1);
                }
                return r;
            }
        }
    }

    // ------------------------------------------------------------ native helpers

    internal static class Native
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct MEMORYSTATUSEX
        {
            public uint dwLength, dwMemoryLoad;
            public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual;
        }

        [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX m);
        [DllImport("kernel32.dll")] public static extern ulong GetTickCount64();
        [DllImport("kernel32.dll")] public static extern bool GetPhysicallyInstalledSystemMemory(out ulong totalKb);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetLogicalProcessorInformationEx(int relationship, IntPtr buffer, ref uint length);

        public static MEMORYSTATUSEX Memory()
        {
            var m = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)) };
            GlobalMemoryStatusEx(ref m);
            return m;
        }

        public static int PhysicalCores()
        {
            try
            {
                uint len = 0;
                GetLogicalProcessorInformationEx(0, IntPtr.Zero, ref len);   // RelationProcessorCore
                if (len == 0) return Environment.ProcessorCount;
                IntPtr buf = Marshal.AllocHGlobal((int)len);
                try
                {
                    if (!GetLogicalProcessorInformationEx(0, buf, ref len)) return Environment.ProcessorCount;
                    int count = 0, off = 0;
                    while (off < len)
                    {
                        int size = Marshal.ReadInt32(buf + off + 4);   // Relationship(4) + Size(4)
                        if (size <= 0) break;
                        count++; off += size;
                    }
                    return count;
                }
                finally { Marshal.FreeHGlobal(buf); }
            }
            catch { return Environment.ProcessorCount; }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern IntPtr CreateFile(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DeviceIoControl(IntPtr h, uint code, IntPtr inBuf, uint inSize, IntPtr outBuf, uint outSize, out uint returned, IntPtr overlapped);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

        /// <summary>Disk number hosting a volume ("C:"), no admin needed (zero access rights).</summary>
        public static int DiskNumberOf(string letter)
        {
            IntPtr h = CreateFile(@"\\.\" + letter, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
            if (h == new IntPtr(-1)) return -1;
            IntPtr buf = Marshal.AllocHGlobal(256);
            try
            {
                uint ret;
                // IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS = 0x00560000
                if (!DeviceIoControl(h, 0x00560000, IntPtr.Zero, 0, buf, 256, out ret, IntPtr.Zero)) return -1;
                // VOLUME_DISK_EXTENTS: DWORD count, (pad to 8), DISK_EXTENT { DWORD DiskNumber; LARGE_INTEGER Start, Length }
                return Marshal.ReadInt32(buf + 8);
            }
            finally { Marshal.FreeHGlobal(buf); CloseHandle(h); }
        }
    }
}
