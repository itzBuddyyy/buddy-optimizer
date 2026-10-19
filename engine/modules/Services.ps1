# ==============================================================
#  Services, scheduled tasks & background apps
#  Replaces: suite STEP 3 / STEP 15.
#  Fixes: wlidsvc (Microsoft Account sign-in) is no longer disabled - it
#  broke Windows sign-in with a Microsoft account, Xbox, Game Pass and the
#  Store. CDPUserSvc (clipboard/notifications) and RmSvc (airplane mode)
#  are left alone. Xbox services are only touched when Xbox mode is OFF.
#  SysMain is only disabled on SSD systems; sensors only on desktops.
# ==============================================================

function Invoke-Services {
    Write-Head 'Telemetry & unused services'
    $disable = @(
        'DiagTrack',            # Connected User Experiences & Telemetry
        'dmwappushservice',     # WAP push (telemetry routing)
        'RetailDemo',
        'MapsBroker',           # Downloaded maps manager
        'RemoteRegistry',
        'Fax',
        'WMPNetworkSvc',        # Windows Media Player network sharing
        'WpcMonSvc',            # Parental controls
        'wisvc',                # Windows Insider service
        'WerSvc'                # Error reporting uploads
    )
    $manual = @(
        'lfsvc',                # Geolocation (Manual keeps auto time-zone working)
        'TrkWks',               # Distributed link tracking
        'PhoneSvc',
        'icssvc',               # Mobile hotspot (starts when you turn it on)
        'diagnosticshub.standardcollector.service',
        'PerfHost',
        'spectrum'              # Mixed reality spatial audio
    )
    foreach ($s in $disable) { Set-ServiceStart -Name $s -Start Disabled }
    foreach ($s in $manual)  { Set-ServiceStart -Name $s -Start Manual }

    if ($script:Sys.SystemSSD) { Set-ServiceStart -Name 'SysMain' -Start Disabled }
    else { Write-Skip 'SysMain kept ON (system drive is an HDD - it speeds up game loading there)' }

    if (-not $script:Sys.IsLaptop) {
        foreach ($s in @('SensorService','SensrSvc','SensorDataService')) { Set-ServiceStart -Name $s -Start Manual }
    } else { Write-Skip 'Sensor services kept (laptop: auto-brightness / rotation)' }

    if (-not $script:XboxMode) {
        Write-Head 'Xbox Live services (Xbox mode OFF)'
        foreach ($s in @('XblAuthManager','XblGameSave','XboxNetApiSvc')) { Set-ServiceStart -Name $s -Start Disabled }
        Write-Info 'XboxGipSvc kept: it is needed for Xbox controllers (Elite paddles, firmware).'
        Write-Info 'Use "Xbox / Store Fix" in the menu if you need Xbox again.'
    } else {
        Write-Skip 'Xbox services untouched (Xbox mode ON)'
    }

    Write-Head 'Telemetry scheduled tasks'
    $tasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Application Experience\StartupAppTask',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
        '\Microsoft\Windows\Maps\MapsUpdateTask'
    )
    # Task Scheduler COM API (not Get-ScheduledTask, which goes through WMI and
    # hung for 2 minutes then aborted the run). Runs with a hard timeout because
    # Task Scheduler can share a stuck svchost process with WMI.
    $results = Invoke-WithTimeout -Seconds 45 -What 'scheduled tasks' -ArgumentList $tasks, $script:DryRun -Script {
        param($list, $dry)
        $s = New-Object -ComObject Schedule.Service
        $s.Connect()
        foreach ($t in $list) {
            $name = Split-Path $t -Leaf
            try { $task = $s.GetFolder((Split-Path $t -Parent)).GetTask($name) }
            catch { [pscustomobject]@{ Path = $t; Name = $name; R = 'missing' }; continue }
            if (-not $task.Enabled) { [pscustomobject]@{ Path = $t; Name = $name; R = 'already' }; continue }
            if ($dry) { [pscustomobject]@{ Path = $t; Name = $name; R = 'would' }; continue }
            try { $task.Enabled = $false; [pscustomobject]@{ Path = $t; Name = $name; R = 'disabled' } }
            catch { [pscustomobject]@{ Path = $t; Name = $name; R = "error: $($_.Exception.Message)" } }
        }
    }
    $results = @($results | Where-Object { $_ })
    if ($results.Count -eq 0) {
        Write-Skip 'Task Scheduler is not responding right now - reboot, then run option 4 again'
    }
    foreach ($r in @($results)) {
        switch -Wildcard ($r.R) {
            'missing'  { }
            'already'  { Write-Skip "Already disabled: $($r.Name)" }
            'would'    { Write-Dry "disable task $($r.Name)" }
            'disabled' {
                Add-JournalCommand -Description "Task $($r.Name) disabled" -UndoCommand "schtasks /Change /TN `"$($r.Path)`" /Enable"
                Write-OK "Task disabled: $($r.Name)"
            }
            'error*'   { Write-Fail "Task $($r.Name) - $($r.R)" }
        }
    }

    Write-Head 'Background apps'
    if (-not $script:XboxMode) {
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0
        Write-Info 'Store apps can no longer run in background (Xbox app included).'
    } else {
        # Only block the obvious offenders instead of every Store app
        foreach ($pkg in @('Microsoft.BingNews_8wekyb3d8bbwe','Microsoft.BingWeather_8wekyb3d8bbwe','Microsoft.GetHelp_8wekyb3d8bbwe',
                           'Microsoft.Getstarted_8wekyb3d8bbwe','Microsoft.WindowsFeedbackHub_8wekyb3d8bbwe','Microsoft.WindowsMaps_8wekyb3d8bbwe',
                           'Microsoft.People_8wekyb3d8bbwe','Microsoft.YourPhone_8wekyb3d8bbwe','Clipchamp.Clipchamp_yxz26nhyzhsrt')) {
            $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\$pkg"
            Set-Reg $k 'Disabled' 1 -Quiet
            Set-Reg $k 'DisabledByUser' 1 -Quiet
        }
        Write-OK 'Background access blocked for news/weather/tips/maps/phone apps (Xbox & Store untouched)'
    }
    $script:RebootNeeded = $true
}
