# ==============================================================
#  Gaming core tweaks
#  Merges: gaming-tweaks-v2.reg, suite STEP 6-12, gaming part of
#  Tweak+ Registry.reg.
#  Fixes: Game Mode was turned ON and OFF at the same time
#  (AllowAutoGameMode=0 + AutoGameModeEnabled=1), global Tcpip
#  Nagle values had no effect (they only work per interface),
#  deprecated netsh options (chimney/dca) removed, mouse change
#  applied live, sticky/filter keys hotkeys disabled.
# ==============================================================

function Invoke-GamingCore {
    $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'

    Write-Head 'MMCSS - multimedia & game scheduling'
    Set-Reg $mm 'SystemResponsiveness' 10          # MMCSS treats 0 as 10, so 10 is the real minimum
    Set-Reg $mm 'NetworkThrottlingIndex' 0xffffffff
    $g = "$mm\Tasks\Games"
    Set-Reg $g 'GPU Priority' 8
    Set-Reg $g 'Priority' 6
    Set-Reg $g 'Scheduling Category' 'High' 'String'
    Set-Reg $g 'SFIO Priority' 'High' 'String'
    Set-Reg $g 'Background Only' 'False' 'String'
    Set-Reg $g 'Clock Rate' 10000
    Set-Reg $g 'Affinity' 0
    Set-Reg $g 'Latency Sensitive' 'True' 'String'

    Write-Head 'CPU scheduler'
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 0x26
    if ($script:Sys.IsWin11) {
        # Lets a timer-resolution request (game / STR service) apply system wide on 22H2+
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1
    }
    if (-not $script:Sys.IsLaptop) {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
    } else { Write-Skip 'Power throttling left ON (laptop battery life)' }

    Write-Head 'Game Mode ON, Game DVR / background recording OFF'
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'ShowStartupPanel' 0
    $gc = 'HKCU:\System\GameConfigStore'
    Set-Reg $gc 'GameDVR_Enabled' 0
    Set-Reg $gc 'GameDVR_FSEBehaviorMode' 2
    Set-Reg $gc 'GameDVR_FSEBehavior' 2
    Set-Reg $gc 'GameDVR_HonorUserFSEBehaviorMode' 1
    Set-Reg $gc 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
    Set-Reg $gc 'GameDVR_EFSEFeatureFlags' 0
    $dvr = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'
    Set-Reg $dvr 'AppCaptureEnabled' 0
    Set-Reg $dvr 'HistoricalCaptureEnabled' 0
    Set-Reg $dvr 'AudioCaptureEnabled' 0
    Set-Reg $dvr 'MicrophoneCaptureEnabled' 0
    if (-not $script:XboxMode) {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    } else { Write-Skip 'Game Bar policy left alone (Xbox mode ON - Game Bar overlay still usable)' }

    Write-Head 'Windowed / borderless optimizations (flip model)'
    $dxKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    $cur = [string](Get-RegValue $dxKey 'DirectXUserGlobalSettings' '')
    # Merge instead of overwrite, so AutoHDR / VRR settings are kept
    $parts = @($cur -split ';' | Where-Object { $_ -and $_ -notmatch '^SwapEffectUpgradeEnable=' })
    $parts += 'SwapEffectUpgradeEnable=1'
    Set-Reg $dxKey 'DirectXUserGlobalSettings' (($parts -join ';') + ';') 'String'

    Write-Head 'Mouse - Enhance Pointer Precision OFF (raw 1:1)'
    $mouse = 'HKCU:\Control Panel\Mouse'
    Set-Reg $mouse 'MouseSpeed' '0' 'String'
    Set-Reg $mouse 'MouseThreshold1' '0' 'String'
    Set-Reg $mouse 'MouseThreshold2' '0' 'String'
    if (-not $script:DryRun) {
        # SPI_SETMOUSE (0x4) - apply now, no sign-out needed
        [void][itzBuddy.Native]::SystemParametersInfo(0x0004, 0, [int[]](0, 0, 0), 0x03)
        Write-OK 'Mouse acceleration disabled live'
    }

    Write-Head 'Accessibility hotkeys OFF (no Sticky Keys popup mid-match)'
    Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'
    Set-Reg 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '58' 'String'
    Set-Reg 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String'

    Write-Head 'GPU interrupts - MSI mode'
    Invoke-MsiMode

    Write-Head 'Network latency'
    Invoke-NetworkLatency

    Write-Head 'No surprise restarts / background downloads'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0

    $script:RebootNeeded = $true
}

function Invoke-MsiMode {
    # Pure registry (no WMI): every present PCI display device
    $count = 0
    $displayClass = '{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($dev in @(Get-ChildItem -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI' -ErrorAction SilentlyContinue |
                       Where-Object { $_.PSChildName -match '^VEN_(10DE|1002|8086)' })) {
        foreach ($inst in @(Get-ChildItem -LiteralPath $dev.PSPath -ErrorAction SilentlyContinue)) {
            if ([string]$inst.GetValue('ClassGUID') -ne $displayClass) { continue }
            if (-not $inst.GetValue('Driver')) { continue }          # not installed / ghost device
            $name = [string]$inst.GetValue('DeviceDesc')
            if ($name -match ';') { $name = $name.Split(';')[-1] }
            $msi = (Join-Path $inst.PSPath 'Device Parameters\Interrupt Management\MessageSignaledInterruptProperties') -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE', 'HKLM:'
            if (Test-Path -LiteralPath $msi) {
                Set-Reg $msi 'MSISupported' 1 -Quiet
                Write-OK "MSI mode: $name"
                $count++
            } else {
                Write-Skip "MSI key not exposed by driver: $name"
            }
        }
    }
    if ($count -eq 0) { Write-Skip 'No discrete/integrated GPU with MSI support found' }
}

function Get-UpAdapters {
    # Get-NetAdapter is WMI-based; run it with a timeout
    $r = Invoke-WithTimeout -Seconds 20 -What 'network adapters' -Script {
        Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name; InterfaceGuid = $_.InterfaceGuid; InterfaceDescription = $_.InterfaceDescription } }
    }
    return @($r)
}

function Invoke-NetworkLatency {
    # Nagle off per active physical adapter (the only place these values work)
    $ifRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $adapters = @(Get-UpAdapters | Where-Object { $_ })
    if ($adapters.Count -eq 0 -and -not $script:WmiHealthy) { Write-Skip 'Network adapters could not be read (WMI not responding) - reboot and run option 3 again' }
    foreach ($a in $adapters) {
        $p = "$ifRoot\$($a.InterfaceGuid)"
        if (Test-Path -LiteralPath $p) {
            Set-Reg $p 'TcpAckFrequency' 1 -Quiet
            Set-Reg $p 'TCPNoDelay' 1 -Quiet
            Set-Reg $p 'TcpDelAckTicks' 0 -Quiet
            Write-OK "Nagle OFF on: $($a.Name) ($($a.InterfaceDescription))"
        }
    }
    if ($adapters.Count -eq 0) { Write-Skip 'No connected physical adapter found for Nagle tweak' }

    $before = (netsh int tcp show global 2>$null | Out-String)
    $nets = @(
        @('autotuninglevel=normal', 'Receive window auto-tuning: normal'),
        @('rss=enabled',            'Receive Side Scaling: enabled'),
        @('ecncapability=disabled', 'ECN: disabled'),
        @('timestamps=disabled',    'TCP timestamps: disabled')
    )
    foreach ($n in $nets) {
        [void](Invoke-Native -Description $n[1] -File 'netsh.exe' -Arguments @('int','tcp','set','global',$n[0]))
    }
    if (-not $script:DryRun) {
        $snap = Join-Path $script:BackupDir "netsh-tcp-before-$($script:SessionId).txt"
        $before | Set-Content -LiteralPath $snap -Encoding UTF8
        Write-Info "Previous TCP globals saved to $snap"
    }

    # NIC power saving / interrupt moderation add latency. Registry keywords
    # are used (not display names) so this works on any Windows language.
    foreach ($a in $adapters) {
        $res = Invoke-WithTimeout -Seconds 40 -What "NIC power settings $($a.Name)" -ArgumentList $a.Name, $script:DryRun -Script {
            param($nic, $dry)
            foreach ($kw in @('*EEE', 'AdvancedEEE', 'EnableGreenEthernet', 'PowerSavingMode', '*InterruptModeration')) {
                $ap = Get-NetAdapterAdvancedProperty -Name $nic -RegistryKeyword $kw -ErrorAction SilentlyContinue
                if (-not $ap) { continue }
                $old = [string]($ap.RegistryValue | Select-Object -First 1)
                if ($old -eq '0') { continue }
                $r = 'would'
                if (-not $dry) {
                    try { Set-NetAdapterAdvancedProperty -Name $nic -RegistryKeyword $kw -RegistryValue '0' -NoRestart -ErrorAction Stop; $r = 'set' }
                    catch { $r = 'refused' }
                }
                [pscustomobject]@{ Kw = $kw; Display = $ap.DisplayName; Old = $old; R = $r }
            }
        }
        foreach ($x in @($res | Where-Object { $_ })) {
            switch ($x.R) {
                'would'   { Write-Dry "$($a.Name): $($x.Display) -> off" }
                'refused' { Write-Skip "$($a.Name): $($x.Display) - driver refused the change" }
                'set' {
                    Add-JournalCommand -Description "$($a.Name) $($x.Kw)" -UndoCommand "powershell -NoProfile -Command `"Set-NetAdapterAdvancedProperty -Name '$($a.Name)' -RegistryKeyword '$($x.Kw)' -RegistryValue '$($x.Old)'`""
                    Write-OK "$($a.Name): $($x.Display) off (applies after reboot)"
                }
            }
        }
    }
}
