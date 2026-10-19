# ==============================================================
#  GPU & drivers (optional)
#  Replaces the driver / NVIDIA / AMD part of Tweak+\optimization.cmd.
#  Fixes: paths were hard-coded to C:\Windows\Setup\Scripts\files (only
#  existed on a custom ISO) - now uses the suite's own files folder.
#  The NVIDIA profile is only imported on NVIDIA systems, and its global
#  FPS cap (357 - meant for a 360 Hz monitor) is adapted to YOUR refresh
#  rate or removed. The takeown/icacls hack on the WindowsApps folder
#  (gave every app package full control and only worked for one exact
#  Control Panel version) is replaced by a normal app launch.
# ==============================================================

function Open-DriverPages {
    $v = $script:Sys.GpuVendors
    if ($v -contains 'NVIDIA') { Start-Process 'https://www.nvidia.com/en-us/drivers/'; Write-OK 'Opened NVIDIA driver page' }
    if ($v -contains 'AMD')    { Start-Process 'https://www.amd.com/en/support/download/drivers.html'; Write-OK 'Opened AMD driver page' }
    if ($v -contains 'Intel')  { Start-Process 'https://www.intel.com/content/www/us/en/support/detect.html'; Write-OK 'Opened Intel driver assistant' }
    if ($script:Sys.CpuVendor -eq 'AMD' -and $v -notcontains 'AMD') {
        Start-Process 'https://www.amd.com/en/support/download/drivers.html'; Write-OK 'Opened AMD page (chipset driver for your Ryzen CPU)'
    }
    if ($v.Count -eq 0) { Write-Warn 'No known GPU detected - check Device Manager' }
}

function Set-NoWUDrivers {
    Write-Head 'Stop Windows Update from replacing your GPU driver'
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' 0
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1
    Write-Info 'Windows will no longer auto-install vendor drivers. Update GPU/chipset drivers yourself.'
}

function Import-NvidiaProfile {
    # -Cap N skips the prompts (N = 0 for no FPS cap); used by the app
    param([int]$Cap = -1)
    Write-Head 'NVIDIA Profile Inspector - competitive base profile'
    if ($script:Sys.GpuVendors -notcontains 'NVIDIA') { Write-Skip 'No NVIDIA GPU detected'; return }
    $exe = Join-Path $script:FilesDir 'Inspector.exe'
    $nip = Join-Path $script:FilesDir 'Inspector.nip'
    if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $nip)) { Write-Fail 'Inspector.exe / Inspector.nip missing in files\'; return }

    Write-Host ""
    Write-Host '  This profile sets (global/base profile):' -ForegroundColor Gray
    Write-Host '   - Power management: Prefer maximum performance' -ForegroundColor Gray
    Write-Host '   - V-Sync: Force off      - G-SYNC / VRR: off globally' -ForegroundColor Gray
    Write-Host '   - Texture filtering: High performance, LOD bias clamp, trilinear/aniso opt.' -ForegroundColor Gray
    Write-Host '   - Shader cache: unlimited  - Threaded optimization: on' -ForegroundColor Gray
    Write-Host '   - FPS limiter (NVCP): 357 in the original file' -ForegroundColor Gray
    Write-Host ""
    $nipXml = [xml](Get-Content -LiteralPath $nip -Raw -Encoding UTF8)
    $limiter = $nipXml.ArrayOfProfile.Profile.Settings.ProfileSetting | Where-Object { $_.SettingNameInfo -eq 'Frame Rate Limiter for NVCPL' }
    $hz = $script:Sys.RefreshRate
    $cap = 0
    if ($Cap -ge 0) { $cap = $Cap }
    elseif ($hz -ge 60) {
        $suggest = [Math]::Max(30, $hz - 3)
        Write-Host "  Detected refresh rate: $hz Hz" -ForegroundColor Cyan
        $in = (Read-Host "  FPS cap: [Enter]=$suggest (refresh-3, best with G-SYNC)  0=no cap  or type a number").Trim()
        if ($in -eq '') { $cap = $suggest } elseif ($in -match '^\d+$') { $cap = [int]$in }
    } elseif (-not $script:AutoYes) {
        $in = (Read-Host '  FPS cap (0 = no cap)').Trim()
        if ($in -match '^\d+$') { $cap = [int]$in }
    }
    if (-not (Confirm-Action "Import NVIDIA profile with FPS cap = $(if ($cap -eq 0) { 'none' } else { $cap })?")) { return }
    if ($script:DryRun) { Write-Dry 'nvidiaProfileInspector import'; return }

    $tmpNip = Join-Path $env:TEMP 'itzBuddy-Inspector.nip'
    if ($limiter) { $limiter.SettingValue = [string]$cap }
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($true)
    $settings.Indent = $true
    $w = [System.Xml.XmlWriter]::Create($tmpNip, $settings); $nipXml.Save($w); $w.Close()

    $p = Start-Process -FilePath $exe -ArgumentList "`"$tmpNip`" -silent" -Wait -PassThru
    Remove-Item -LiteralPath $tmpNip -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -eq 0) { Write-OK 'NVIDIA base profile imported' } else { Write-Fail "Profile Inspector exit code $($p.ExitCode)" }
    Write-Info 'To undo: NVIDIA Control Panel > Manage 3D settings > Restore (driver defaults).'
}

function Open-NvidiaPanel {
    $pkg = Get-AppxPackage -Name 'NVIDIACorp.NVIDIAControlPanel' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg) { Start-Process "shell:AppsFolder\$($pkg.PackageFamilyName)!NVIDIACorp.NVIDIAControlPanel"; Write-OK 'NVIDIA Control Panel opened'; return }
    $classic = Join-Path ${env:ProgramFiles} 'NVIDIA Corporation\Control Panel Client\nvcplui.exe'
    if (Test-Path -LiteralPath $classic) { Start-Process $classic; Write-OK 'NVIDIA Control Panel opened'; return }
    $app = Join-Path ${env:ProgramFiles} 'NVIDIA Corporation\NVIDIA app\CEF\NVIDIA app.exe'
    if (Test-Path -LiteralPath $app) { Start-Process $app; Write-OK 'NVIDIA app opened'; return }
    Write-Fail 'NVIDIA Control Panel / NVIDIA app not found - install the driver first'
}

function Open-AmdPanel {
    $cands = @(
        (Join-Path ${env:ProgramFiles} 'AMD\CNext\CNext\RadeonSoftware.exe'),
        (Join-Path ${env:ProgramFiles} 'AMD\CNext\CNext\AMDRSServ.exe')
    )
    $exe = $cands | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($exe) {
        Start-Process $exe
        Write-OK 'AMD Software: Adrenalin Edition opened'
        Write-Info 'Suggested: Anti-Lag ON, Radeon Chill OFF, Enhanced Sync OFF, Wait for V-Sync: Always off.'
    } else { Write-Fail 'AMD Software not found - install the Adrenalin driver first' }
}

function Invoke-GPUMenu {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "  GPU & DRIVERS   (detected: $($script:Sys.GPU))" -ForegroundColor Cyan
        Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  1  Open Device Manager (check network / chipset / GPU drivers)"
        Write-Host "  2  Open driver download page(s) for your hardware"
        Write-Host "  3  Block Windows Update from replacing GPU drivers"
        $c4 = if ($script:Sys.GpuVendors -contains 'NVIDIA') { 'White' } else { 'DarkGray' }
        $c6 = if ($script:Sys.GpuVendors -contains 'AMD') { 'White' } else { 'DarkGray' }
        Write-Host "  4  NVIDIA: import competitive profile (Profile Inspector)" -ForegroundColor $c4
        Write-Host "  5  NVIDIA: open Control Panel / NVIDIA app" -ForegroundColor $c4
        Write-Host "  6  AMD: open Adrenalin settings" -ForegroundColor $c6
        Write-Host "  B  Back"
        $c = (Read-Host "  Choice").Trim().ToUpper()
        switch ($c) {
            '1' { Start-Process devmgmt.msc }
            '2' { Open-DriverPages; Wait-Key }
            '3' { if (Confirm-Action 'Apply?') { Set-NoWUDrivers }; Wait-Key }
            '4' { Import-NvidiaProfile; Wait-Key }
            '5' { Open-NvidiaPanel; Wait-Key }
            '6' { Open-AmdPanel; Wait-Key }
            'B' { return }
        }
    }
}
