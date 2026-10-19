# Third-party notices

Buddy Optimizer includes or depends on the following components.

## Bundled in the installer

| Component | License | Notes |
|---|---|---|
| [Electron](https://www.electronjs.org/) (incl. Chromium, Node.js) | MIT (+ Chromium licenses) | App runtime |
| [React](https://react.dev/) | MIT | UI framework |
| [Motion](https://motion.dev/) | MIT | Spring animations |
| [Lucide](https://lucide.dev/) | ISC | Icons |
| [Inter](https://rsms.me/inter/) by Rasmus Andersson | SIL Open Font License 1.1 | UI typeface. Apple's SF Pro license does not allow bundling it in a Windows app, so Inter (with optical sizes) is used instead |
| [electron-updater](https://www.electron.build/) | MIT | Automatic updates from GitHub Releases |
| [LibreHardwareMonitorLib](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) 0.9.6 | MPL-2.0 | GPU / storage sensors (unmodified binary) |
| HidSharp, DiskInfoToolkit, RAMSPDToolkit, BlackSharp.Core | See each package | Dependencies of LibreHardwareMonitorLib |
| [NVIDIA Profile Inspector](https://github.com/Orbmu2k/nvidiaProfileInspector) (`engine/files/Inspector.exe`) | MIT | Imports the optional NVIDIA profile |
| Microsoft Visual C++ 2010 Redistributable (`engine/files/Vs2010*.exe`) | Microsoft redistributable terms | Runtime needed by the timer-resolution service |

## Need verification before commercial distribution

These files came with the original itzBuddy suite, and their redistribution terms are not documented here.
Confirm you have the right to redistribute them, or remove them, before selling the app:

| File | What it is | Used by |
|---|---|---|
| `engine/files/STR.exe` | SetTimerResolutionService (community tool, no license file included) | Optimize → Tools → Timer |
| `engine/files/Power.pow` | "Bitsum Highest Performance" power plan exported from Bitsum software | Power plan option 1 |
| `engine/files/Wallpaper.png` | itzBuddy wallpaper | Look & feel → Wallpaper |

If you remove one, the related option simply reports that the file is missing. For example, the power plan falls back to Ultimate Performance.
