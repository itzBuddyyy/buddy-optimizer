<p align="center">
  <img src="docs/icon.png" width="128" alt="Buddy Optimizer icon">
</p>

<h1 align="center">Buddy Optimizer</h1>
<p align="center"><b>A real-time performance monitor and one-click Windows tuner for competitive gaming.</b><br>
Purple Void edition · Windows 10 / 11 · x64</p>

<p align="center">
  <img src="docs/screenshots/dashboard.png" width="860" alt="Dashboard">
</p>

## Features

**Live monitoring.** A panel for each component, updated up to twice a second:

| Panel | What you see |
|---|---|
| Processor | Total and per-thread load, live clock speed, processes and threads, uptime |
| Graphics | Load, core / hotspot / VRAM temperature, clock, fan RPM, board power, VRAM usage, and 3D / compute / encode / decode engines |
| Memory | In use, available, cached and committed memory, plus history |
| Storage | Read/write throughput, activity and free space for each drive (and temperature when available) |
| Network | Download and upload, ping, jitter and packet loss to a server you choose, plus link speed |

**One-click optimization.** Quick Optimize starts with a System Restore point and then tunes six areas:
- **Power:** high-performance power plan
- **Gaming:** Game Mode, scheduler priority, raw mouse input, MSI interrupts and network latency
- **Services:** telemetry and unused services
- **Privacy:** ads, tips and tracking
- **Cleanup:** temporary files
- **Network:** a quick connection refresh

**Tools:** Debloat, startup apps, look & feel, GPU (NVIDIA profile, AMD Adrenalin, driver pages), timer resolution, and advanced switches that each show their trade-off.

**Undo everything.** Every registry value, service start type and command is recorded before it changes. Any session can be rolled back from **Optimize → Repair**.

**Xbox-aware.** Xbox mode keeps Xbox, Game Pass and the Microsoft Store working.

**Other features:**
- Password lock and auto-lock
- Threshold alerts (GPU temperature, CPU, RAM, ping)
- Tray mode, launch at login and automatic updates from GitHub Releases
- Five languages: English, Italiano, Español, Français, Deutsch
- Dark and light themes, adjustable glass, macOS- or Windows-style window controls, and three motion levels

<p align="center">
  <img src="docs/screenshots/optimize.png" width="420" alt="Optimize">
  <img src="docs/screenshots/settings.png" width="420" alt="Settings">
</p>

## Install

Download `Buddy-Optimizer-Setup-x.y.z.exe` from [Releases](../../releases) and run it.

- The app opens with a password lock. Your distributor gives you the password, and you can change it in **Settings → Security**.
- Monitoring runs **without** administrator rights. The optimization engine asks for administrator rights **once per session**, the first time you optimize something.
- The installer is not code-signed yet, so Windows SmartScreen may show "Windows protected your PC". Click **More info → Run anyway**.

## How it works

```
Electron app (runs as the normal user)
├── Renderer: React + Motion, custom glass UI, sandboxed, no Node access
├── Main process: settings, password lock (scrypt), tray, alerts, updates
├── BuddyMonitor.exe   C# (.NET Framework 4.7.2, built into Windows)
│     Windows performance counters (PDH) for CPU, GPU engines, VRAM, disk and network
│     DXGI for GPU names and VRAM size; LibreHardwareMonitorLib for GPU temperature, fan and power
│     Streams JSON lines; no WMI, no admin rights, no kernel driver
└── engine\Agent.ps1   started elevated on demand (one UAC prompt)
      Talks to the app over a private named pipe (random name + one-time token)
      Runs the itzBuddy PowerShell modules; every change is journaled for undo
```

There is no CPU temperature on purpose. Reading it needs a kernel driver (PawnIO), and some anti-cheats, such as FACEIT, are reported to block that driver. Buddy Optimizer never installs one.

## Build from source

Requirements: Node.js 22+, .NET SDK 8+ (it builds the net472 helper), Windows 10/11 x64.

```bash
npm install
npm run build:native   # BuddyMonitor.exe
npm run build:icons    # icon.ico, installer artwork (from the vector masters)
npm run dev            # run the app
npm run dist           # build release/Buddy-Optimizer-Setup-<version>.exe
```

You can preview the interface in a browser with simulated data: `npx vite --config vite.preview.config.ts`

### Releasing

1. The repository is `itzBuddyyy/buddy-optimizer` (set in `electron-builder.yml` and `package.json`).
2. Bump `version` in `package.json`, commit, then push a tag: `git tag v1.0.1 && git push --tags`
3. The **Release** workflow builds the installer and publishes it to GitHub Releases. Installed copies update themselves.

## Project layout

| Path | Contents |
|---|---|
| `src/main` | Electron main process (window, IPC, lock, monitor and engine bridges) |
| `src/preload` | The typed, minimal bridge exposed to the UI |
| `src/renderer` | The interface: views, components, design tokens, translations |
| `native/BuddyMonitor` | C# hardware monitor helper |
| `engine` | itzBuddy optimization engine (PowerShell), also usable on its own via `itzBuddy.cmd` |
| `scripts` | Icon generator (pure vector geometry) and asset build |
| `build` | Icons, installer artwork, NSIS hooks |

## Third-party components

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE) © 2026 itzBuddy. Bundled third-party components keep their own licenses.
