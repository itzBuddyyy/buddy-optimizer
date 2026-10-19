# ==============================================================
#  Undo / restore
#  Every itzBuddy session writes a journal of the previous registry
#  values, service start types and undo commands. This replays it
#  backwards. (The old suite's "restore helper" re-imported raw .reg
#  exports, which could not remove values it had added.)
# ==============================================================

function Restore-JournalEntry {
    param($e)
    switch ($e.Type) {
        'Reg' {
            $name = if ($e.Name -eq '') { '(default)' } else { $e.Name }
            if ($e.Existed) {
                $val = $e.Value
                switch ($e.Kind) {
                    'Binary'      { $val = [byte[]]@($val) }
                    'MultiString' { $val = [string[]]@($val) }
                    'DWord'       { $val = [int]$val }
                    'QWord'       { $val = [long]$val }
                }
                if (-not (Test-Path -LiteralPath $e.Path)) { New-Item -Path $e.Path -Force | Out-Null }
                New-ItemProperty -LiteralPath $e.Path -Name $name -Value $val -PropertyType $e.Kind -Force -ErrorAction Stop | Out-Null
            } else {
                Remove-RegValueRaw -Path $e.Path -Name $e.Name
            }
        }
        'File' { Restore-GameFileEntry $e }
        'Cmd' {
            $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $($e.Undo)" -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -ne 0) { throw "exit code $($p.ExitCode): $($e.Undo)" }
        }
    }
}

function Invoke-Undo {
    Write-Head 'Undo a previous itzBuddy session'
    $files = @(Get-ChildItem -LiteralPath $script:BackupDir -Filter 'session-*.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($files.Count -eq 0) { Write-Info 'No saved sessions yet.'; return }
    for ($i = 0; $i -lt [Math]::Min($files.Count, 15); $i++) {
        $j = Get-Content -LiteralPath $files[$i].FullName -Raw | ConvertFrom-Json
        Write-Host ("  {0,2}  {1}   {2} changes" -f ($i + 1), $files[$i].LastWriteTime.ToString('yyyy-MM-dd HH:mm'), @($j.Entries).Count) -ForegroundColor White
    }
    Write-Host "   R  Open Windows System Restore instead" -ForegroundColor DarkGray
    $c = (Read-Host '  Session number to undo (ENTER = cancel)').Trim().ToUpper()
    if ($c -eq 'R') { Start-Process rstrui.exe; return }
    if ($c -notmatch '^\d+$' -or [int]$c -lt 1 -or [int]$c -gt $files.Count) { return }
    $file = $files[[int]$c - 1]
    $j = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    Write-Warn "This restores $(@($j.Entries).Count) values/commands to how they were before that session."
    Write-Info 'Removed apps (Debloat) and deleted temp files cannot be brought back this way.'
    if (-not (Confirm-Action 'Undo this session?' -DefaultNo)) { return }
    Undo-SessionFile -Path $file.FullName
}

function Get-UndoSessions {
    # For the app: list of saved sessions (newest first)
    foreach ($f in @(Get-ChildItem -LiteralPath $script:BackupDir -Filter 'session-*.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
        $count = 0
        try { $count = @((Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json).Entries).Count } catch { }
        [pscustomobject]@{ File = $f.Name; Date = $f.LastWriteTime.ToString('s'); Changes = $count; Undone = ($f.Name -like '*.undone.json') }
    }
}

function Undo-SessionFile {
    param([Parameter(Mandatory)][string]$Path)
    # only files inside the backup folder can be replayed
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith([IO.Path]::GetFullPath($script:BackupDir), [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full)) {
        Write-Fail "Not a valid session file: $Path"; return
    }
    $file = Get-Item -LiteralPath $full
    $entries = @((Get-Content -LiteralPath $full -Raw | ConvertFrom-Json).Entries)
    if ($script:DryRun) { Write-Dry "undo $($file.Name) ($($entries.Count) entries)"; return }
    $ok = 0; $fail = 0
    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        try { Restore-JournalEntry $entries[$i]; $ok++ }
        catch {
            $fail++
            $what = if ($entries[$i].Type -eq 'Reg') { "$($entries[$i].Path)\$($entries[$i].Name)" } elseif ($entries[$i].Type -eq 'File') { $entries[$i].Path } else { $entries[$i].Description }
            Write-Fail "$what - $($_.Exception.Message)"
        }
    }
    Write-OK "$ok entries restored, $fail failed"
    Rename-Item -LiteralPath $file.FullName -NewName ($file.Name -replace '\.json$', '.undone.json') -ErrorAction SilentlyContinue
    $script:RebootNeeded = $true
}
