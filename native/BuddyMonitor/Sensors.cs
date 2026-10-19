using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using LibreHardwareMonitor.Hardware;

namespace BuddyMonitor
{
    internal sealed class GpuSensors
    {
        public string Name;
        public double? Temp, HotSpot, MemTemp, CoreClock, MemClock, Fan, FanPct, Power, Load;
    }

    internal sealed class SensorSnapshot
    {
        public double? CpuTemp, CpuPower, CpuClockMax;
        public List<GpuSensors> Gpus = new List<GpuSensors>();
        public Dictionary<string, double> DiskTemps = new Dictionary<string, double>();
        public bool Ready;
        public string Note;
    }

    /// <summary>
    /// Optional extra sensors (temperatures, clocks, fans, power) through
    /// LibreHardwareMonitorLib 0.9.6. GPU sensors are read in user mode through
    /// the vendor libraries (ADL / NVAPI / IGCL) - no kernel driver needed.
    /// CPU temperatures need the PawnIO driver; this app NEVER installs it
    /// (PawnIO is reported to be blocked by FACEIT anti-cheat), it only uses it
    /// if the user already has it. Everything runs on its own thread with a
    /// timeout so a slow vendor library can't freeze the monitor.
    /// </summary>
    internal sealed class Sensors : IDisposable
    {
        readonly object _lock = new object();
        SensorSnapshot _snap = new SensorSnapshot { Note = "starting" };
        Computer _pc;
        Thread _thread;
        volatile bool _stop;
        public int IntervalMs = 1000;

        public void Start()
        {
            _thread = new Thread(Run) { IsBackground = true, Name = "sensors", Priority = ThreadPriority.BelowNormal };
            _thread.Start();
        }

        public SensorSnapshot Snapshot { get { lock (_lock) return _snap; } }

        void Run()
        {
            try
            {
                _pc = new Computer { IsGpuEnabled = true, IsCpuEnabled = true, IsStorageEnabled = true };
                var opened = new ManualResetEventSlim();
                var opener = new Thread(() => { try { _pc.Open(); } catch { } opened.Set(); }) { IsBackground = true };
                opener.Start();
                if (!opened.Wait(TimeSpan.FromSeconds(15)))
                {
                    lock (_lock) _snap = new SensorSnapshot { Note = "sensor library did not respond" };
                    return;
                }
                while (!_stop)
                {
                    var s = Read();
                    lock (_lock) _snap = s;
                    Thread.Sleep(Math.Max(500, IntervalMs));
                }
            }
            catch (Exception ex)
            {
                lock (_lock) _snap = new SensorSnapshot { Note = ex.GetType().Name };
            }
        }

        static double? Positive(double? v) { return v.HasValue && v.Value > 0 ? v : null; }

        static double? Pick(IHardware h, SensorType type, params string[] names)
        {
            foreach (var n in names)
            {
                var s = h.Sensors.FirstOrDefault(x => x.SensorType == type && x.Name.IndexOf(n, StringComparison.OrdinalIgnoreCase) >= 0 && x.Value.HasValue);
                if (s != null) return Math.Round(s.Value.Value, 1);
            }
            return null;
        }

        SensorSnapshot Read()
        {
            var s = new SensorSnapshot { Ready = true };
            foreach (var h in _pc.Hardware)
            {
                try { h.Update(); } catch { continue; }
                switch (h.HardwareType)
                {
                    case HardwareType.Cpu:
                        // Without the PawnIO driver LHM reports these as 0 -> "not available"
                        s.CpuTemp = Positive(Pick(h, SensorType.Temperature, "Tctl", "Tdie", "Package", "Core Average", "Core Max", "CPU"));
                        s.CpuPower = Positive(Pick(h, SensorType.Power, "Package", "CPU"));
                        var clocks = h.Sensors.Where(x => x.SensorType == SensorType.Clock && x.Name.StartsWith("Core", StringComparison.OrdinalIgnoreCase) && x.Value.HasValue).Select(x => (double)x.Value.Value).ToList();
                        if (clocks.Count > 0 && clocks.Max() > 0) s.CpuClockMax = Math.Round(clocks.Max());
                        break;
                    case HardwareType.GpuNvidia:
                    case HardwareType.GpuAmd:
                    case HardwareType.GpuIntel:
                        s.Gpus.Add(new GpuSensors
                        {
                            Name = h.Name,
                            Temp = Pick(h, SensorType.Temperature, "GPU Core", "Core", "GPU"),
                            HotSpot = Pick(h, SensorType.Temperature, "Hot Spot", "Hotspot"),
                            MemTemp = Pick(h, SensorType.Temperature, "Memory Junction", "Memory"),
                            CoreClock = Pick(h, SensorType.Clock, "GPU Core", "Core"),
                            MemClock = Pick(h, SensorType.Clock, "GPU Memory", "Memory"),
                            Fan = Pick(h, SensorType.Fan, "GPU Fan", "Fan"),
                            FanPct = Pick(h, SensorType.Control, "GPU Fan", "Fan"),
                            Power = Pick(h, SensorType.Power, "GPU Package", "GPU Power", "Package", "Core"),
                            Load = Pick(h, SensorType.Load, "GPU Core", "D3D 3D", "Core")
                        });
                        break;
                    case HardwareType.Storage:
                        var t = Pick(h, SensorType.Temperature, "Composite", "Temperature");
                        if (t.HasValue) s.DiskTemps[h.Name] = t.Value;
                        break;
                }
            }
            return s;
        }

        public void Dispose()
        {
            _stop = true;
            try { _pc?.Close(); } catch { }
        }
    }
}
