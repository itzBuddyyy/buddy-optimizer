# ==============================================================
#  Advanced toggles (optional, one by one, current state shown)
#  These were mixed into Tweak+ Registry.reg / the suite without asking.
#  Each has a real trade-off, so each is now an explicit switch.
#  Dropped completely: "Disable UAC" (EnableLUA=0). On Windows 11 it
#  breaks every Store/UWP app, the Xbox app and some anti-cheats, and
#  turns every program into full admin. Replaced by the harmless
#  "no dimmed desktop on UAC prompt" option.
# ==============================================================

function Get-NvidiaClassKeys {
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -match '^\d{4}$' -and ([string]$_.GetValue('ProviderName') -match 'NVIDIA')
    } | ForEach-Object { $_.Name -replace '^HKEY_LOCAL_MACHINE', 'HKLM:' })
}

function Get-AdvancedToggles {
    $hags   = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 0
    $mpo    = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 0
    $hvci   = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
    $dg = Get-CimSafe -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -Seconds 10
    if ($dg -and $dg.SecurityServicesRunning -contains 2) { $hvci = 1 }
    $bcd    = (bcdedit /enum '{current}' 2>$null | Out-String)
    $uacDim = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'PromptOnSecureDesktop' 1
    $wsrch  = (Get-Service WSearch -ErrorAction SilentlyContinue).StartType
    $nv     = Get-NvidiaClassKeys
    $p0 = $false
    if ($nv.Count) { $p0 = (Get-RegValue $nv[0] 'DisableDynamicPstate' 0) -eq 1 }
    $hib = (Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled' 1) -eq 1

    return @(
        @{ Id = 'HAGS';  Label = 'Hardware-accelerated GPU scheduling'; On = ($hags -eq 2)
           Info = 'ON lowers latency on RTX 30/40/50 and RX 7000+ and is required for DLSS Frame Generation. Try OFF only if you see stutter.' }
        @{ Id = 'MPO';   Label = 'Disable Multi-Plane Overlay (MPO)'; On = ($mpo -eq 5)
           Info = 'Fixes flicker/black screens/stutter on some multi-monitor setups. Leave OFF if you have no issues.' }
        @{ Id = 'HVCI';  Label = 'Memory Integrity (Core Isolation)'; On = ($hvci -eq 1)
           Info = 'Turning it OFF gives ~5% FPS on some CPUs but lowers security. Some anti-cheats (Vanguard/FACEIT) may ask for it ON.' }
        @{ Id = 'BCD';   Label = 'BCD timer tweaks (dynamic tick off, TSC enhanced)'; On = ($bcd -match 'disabledynamictick')
           Info = 'More consistent timer on some systems. BitLocker is auto-suspended for one reboot so it will not ask for the recovery key.' }
        @{ Id = 'NVP0';  Label = 'NVIDIA: force max clocks (P0) + HDCP off'; On = $p0; Hidden = ($nv.Count -eq 0)
           Info = 'Stops GPU downclocking between frames. More heat/power at idle. HDCP off breaks Netflix/Disney+ 4K in browsers.' }
        @{ Id = 'WSRCH'; Label = 'Windows Search indexing'; On = ($wsrch -ne 'Disabled' -and $wsrch -ne 'Manual')
           Info = 'Indexing OFF saves disk/CPU spikes; Start menu file search gets slower.' }
        @{ Id = 'UAC';   Label = 'UAC prompt dims the desktop (secure desktop)'; On = ($uacDim -ne 0)
           Info = 'OFF = UAC prompt appears without the black flash that minimizes fullscreen games. UAC itself stays ON.' }
        @{ Id = 'HIBER'; Label = 'Hibernation / Fast Startup'; On = $hib
           Info = 'OFF frees disk space = RAM size and gives a clean kernel/driver state on every boot.' }
        @{ Id = 'SVCSPLIT'; Label = 'Separate svchost per service (Windows default)'; On = (-not $script:Sys.SvcHostGrouped)
           Info = 'OFF = "fewer processes" tweak (SvcHostSplitThresholdInKB). No FPS gain, but one hung service can freeze WMI/Task Scheduler/Start menu. Keep ON.' }
    ) | Where-Object { -not $_.Hidden }
}

function Set-AdvancedToggle {
    param([string]$Id, [bool]$Enable)
    switch ($Id) {
        'HAGS'  { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' $(if ($Enable) { 2 } else { 1 }); $script:RebootNeeded = $true }
        'MPO'   { if ($Enable) { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5 } else { Remove-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' }; $script:RebootNeeded = $true }
        'HVCI'  { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' $(if ($Enable) { 1 } else { 0 }); $script:RebootNeeded = $true }
        'BCD'   {
            if (-not $script:WmiHealthy) {
                # Without WMI the BitLocker state is unknown - a BCD edit could trigger the recovery-key screen
                Write-Fail 'WMI is not responding, so BitLocker status is unknown - BCD change skipped for safety. Reboot and retry.'
                return
            }
            if ($script:Sys.BitLocker -and -not $script:DryRun) {
                $ok = Invoke-WithTimeout -Seconds 30 -What 'Suspend BitLocker' -ArgumentList $env:SystemDrive -Script {
                    param($d) Suspend-BitLocker -MountPoint $d -RebootCount 1 -ErrorAction Stop | Out-Null; 'ok'
                }
                if ($ok -eq 'ok') { Write-OK 'BitLocker suspended for 1 reboot' }
                else { Write-Fail 'Could not suspend BitLocker - BCD change skipped for safety'; return }
            }
            if ($Enable) {
                [void](Invoke-Native -Description 'bcdedit disabledynamictick yes' -File 'bcdedit.exe' -Arguments @('/set','disabledynamictick','yes') -UndoCommand 'bcdedit /deletevalue disabledynamictick')
                [void](Invoke-Native -Description 'bcdedit tscsyncpolicy enhanced' -File 'bcdedit.exe' -Arguments @('/set','tscsyncpolicy','enhanced') -UndoCommand 'bcdedit /deletevalue tscsyncpolicy')
                # useplatformclock must be REMOVED, not set to false (forcing HPET off/on both hurt)
                [void](Invoke-Native -Description 'bcdedit useplatformclock default' -File 'bcdedit.exe' -Arguments @('/deletevalue','useplatformclock') -OkCodes @(0,1))
            } else {
                [void](Invoke-Native -Description 'bcdedit disabledynamictick default' -File 'bcdedit.exe' -Arguments @('/deletevalue','disabledynamictick') -OkCodes @(0,1))
                [void](Invoke-Native -Description 'bcdedit tscsyncpolicy default' -File 'bcdedit.exe' -Arguments @('/deletevalue','tscsyncpolicy') -OkCodes @(0,1))
            }
            $script:RebootNeeded = $true
        }
        'NVP0'  {
            foreach ($k in (Get-NvidiaClassKeys)) {
                if ($Enable) { Set-Reg $k 'DisableDynamicPstate' 1; Set-Reg $k 'RMHdcpKeyglobZero' 1 }
                else { Remove-Reg $k 'DisableDynamicPstate'; Remove-Reg $k 'RMHdcpKeyglobZero' }
            }
            $script:RebootNeeded = $true
        }
        'WSRCH' {
            if ($Enable) { Set-ServiceStart -Name 'WSearch' -Start Automatic -StartNow }
            else { Set-ServiceStart -Name 'WSearch' -Start Disabled }
        }
        'UAC'   { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'PromptOnSecureDesktop' $(if ($Enable) { 1 } else { 0 }) }
        'SVCSPLIT' {
            $ctl = 'HKLM:\SYSTEM\CurrentControlSet\Control'
            if ($Enable) { Remove-Reg $ctl 'SvcHostSplitThresholdInKB' }
            else {
                # Threshold above installed RAM = grouping (what "debloat" guides do)
                $kb = [int][Math]::Min([int]::MaxValue, ($script:Sys.RamGB + 1) * 1MB)
                Set-Reg $ctl 'SvcHostSplitThresholdInKB' $kb
            }
            if (-not $script:DryRun) { $script:Sys.SvcHostGrouped = -not $Enable }
            $script:RebootNeeded = $true
        }
        'HIBER' {
            if ($Enable) { [void](Invoke-Native -Description 'Hibernation ON' -File 'powercfg.exe' -Arguments @('/hibernate','on') -UndoCommand 'powercfg /hibernate off') }
            else { [void](Invoke-Native -Description 'Hibernation OFF' -File 'powercfg.exe' -Arguments @('/hibernate','off') -UndoCommand 'powercfg /hibernate on') }
        }
    }
}

function Invoke-AdvancedMenu {
    while ($true) {
        $t = @(Get-AdvancedToggles)
        Clear-Host
        Write-Host ""
        Write-Host "  ADVANCED TOGGLES - each one has a trade-off, read the note" -ForegroundColor Cyan
        Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
        for ($i = 0; $i -lt $t.Count; $i++) {
            $s = if ($t[$i].On) { 'ON ' } else { 'OFF' }
            $col = if ($t[$i].On) { 'Green' } else { 'DarkGray' }
            Write-Host ("  {0}  [{1}] " -f ($i + 1), $s) -NoNewline -ForegroundColor $col
            Write-Host $t[$i].Label -ForegroundColor White
            Write-Host "         $($t[$i].Info)" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host "  Number = flip that setting   B = back" -ForegroundColor DarkGray
        $c = (Read-Host '  Choice').Trim().ToUpper()
        if ($c -eq 'B' -or $c -eq '') { return }
        if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $t.Count) {
            $x = $t[[int]$c - 1]
            $target = -not $x.On
            $word = if ($target) { 'ON' } else { 'OFF' }
            if (Confirm-Action "Turn '$($x.Label)' $word?") {
                Set-AdvancedToggle -Id $x.Id -Enable $target
                Wait-Key
            }
        }
    }
}
