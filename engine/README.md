# itzBuddy Optimization Suite v3.1

An interactive optimizer for competitive gaming on Windows 10/11.
**Run it:** extract the whole folder, then double-click `itzBuddy.cmd`. It asks for admin rights.

Every change is logged. Registry values, service start types and commands are saved to an undo journal at
`C:\ProgramData\itzBuddy\backups`. Use menu **18** to roll back any session. Press **D** in the menu for a
dry run, which shows every change without applying anything.

## Menu

| # | Section | Type | Source in the old ZIP |
|---|---|---|---|
| 1 | **Quick Optimize**: restore point + 2,3,4,5,6 | one confirmation | all of the below |
| 2 | Power plan (Bitsum / Ultimate / High Perf) | one choice | `Power.pow`, `optimization.cmd`, suite step 1-2 |
| 3 | Gaming core tweaks | one confirmation | `gaming-tweaks-v2.reg`, suite steps 6-12, `Registry.reg` (gaming) |
| 4 | Services & background apps | one confirmation | suite step 3/15 |
| 5 | Privacy, telemetry & ads | one confirmation | `gaming-tweaks-v2.reg`, suite 14-19, `Registry.reg` (privacy) |
| 6 | Clean temp files | one confirmation | `PuliziaTemp.ps1/.bat` |
| 7 | Network refresh | one confirmation | `pulizia_connessione.bat` |
| 8 | Debloat apps | optional checklist | `Debloat.ps1` |
| 9 | Startup apps manager | optional checklist | `Registry.reg` STARTUP, suite step 4 |
| 10 | Look & feel | optional checklist | `Registry.reg` UI parts, `Tiles.ps1`, wallpaper |
| 11 | GPU & drivers | optional sub-menu | `optimization.cmd`, `Inspector.exe/.nip` |
| 12 | Timer Resolution service | optional | `STR.exe`, `Vs2010x64/x86.exe` |
| 13 | Advanced toggles | optional, one by one | HAGS/MPO/HVCI/NVIDIA/BCD from `Registry.reg` + suite |
| 14-15 | Xbox / Store fix · Xbox lockdown | repair | `itzBuddy_XboxFix.bat` / `_REVERT.bat` |
| 16 | Restore default power plans | repair | `RestorePowerPlans.ps1` |
| 17 | Deep network reset | repair | new |
| 18-19 | Undo session · Restore point | repair | new (replaces the suite's "restore helper") |
| 20 | WinUtil tweaks: 64 tweaks in 8 categories, Minimal/Standard/Advanced presets, apply or undo | own menu | WinUtil (Chris Titus Tech, MIT) |
| 21 | WinUtil apps: 239 apps in 12 categories, search, install/remove, update all (WinGet or Chocolatey) | own menu | WinUtil |
| 22 | WinUtil system tools: features, repairs, Windows Update policy, Store apps, control panels, DNS, Ultimate Performance, O&O ShutUp10++, OpenSSH, PowerShell profile | own menu | WinUtil |
| 23 | Windows 11 ISO creator: unattended ISO or bootable USB (type ERASE to confirm the USB) | own menu | WinUtil Win11 Creator |

**Running several actions at once:** type more than one number at the `Select` prompt, for example `1 8 9`,
`1,8,9` or `3-6 10`. You get a list of the queue and confirm once. Recommended items then run without asking
again. Checklists (8, 9, 10) and sub-menus (11, 12, 13) still open so you can choose; press **B** to leave a
sub-menu and move to the next item. Items 2-6 are skipped if 1 is in the queue, because Quick Optimize already
includes them. A typo cancels the whole queue, so nothing unexpected runs.

**Xbox mode** (toggle with **X**) turns on automatically when Gaming Services or the Xbox app is installed.
While it's on, nothing that Xbox, Game Pass or Microsoft Store needs gets disabled.

## What was broken or harmful in the old files, and what changed

- **`optimization.cmd`** only worked from `C:\Windows\Setup\Scripts\files` (a custom-ISO path), and it quit
  if you answered "N" to the TikTok question. It also **deleted the Balanced, High Performance and Power Saver plans**.
  Its NVIDIA step ran `takeown`/`icacls` on WindowsApps, which gave every app package full control,
  and it only matched one Control Panel version. All of this is rewritten.
- **`Registry.reg`**
  - Turned **UAC off** (`EnableLUA=0`). On Windows 11 this breaks Store/UWP apps, the Xbox app and some anti-cheats.
    It has been removed and replaced by an optional "no dimmed desktop" switch.
  - Deleted **every startup entry**, including audio, mouse and RGB software. Replaced by the startup manager,
    which disables entries the same way Task Manager does, so they can be re-enabled.
  - Turned off browser **hardware acceleration**, which costs FPS while Discord or a stream runs. Also turned off
    the Edge/Chrome updaters. Both removed.
  - Forced **100% DPI**, which broke text on 1440p, 4K and laptop screens. Removed.
  - Wrote `UserPreferencesMask` as the wrong registry type, so Windows ignored it. Fixed to binary.
  - Contained an invalid `Computer\HKEY_LOCAL_MACHINE` key. Fixed.
  - Turned off Automatic Maintenance, which also stops SSD TRIM. Removed.
  - Denied account info and turned off notifications, which **broke Xbox sign-in**.
    This is the reason the XboxFix script existed. Removed.
  - Applied NVIDIA P0/HDCP to class key `\0000` without checking it was the NVIDIA GPU. Now it detects the right key,
    and it's an optional toggle.
  - Turned Game Mode on and off at the same time. Now it's on.
- **`win11-gaming-optimizer-v2.2-suite.ps1`**
  - Disabled `wlidsvc`, which broke Microsoft-account sign-in to Windows, Xbox and the Store.
    It also disabled CDPUserSvc and RmSvc (airplane mode). All of these are now left alone.
  - Disabled SysMain even on hard drives. Now it only does so when the system drive is an SSD.
  - Used deprecated `netsh` options (`chimney`, `dca`) and printed OK even when a command failed.
  - Parsed `powercfg` output in a way that broke on non-English Windows.
  - Set Nagle values globally, where they have no effect. Now they're set per network adapter.
  - Ran BCD edits without suspending BitLocker, which could trigger the recovery-key prompt.
- **`Debloat.ps1`** didn't remove the provisioned copies, so the apps came back after updates. It had hard-coded
  `C:\Users\Administrator` OneDrive paths, and it removed Calculator, Snipping Tool and Camera without asking.
  It's now a checklist, and it checks whether your folders live in OneDrive before removing OneDrive.
- **`Tiles.ps1`** only works on Windows 10. Windows 11 now gets the proper Start settings instead.
- **XboxFix `.bat`**: `sc config X start=auto` is missing the space that sc.exe requires (`start= auto`), so those
  service changes failed silently. The new version uses Set-Service and restores the real Windows defaults.
- **`PuliziaTemp`** stopped on every locked file. Locked files are now skipped automatically.
  Crash dumps, error reports and the Delivery Optimization cache were added. GPU shader caches are kept on purpose.
- **`Inspector.nip`** set a global **357 FPS cap**, which only makes sense on a 360 Hz monitor.
  The cap is now based on your refresh rate, or you can turn it off.
- **`STR.exe`** ran from the extract folder, so the service broke when the folder moved. It's now copied
  to `C:\Program Files\itzBuddy`, and an uninstall option was added.

## Troubleshooting

- **A red "WMI is not responding" banner at startup.** Windows Management Instrumentation is stuck. Reboot before
  optimizing. Until then, steps that need WMI are skipped safely and never hang: restore point, adapter tweaks,
  BCD edits.
- **A yellow "services share svchost processes" warning.** The PC has the `SvcHostSplitThresholdInKB`
  "fewer processes" tweak. It packs WMI, Task Scheduler, User Manager and others into one process, so a single
  hiccup freezes them all. It gives no FPS gain. Turn it back to the Windows default with
  **13 → "Separate svchost per service" = ON**, then reboot.
- **Services are no longer stopped while Windows is running.** Only their startup type changes, and they stop at the
  next reboot. Stopping them live is what froze WMI on PCs with grouped svchosts.
- **Quick Optimize runs every step on its own.** If one step fails, the others still run, and the summary lists what to re-run.

## Folder layout

```
itzBuddy.cmd        launcher (admin + execution policy)
itzBuddy.ps1        menu
lib\Core.ps1        logging, prompts, detection, undo journal
modules\*.ps1       one file per section (WinUtil.ps1 = options 20-23 and the app's WinUtil screens)
winutil\           vendored WinUtil functions + catalogs (MIT), buddy-categories.json
files\              Power.pow, Inspector.exe/.nip, STR.exe, VC++ 2010, Wallpaper.png
```
