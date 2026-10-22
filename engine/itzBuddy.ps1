<#
    itzBuddy Optimization Suite v3.0
    Interactive Windows 10/11 optimizer for competitive gaming.

    Start it with itzBuddy.cmd (handles admin + execution policy), or:
        powershell -NoProfile -ExecutionPolicy Bypass -File .\itzBuddy.ps1
    Optional:  -DryRun   (show what would change, change nothing)
#>
param([switch]$DryRun)

$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'itzBuddy Optimization Suite'

# ---- Admin check / self-elevation ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($DryRun) { $argList += ' -DryRun' }
    try { Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs } catch { Write-Host 'Administrator rights are required.' -ForegroundColor Red; Read-Host 'Press ENTER' }
    exit
}

$script:Root     = Split-Path -Parent $PSCommandPath
$script:FilesDir = Join-Path $script:Root 'files'

. (Join-Path $script:Root 'lib\Core.ps1')
foreach ($m in Get-ChildItem -LiteralPath (Join-Path $script:Root 'modules') -Filter '*.ps1' | Sort-Object Name) { . $m.FullName }

$script:DryRun = [bool]$DryRun
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

Write-Host ''
Write-Host '  Checking Windows Management (WMI)...' -ForegroundColor DarkGray
if (-not (Test-WmiHealth)) { Write-Log 'WMI health check FAILED' }
Write-Host '  Detecting hardware...' -ForegroundColor DarkGray
$script:Sys = Get-SystemProfile
# Xbox mode ON = keep everything Xbox / Game Pass / Store needs working
$script:XboxMode = $script:Sys.XboxInstalled
Write-Log "System: $($script:Sys | ConvertTo-Json -Compress)"

# ------------------------------------------------------------------
# Menu definition.
# Kind = Recommended -> one Y/N confirmation then runs
#        Optional    -> opens its own chooser (pick items / toggles)
#        Repair      -> repair / restore tools
# ------------------------------------------------------------------
$script:Menu = @(
    @{ Key = '1';  Kind = 'Recommended'; Label = 'QUICK OPTIMIZE  (restore point + 2,3,4,5,6 in one go)'; Run = { Invoke-QuickOptimize } }
    @{ Key = '2';  Kind = 'Recommended'; Label = 'Power plan (Bitsum / Ultimate / High Performance)';     Run = { Invoke-PowerPlan } ; BatchRun = { Invoke-PowerPlan -Auto }; NoConfirm = $true }
    @{ Key = '3';  Kind = 'Recommended'; Label = 'Gaming core tweaks (MMCSS, Game Mode, DVR, mouse, MSI, network latency)'; Run = { Invoke-GamingCore } }
    @{ Key = '4';  Kind = 'Recommended'; Label = 'Services & background apps (telemetry off, Xbox-aware)'; Run = { Invoke-Services } }
    @{ Key = '5';  Kind = 'Recommended'; Label = 'Privacy, telemetry & ads off';                          Run = { Invoke-Privacy } }
    @{ Key = '6';  Kind = 'Recommended'; Label = 'Clean temp files';                                      Run = { Invoke-Cleanup } }
    @{ Key = '7';  Kind = 'Recommended'; Label = 'Network refresh (DNS flush, IP renew)';                 Run = { Invoke-NetworkReset } }

    @{ Key = '8';  Kind = 'Optional';    Label = 'Debloat apps (choose)';                                 Run = { Invoke-Debloat } }
    @{ Key = '9';  Kind = 'Optional';    Label = 'Startup apps manager (choose)';                         Run = { Invoke-StartupManager } }
    @{ Key = '10'; Kind = 'Optional';    Label = 'Look & feel: visual effects, taskbar, explorer, start, sounds, wallpaper'; Run = { Invoke-UITweaks } }
    @{ Key = '11'; Kind = 'Optional';    Label = 'GPU & drivers (NVIDIA profile, AMD, driver pages)';     Run = { Invoke-GPUMenu } }
    @{ Key = '12'; Kind = 'Optional';    Label = 'Timer Resolution service (STR)';                         Run = { Invoke-TimerResMenu } }
    @{ Key = '13'; Kind = 'Optional';    Label = 'Advanced toggles (HAGS, MPO, Memory Integrity, BCD, NVIDIA P0...)'; Run = { Invoke-AdvancedMenu } }

    @{ Key = '14'; Kind = 'Repair';      Label = 'Xbox / Microsoft Store fix';                             Run = { Invoke-XboxFix } }
    @{ Key = '15'; Kind = 'Repair';      Label = 'Xbox lockdown (disable Xbox services)';                  Run = { Invoke-XboxLockdown } }
    @{ Key = '16'; Kind = 'Repair';      Label = 'Restore default power plans (keeps your current one)';   Run = { Invoke-RestorePowerPlans } }
    @{ Key = '17'; Kind = 'Repair';      Label = 'Deep network reset (Winsock + TCP/IP, for broken connections)'; Run = { Invoke-DeepNetworkReset } }
    @{ Key = '18'; Kind = 'Repair';      Label = 'Undo a previous itzBuddy session';                       Run = { Invoke-Undo } }
    @{ Key = '19'; Kind = 'Repair';      Label = 'Create a System Restore point now';                      Run = { New-RestorePoint } }

    @{ Key = '20'; Kind = 'WinUtil';     Label = 'Tweaks: all 64 WinUtil tweaks by category, presets, undo';  Run = { Invoke-WinUtilTweaksMenu } }
    @{ Key = '21'; Kind = 'WinUtil';     Label = 'Apps: install, update or remove 239 apps (WinGet / Chocolatey)'; Run = { Invoke-WinUtilAppsMenu } }
    @{ Key = '22'; Kind = 'WinUtil';     Label = 'System tools: features, repairs, Windows Update, Store apps, DNS, panels...'; Run = { Invoke-WinUtilSystemMenu } }
    @{ Key = '23'; Kind = 'WinUtil';     Label = 'Windows 11 ISO creator: unattended ISO or bootable USB';  Run = { Invoke-WinUtilIsoMenu } }
)

function Show-Banner {
    Clear-Host
    $s = $script:Sys
    Write-Host ''
    Write-Host '   _ _       ____            _     _       ' -ForegroundColor Magenta
    Write-Host '  (_) |_ ___| __ ) _   _  __| | __| |_   _ ' -ForegroundColor Magenta
    Write-Host '  | | __|_  /  _ \| | | |/ _` |/ _` | | | |' -ForegroundColor Magenta
    Write-Host '  | | |_ / /| |_) | |_| | (_| | (_| | |_| |' -ForegroundColor Magenta
    Write-Host '  |_|\__/___|____/ \__,_|\__,_|\__,_|\__, |' -ForegroundColor Magenta
    Write-Host '        Optimization Suite v3.1      |___/' -ForegroundColor Magenta
    Write-Host ''
    $type = if ($s.IsLaptop) { 'Laptop' } else { 'Desktop' }
    $disk = if ($s.SystemSSD) { 'SSD' } else { 'HDD' }
    Write-Host "  $($s.OSName) (build $($s.Build))  |  $type  |  System drive: $disk" -ForegroundColor Gray
    Write-Host "  CPU: $($s.CPU)" -ForegroundColor Gray
    $hz = if ($s.RefreshRate) { "  @ $($s.RefreshRate) Hz" } else { '' }
    Write-Host "  GPU: $($s.GPU)$hz" -ForegroundColor Gray
    $xb = if ($script:XboxMode) { 'ON  (Xbox / Game Pass / Store kept working)' } else { 'OFF (Xbox services may be disabled)' }
    Write-Host "  Xbox mode: $xb" -ForegroundColor $(if ($script:XboxMode) { 'Green' } else { 'Yellow' })
    if ($script:DryRun) {
        Write-Host "  Dry run:   ON  (preview only - nothing will be changed)" -ForegroundColor Yellow
    } else {
        Write-Host "  Dry run:   OFF (changes are applied for real)" -ForegroundColor Gray
    }
    if ($script:RebootNeeded) { Write-Host '  * Reboot pending to apply changes' -ForegroundColor Yellow }
    if (-not $script:WmiHealthy) {
        Write-Host ''
        Write-Host '  !! Windows Management (WMI) is not responding on this PC right now.          ' -ForegroundColor White -BackgroundColor DarkRed
        Write-Host '  !! REBOOT before optimizing. Steps that need WMI will be skipped safely.     ' -ForegroundColor White -BackgroundColor DarkRed
    }
    if ($s.SvcHostGrouped) {
        Write-Host '  ! Services share svchost processes (SvcHostSplitThresholdInKB tweak). This can' -ForegroundColor Yellow
        Write-Host '    freeze WMI / Task Scheduler. Recommended: 13 > "Separate svchost" = ON.' -ForegroundColor Yellow
    }
    if ($script:DryRun) { Show-DryRunBanner }
}

function Show-DryRunBanner {
    Write-Host ''
    Write-Host '  ################################################################' -ForegroundColor Black -BackgroundColor Yellow
    Write-Host '  #  DRY RUN MODE - pick any option to PREVIEW what it would do  #' -ForegroundColor Black -BackgroundColor Yellow
    Write-Host '  #  Nothing is changed on your PC.   Press D again to exit.     #' -ForegroundColor Black -BackgroundColor Yellow
    Write-Host '  ################################################################' -ForegroundColor Black -BackgroundColor Yellow
}

function Switch-DryRun {
    $script:DryRun = -not $script:DryRun
    Clear-Host
    Write-Host ''
    if ($script:DryRun) {
        Write-Host '  DRY RUN is now ON' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  Choose any option from the menu (for example 1 = Quick Optimize).' -ForegroundColor White
        Write-Host '  It runs as a simulation: every change it WOULD make is listed in' -ForegroundColor White
        Write-Host '  grey with a [DRY] tag, but nothing is written, removed or deleted.' -ForegroundColor White
        Write-Host ''
        Write-Host '  When you are happy with the preview, press D again to switch' -ForegroundColor Gray
        Write-Host '  back to normal mode and run the option for real.' -ForegroundColor Gray
    } else {
        Write-Host '  DRY RUN is now OFF - options will apply changes for real.' -ForegroundColor Green
    }
    Write-Log "Dry run toggled: $script:DryRun"
    Write-Host ''
    [void](Read-Host '  Press ENTER to return to the menu')
}

function Switch-XboxMode {
    $script:XboxMode = -not $script:XboxMode
    Clear-Host
    Write-Host ''
    if ($script:XboxMode) {
        Write-Host '  Xbox mode is now ON - Xbox, Game Pass and Store services will be kept working.' -ForegroundColor Green
    } else {
        Write-Host '  Xbox mode is now OFF - options 1 and 4 will disable Xbox Live services' -ForegroundColor Yellow
        Write-Host '  and background access for Store apps (use 14 to undo later).' -ForegroundColor Yellow
    }
    Write-Log "Xbox mode toggled: $script:XboxMode"
    Write-Host ''
    [void](Read-Host '  Press ENTER to return to the menu')
}

function Show-Menu {
    Show-Banner
    $sections = @(
        @{ Kind = 'Recommended'; Title = 'RECOMMENDED  - one confirmation each';  Color = 'Green' },
        @{ Kind = 'Optional';    Title = 'OPTIONAL  - you choose what to apply';  Color = 'Cyan' },
        @{ Kind = 'Repair';      Title = 'REPAIR & RESTORE';                       Color = 'Yellow' },
        @{ Kind = 'WinUtil';     Title = 'WINUTIL (Chris Titus Tech)  - each opens its own menu'; Color = 'Magenta' }
    )
    foreach ($sec in $sections) {
        Write-Host ''
        Write-Host "  $($sec.Title)" -ForegroundColor $sec.Color
        foreach ($m in ($script:Menu | Where-Object { $_.Kind -eq $sec.Kind })) {
            Write-Host ("   {0,3}  {1}" -f $m.Key, $m.Label)
        }
    }
    Write-Host ''
    $dState = if ($script:DryRun) { 'ON' } else { 'off' }
    $xState = if ($script:XboxMode) { 'ON' } else { 'off' }
    Write-Host "     X  Xbox mode [$xState]    D  Dry run / preview [$dState]    L  Open log folder    R  Reboot    Q  Quit" -ForegroundColor DarkGray
    Write-Host '     Tip: type several numbers to queue them in one go, e.g.  1 8 9   or   3-6 10' -ForegroundColor DarkCyan
    Write-Host ''
}

function Get-MenuSelection {
    # "1 8 9", "1,8,9", "3-6 10" -> menu items in the order typed, no duplicates.
    # Returns $null if any token is invalid (so a typo never runs the wrong thing).
    param([string]$Text)
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($tok in ($Text -split '[\s,;]+' | Where-Object { $_ })) {
        if ($tok -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            $step = if ($a -le $b) { 1 } else { -1 }
            for ($n = $a; $n -ne ($b + $step); $n += $step) { $keys.Add([string]$n) }
        } elseif ($tok -match '^\d+$') {
            $keys.Add([string][int]$tok)
        } else { return $null }
    }
    $items = New-Object System.Collections.ArrayList
    foreach ($k in $keys) {
        $it = $script:Menu | Where-Object { $_.Key -eq $k } | Select-Object -First 1
        if (-not $it) { return $null }
        if (-not $items.Contains($it)) { [void]$items.Add($it) }
    }
    # Quick Optimize already contains 2-6: don't run them twice
    if ($items | Where-Object { $_.Key -eq '1' }) {
        $dupes = @($items | Where-Object { $_.Key -in '2','3','4','5','6' })
        foreach ($d in $dupes) { [void]$items.Remove($d) }
    }
    return , $items.ToArray()
}

function Invoke-MenuItem {
    # Runs one menu entry, isolated so an error never kills the menu / batch.
    param($Item, [switch]$Batch)
    Write-Log ">>> Menu $($Item.Key): $($Item.Label)"
    $run = $Item.Run
    if ($Batch -and $Item.BatchRun) { $run = $Item.BatchRun }
    # In a batch the user already confirmed once: recommended items run straight away
    $prevAuto = $script:AutoYes
    if ($Batch -and $Item.Kind -eq 'Recommended') { $script:AutoYes = $true }
    try { & $run }
    catch { Write-Fail "Unexpected error in '$($Item.Label)': $($_.Exception.Message)"; Write-Log $_.ScriptStackTrace }
    finally { $script:AutoYes = $prevAuto }
    Save-Journal
}

function Invoke-Batch {
    param([array]$Items)
    Clear-Host
    if ($script:DryRun) { Show-DryRunBanner }
    Write-Host ''
    Write-Host "  QUEUE - $($Items.Count) actions, run in this order:" -ForegroundColor Cyan
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray
    foreach ($it in $Items) {
        $how = switch ($it.Kind) {
            'Recommended' { 'runs automatically' }
            'Optional'    { if ($it.Run.ToString() -match 'Menu') { 'opens its menu - press B when done' } else { 'you pick what to apply' } }
            'WinUtil'     { 'opens its menu - press B when done' }
            default       { 'asks before changing anything' }
        }
        $col = switch ($it.Kind) { 'Recommended' { 'Green' } 'Optional' { 'Cyan' } 'WinUtil' { 'Magenta' } default { 'Yellow' } }
        Write-Host ("   {0,3}  {1}" -f $it.Key, $it.Label) -ForegroundColor $col
        Write-Host "         ($how)" -ForegroundColor DarkGray
    }
    if ($Items | Where-Object { $_.Key -eq '2' }) { Write-Host '  Power plan in a queue uses the automatic choice (Bitsum on desktop, High Performance on laptop).' -ForegroundColor DarkGray }
    Write-Host ''
    $q = if ($script:DryRun) { 'Preview this queue?' } else { 'Run this queue?' }
    if (-not (Confirm-Action $q)) { return }
    $i = 0
    foreach ($it in $Items) {
        $i++
        Clear-Host
        if ($script:DryRun) { Show-DryRunBanner }
        Write-Host ''
        Write-Host ("  ===== [{0}/{1}]  {2} =====" -f $i, $Items.Count, $it.Label) -ForegroundColor Magenta
        Invoke-MenuItem -Item $it -Batch
        if ($i -lt $Items.Count -and $it.Kind -eq 'Recommended') {
            Write-Host ''
            Write-Host "  Next: $($Items[$i].Label)" -ForegroundColor DarkGray
            Start-Sleep -Seconds 2
        }
    }
    Write-Host ''
    Write-Host '  ===== QUEUE FINISHED =====' -ForegroundColor Magenta
    Show-Stats
    Wait-Key
}

function Invoke-QuickOptimize {
    Write-Head 'QUICK OPTIMIZE'
    Write-Host '  Runs, in order:' -ForegroundColor Gray
    Write-Host '   1. System Restore point' -ForegroundColor Gray
    $plan = if ($script:Sys.IsLaptop) { 'High Performance (laptop)' } else { 'Bitsum Highest Performance' }
    Write-Host "   2. Power plan: $plan" -ForegroundColor Gray
    Write-Host '   3. Gaming core tweaks' -ForegroundColor Gray
    Write-Host '   4. Services & background apps' -ForegroundColor Gray
    Write-Host '   5. Privacy, telemetry & ads off' -ForegroundColor Gray
    Write-Host '   6. Temp files cleanup (locked files skipped)' -ForegroundColor Gray
    if (-not $script:WmiHealthy) {
        Write-Warn 'WMI is not responding: reboot first is strongly recommended (no restore point possible now).'
    }
    $xb = if ($script:XboxMode) { 'Xbox mode is ON: Xbox / Game Pass / Store stay working.' } else { 'Xbox mode is OFF: Xbox Live services will be disabled.' }
    Write-Host "  $xb" -ForegroundColor Yellow
    Write-Host ''
    if (-not (Confirm-Action 'Start Quick Optimize?')) { return }
    $script:AutoYes = $true
    $failed = @()
    $steps = @(
        @{ Name = 'Restore point';  Run = { New-RestorePoint } },
        @{ Name = 'Power plan';     Run = { Invoke-PowerPlan -Auto } },
        @{ Name = 'Gaming core';    Run = { Invoke-GamingCore } },
        @{ Name = 'Services';       Run = { Invoke-Services } },
        @{ Name = 'Privacy';        Run = { Invoke-Privacy } },
        @{ Name = 'Temp cleanup';   Run = { Invoke-Cleanup } }
    )
    try {
        # Each step is isolated: an error in one never stops the others
        foreach ($st in $steps) {
            try { & $st.Run }
            catch {
                $failed += $st.Name
                Write-Fail "$($st.Name) stopped early: $($_.Exception.Message)"
                Write-Log $_.ScriptStackTrace
            }
            Save-Journal
        }
    } finally { $script:AutoYes = $false }
    Write-Head 'Quick Optimize finished'
    if ($failed.Count) { Write-Warn "Not fully completed: $($failed -join ', ') - you can re-run just those from the menu (2-6)." }
    Write-Host '  Next (optional): 8 Debloat, 9 Startup apps, 11 GPU profile, 12 Timer Resolution.' -ForegroundColor Gray
}

function Show-Stats {
    Write-Host ''
    if ($script:DryRun) {
        Write-Host ("  PREVIEW FINISHED: {0} change(s) would be made, {1} skipped. Nothing was changed." -f $script:Stats.DRY, $script:Stats.SKIP) -ForegroundColor Yellow
        Write-Host '  Press D in the menu to leave dry run and apply for real.' -ForegroundColor Yellow
    } else {
        Write-Host ("  Done.  OK: {0}   Skipped: {1}   Failed: {2}" -f $script:Stats.OK, $script:Stats.SKIP, $script:Stats.FAIL) -ForegroundColor White
        if ($script:Journal.Count -gt 0) { Write-Host "  Undo data: $script:JournalFile" -ForegroundColor DarkGray }
    }
    Write-Host "  Log:       $script:LogFile" -ForegroundColor DarkGray
    $script:Stats.OK = 0; $script:Stats.SKIP = 0; $script:Stats.FAIL = 0; $script:Stats.DRY = 0
}

function Request-Reboot {
    if (Confirm-Action 'Reboot now?' -DefaultNo) {
        Write-Log 'Reboot requested by user'
        Restart-Computer -Force
    }
}

# ---------------- Main loop ----------------
Write-Log "itzBuddy started (DryRun=$script:DryRun)"
while ($true) {
    Show-Menu
    $choice = (Read-Host '  Select').Trim().ToUpper()
    switch ($choice) {
        'Q' {
            if ($script:RebootNeeded -and -not $script:DryRun) {
                Write-Host ''
                Write-Warn 'Some changes need a reboot to take effect.'
                Request-Reboot
            }
            Save-Journal
            exit
        }
        'X' { Switch-XboxMode; continue }
        'D' { Switch-DryRun; continue }
        'L' { Start-Process explorer.exe $script:DataRoot; continue }
        'R' { Request-Reboot; continue }
    }
    if ($choice -eq '') { continue }
    $sel = Get-MenuSelection $choice
    if ($null -eq $sel -or $sel.Count -eq 0) {
        Write-Host "  '$choice' is not a valid choice. Use menu numbers, e.g. 1   or   1 8 9   or   3-6" -ForegroundColor Red
        Start-Sleep -Seconds 2
        continue
    }
    if ($sel.Count -gt 1) { Invoke-Batch -Items $sel; continue }

    $item = $sel[0]
    Clear-Host
    if ($script:DryRun) { Show-DryRunBanner }
    if ($item.Kind -eq 'Recommended' -and $item.Key -ne '1' -and -not $item.NoConfirm) {
        Write-Host ''
        Write-Host "  $($item.Label)" -ForegroundColor Green
        $q = if ($script:DryRun) { 'Preview this?' } else { 'Apply?' }
        if (-not (Confirm-Action $q)) { continue }
    }
    Invoke-MenuItem -Item $item
    # WinUtil menus show their own results after each action
    if ($item.Kind -ne 'WinUtil' -and ($item.Kind -ne 'Optional' -or ($script:Stats.OK + $script:Stats.FAIL + $script:Stats.DRY) -gt 0)) { Show-Stats }
    if ($item.Run.ToString() -notmatch 'Menu') { Wait-Key }
}
