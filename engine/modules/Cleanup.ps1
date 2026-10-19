# ==============================================================
#  Temp cleanup
#  Rewrite of PuliziaTemp.ps1 / PuliziaTemp.bat.
#  Changes: locked files are skipped automatically by default (the old
#  version stopped on every in-use file, often dozens of times), BITS is
#  stopped together with Windows Update, more junk locations, and GPU
#  shader caches are deliberately NOT deleted (that causes stutter the
#  next time each game compiles its shaders).
# ==============================================================

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Clear-Folder {
    param([string]$Path, [string]$Label, [bool]$Interactive)
    $r = [ordered]@{ Folder = $Label; Deleted = 0; Skipped = 0; Bytes = 0L }
    Write-Host ""
    Write-Host "  -> $Label" -ForegroundColor Cyan
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { Write-Skip 'Folder not found'; return [pscustomobject]$r }
    $skipAll = -not $Interactive
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        $size = $f.Length
        if ($script:DryRun) { $r.Deleted++; $r.Bytes += $size; continue }
        $done = $false
        while (-not $done) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $r.Deleted++; $r.Bytes += $size; $done = $true
            } catch {
                if ($skipAll) { $r.Skipped++; $done = $true; continue }
                Write-Host "     In use: $($f.FullName)" -ForegroundColor DarkYellow
                $c = (Read-Host '     [R]etry  [S]kip  [A]lways skip  [Q]uit folder').Trim().ToUpper()
                switch ($c) {
                    'R' { }
                    'A' { $skipAll = $true; $r.Skipped++; $done = $true }
                    'Q' { $r.Skipped++; return [pscustomobject]$r }
                    default { $r.Skipped++; $done = $true }
                }
            }
        }
    }
    if (-not $script:DryRun) {
        Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object {
                if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
            }
    }
    $verb = if ($script:DryRun) { 'would be deleted' } else { 'deleted' }
    Write-Host ("     {0} files {1}, {2} in use/skipped, {3}" -f $r.Deleted, $verb, $r.Skipped, (Format-Size $r.Bytes)) -ForegroundColor Gray
    return [pscustomobject]$r
}

function Invoke-Cleanup {
    # -Interactive brings back the old per-file Retry/Skip prompt for locked files
    param([switch]$Interactive)
    Write-Head 'Temp files cleanup'
    $interactive = [bool]$Interactive

    $targets = @(
        @{ Path = (Join-Path $env:SystemRoot 'Temp');                                         Label = 'Windows Temp' },
        @{ Path = $env:TEMP;                                                                   Label = 'User Temp (%TEMP%)' },
        @{ Path = (Join-Path $env:LOCALAPPDATA 'CrashDumps');                                  Label = 'App crash dumps' },
        @{ Path = (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive');          Label = 'Error reports (archive)' },
        @{ Path = (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue');            Label = 'Error reports (queue)' },
        @{ Path = (Join-Path $env:SystemRoot 'SoftwareDistribution\Download');                 Label = 'Windows Update download cache'; StopWU = $true }
    )
    $results = @()
    foreach ($t in $targets) {
        $wasRunning = @()
        if ($t.StopWU -and -not $script:DryRun) {
            Write-Info 'Pausing Windows Update + BITS while cleaning their cache...'
            $wasRunning = @(Get-Service -Name wuauserv, bits -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running')
            # sc stop never blocks (Stop-Service can hang on a stuck shared svchost)
            foreach ($s in $wasRunning) { & sc.exe stop $s.Name 2>&1 | Out-Null }
            $deadline = (Get-Date).AddSeconds(15)
            while ((Get-Date) -lt $deadline -and @(Get-Service -Name wuauserv, bits -ErrorAction SilentlyContinue | Where-Object Status -ne 'Stopped').Count) {
                Start-Sleep -Milliseconds 500
            }
            if (@(Get-Service -Name wuauserv -ErrorAction SilentlyContinue | Where-Object Status -ne 'Stopped').Count) {
                Write-Skip 'Windows Update did not pause (probably installing) - its cache was left alone'
                foreach ($s in $wasRunning) { & sc.exe start $s.Name 2>&1 | Out-Null }
                continue
            }
        }
        $results += Clear-Folder -Path $t.Path -Label $t.Label -Interactive $interactive
        foreach ($s in $wasRunning) { & sc.exe start $s.Name 2>&1 | Out-Null }
    }

    if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
        if ($script:DryRun) { Write-Dry 'Delivery Optimization cache' }
        else {
            $r = Invoke-WithTimeout -Seconds 30 -What 'Delivery Optimization cache' -Script { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null; 'ok' }
            if ($r -eq 'ok') { Write-OK 'Delivery Optimization cache cleared' } else { Write-Skip 'Delivery Optimization cache - nothing to clear / not responding' }
        }
    }

    $tot = ($results | Measure-Object -Property Bytes -Sum).Sum
    $del = ($results | Measure-Object -Property Deleted -Sum).Sum
    $skp = ($results | Measure-Object -Property Skipped -Sum).Sum
    Write-Host ""
    Write-Host "  ----------------------------------------" -ForegroundColor Green
    Write-Host "  TOTAL: $del files deleted, $skp skipped, $(Format-Size $tot) freed" -ForegroundColor Green
    Write-Host "  ----------------------------------------" -ForegroundColor Green
    Write-Log "Cleanup total: $del deleted, $skp skipped, $tot bytes"
    Write-Info 'GPU shader caches were kept on purpose (deleting them causes in-game stutter).'
}
