# ==============================================================
#  Timer Resolution service (optional)
#  From Tweak+\optimization.cmd (STR.exe = SetTimerResolutionService,
#  needs the Visual C++ 2010 runtime = Vs2010x64/x86.exe).
#  Fixes: the service used to run from wherever the script was
#  extracted - if that folder moved, the service broke. It is now copied
#  to Program Files. "sc config STR start=auto" was missing the space sc
#  requires ("start= auto"); Set-Service is used instead. The VC++
#  installers are skipped when already installed. Uninstall is provided.
# ==============================================================

$script:StrDir = Join-Path ${env:ProgramFiles} 'itzBuddy'
$script:StrExe = Join-Path $script:StrDir 'STR.exe'

function Test-VC2010 {
    param([string]$Arch)
    $keys = if ($Arch -eq 'x64') { @('HKLM:\SOFTWARE\Microsoft\VisualStudio\10.0\VC\VCRedist\x64') }
            else { @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\10.0\VC\VCRedist\x86', 'HKLM:\SOFTWARE\Microsoft\VisualStudio\10.0\VC\VCRedist\x86') }
    foreach ($k in $keys) { if ((Get-RegValue $k 'Installed' 0) -eq 1) { return $true } }
    return $false
}

function Get-StrService {
    Get-CimSafe Win32_Service | Where-Object { $_.PathName -match 'STR\.exe' } | Select-Object -First 1
}

function Install-TimerRes {
    Write-Head 'Timer Resolution service'
    if ($script:Sys.IsLaptop) { Write-Warn 'Laptop detected: a 0.5 ms timer keeps the CPU awake and costs battery life.' }
    Write-Info 'Keeps Windows at its highest timer resolution so frame pacing / input timing are consistent.'
    if (-not (Confirm-Action 'Install and start the Timer Resolution service?')) { return }
    if ($script:DryRun) { Write-Dry 'VC++ 2010 + STR service'; return }

    foreach ($arch in @('x64','x86')) {
        if (Test-VC2010 $arch) { Write-Skip "Visual C++ 2010 $arch already installed"; continue }
        $inst = Join-Path $script:FilesDir "Vs2010$arch.exe"
        if (-not (Test-Path -LiteralPath $inst)) { Write-Fail "files\Vs2010$arch.exe missing"; continue }
        $p = Start-Process -FilePath $inst -ArgumentList '/install /quiet /norestart' -Wait -PassThru
        if ($p.ExitCode -in 0, 1638, 3010) { Write-OK "Visual C++ 2010 $arch installed" } else { Write-Fail "VC++ 2010 $arch exit code $($p.ExitCode)" }
    }

    $existing = Get-StrService
    if ($existing) {
        Write-Info "Service already registered: $($existing.Name)"
    } else {
        $src = Join-Path $script:FilesDir 'STR.exe'
        if (-not (Test-Path -LiteralPath $src)) { Write-Fail 'files\STR.exe missing'; return }
        New-Item -ItemType Directory -Path $script:StrDir -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $script:StrExe -Force
        $p = Start-Process -FilePath $script:StrExe -ArgumentList '-install' -Wait -PassThru -WindowStyle Hidden
        if ($p.ExitCode -ne 0) { Write-Fail "STR.exe -install exit code $($p.ExitCode)"; return }
        $existing = Get-StrService
        if (-not $existing) { Write-Fail 'Service did not register'; return }
        Write-OK "Service registered: $($existing.Name)"
        Add-JournalCommand -Description 'Timer Resolution service installed' -UndoCommand "`"$script:StrExe`" -uninstall"
    }
    try {
        Set-Service -Name $existing.Name -StartupType Automatic -ErrorAction Stop
        Start-Service -Name $existing.Name -ErrorAction Stop
        Write-OK 'Timer Resolution service: Automatic + running'
    } catch { Write-Fail "Could not start service: $($_.Exception.Message)" }
    if ($script:Sys.IsWin11) {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1
        Write-Info 'GlobalTimerResolutionRequests=1 set (required on Windows 11 for the service to apply system-wide).'
    }
    $script:RebootNeeded = $true
}

function Uninstall-TimerRes {
    Write-Head 'Remove Timer Resolution service'
    $svc = Get-StrService
    if (-not $svc) { Write-Skip 'Service not installed'; return }
    if (-not (Confirm-Action "Remove service '$($svc.Name)'?")) { return }
    if ($script:DryRun) { Write-Dry 'uninstall STR'; return }
    Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
    $exe = ($svc.PathName -replace '"', '' -replace '\s+-.*$', '').Trim()
    if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe -ArgumentList '-uninstall' -Wait -WindowStyle Hidden }
    if (Get-StrService) { sc.exe delete $svc.Name | Out-Null }
    if (-not (Get-StrService)) { Write-OK 'Timer Resolution service removed' } else { Write-Fail 'Service still present - reboot and retry' }
}

function Invoke-TimerResMenu {
    $svc = Get-StrService
    $state = if ($svc) { "installed ($($svc.State))" } else { 'not installed' }
    Clear-Host
    Write-Host ""
    Write-Host "  TIMER RESOLUTION SERVICE   status: $state" -ForegroundColor Cyan
    Write-Host "  1  Install / start"
    Write-Host "  2  Uninstall"
    Write-Host "  B  Back"
    switch ((Read-Host '  Choice').Trim().ToUpper()) {
        '1' { Install-TimerRes; Wait-Key }
        '2' { Uninstall-TimerRes; Wait-Key }
    }
}
