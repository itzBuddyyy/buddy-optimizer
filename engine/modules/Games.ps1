# ==============================================================
#  Per-game optimization: Call of Duty (Warzone / Black Ops 7 /
#  Modern Warfare 4), Fortnite, Apex Legends, VALORANT.
#
#  Rules followed for every game:
#   - only the game's own settings file is edited, never game files,
#     so nothing here touches anti-cheat protected data
#   - only keys that already exist in the user's file are changed, and
#     each new value is validated against what the game allows
#   - monitor, resolution, refresh rate, audio devices, sensitivity and
#     key binds are never touched
#   - the file is backed up first; "Restore" puts it back exactly
#   - nothing is written while the game is running (it would overwrite
#     the file on exit)
# ==============================================================

$script:GameDefs = [ordered]@{
    cod      = @{ Procs = '^(cod\d*|BlackOps\d*|ModernWarfare\d*)$';             Ifeo = @('cod.exe') }
    fortnite = @{ Procs = '^(FortniteClient-Win64-Shipping.*|FortniteLauncher)$'; Ifeo = @('FortniteClient-Win64-Shipping.exe') }
    apex     = @{ Procs = '^r5apex.*$';                                          Ifeo = @('r5apex.exe', 'r5apex_dx12.exe') }
    valorant = @{ Procs = '^VALORANT(-Win64-Shipping)?$';                        Ifeo = @('VALORANT-Win64-Shipping.exe') }
}
$script:GameNames = @{ cod = 'Call of Duty'; fortnite = 'Fortnite'; apex = 'Apex Legends'; valorant = 'VALORANT' }
$script:UserEnv = $null

# ---------------- user paths ----------------
# The agent runs elevated; the app passes the signed-in user's folders so the
# right profile is used even if the UAC prompt was answered with another account.

function Get-ProfilesRoot {
    $d = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' 'ProfilesDirectory' '%SystemDrive%\Users'
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$d)).TrimEnd('\')
}

function Test-UnderProfiles([string]$p) {
    if (-not $p) { return $false }
    try { $full = [IO.Path]::GetFullPath($p) } catch { return $false }
    return $full.StartsWith((Get-ProfilesRoot) + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Get-UserPaths {
    $u = [ordered]@{
        Profile  = $env:USERPROFILE
        Local    = $env:LOCALAPPDATA
        Docs     = [Environment]::GetFolderPath('MyDocuments')
        SavedGames = Join-Path $env:USERPROFILE 'Saved Games'
    }
    $e = $script:UserEnv
    if ($e -and $e.userProfile -and (Test-UnderProfiles $e.userProfile) -and (Test-Path -LiteralPath $e.userProfile -PathType Container)) {
        $u.Profile = [IO.Path]::GetFullPath([string]$e.userProfile).TrimEnd('\')
        $u.SavedGames = Join-Path $u.Profile 'Saved Games'
        $u.Local = Join-Path $u.Profile 'AppData\Local'
        $u.Docs  = Join-Path $u.Profile 'Documents'
        if ($e.localAppData -and (Test-UnderProfiles $e.localAppData) -and (Test-Path -LiteralPath $e.localAppData -PathType Container)) { $u.Local = [IO.Path]::GetFullPath([string]$e.localAppData).TrimEnd('\') }
        if ($e.documents -and (Test-Path -LiteralPath $e.documents -PathType Container)) { $u.Docs = [IO.Path]::GetFullPath([string]$e.documents).TrimEnd('\') }
    }
    return $u
}

# ---------------- generic helpers ----------------

function Test-GameRunning([string]$game) {
    $re = $script:GameDefs[$game].Procs
    return [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match $re } | Select-Object -First 1)
}

function Read-TextFile([string]$path) {
    # keeps the exact encoding (BOM or not) and line endings of the original
    $bytes = [IO.File]::ReadAllBytes($path)
    $bom = $false; $unicode = $false
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $bom = $true }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $unicode = $true }
    $enc = if ($unicode) { New-Object System.Text.UnicodeEncoding($false, $true) } else { New-Object System.Text.UTF8Encoding($bom) }
    $text = if ($unicode) { [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) } elseif ($bom) { [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3) } else { [Text.Encoding]::UTF8.GetString($bytes) }
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    return [pscustomobject]@{ Lines = [string[]]($text -split "`r?`n"); NewLine = $nl; Encoding = $enc }
}

function Write-TextFile([string]$path, $doc, [string[]]$lines) {
    $text = [string]::Join($doc.NewLine, $lines)
    $tmp = "$path.buddy-tmp"
    [IO.File]::WriteAllText($tmp, $text, $doc.Encoding)
    $attr = (Get-Item -LiteralPath $path -Force).Attributes
    if ($attr -band [IO.FileAttributes]::ReadOnly) { Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false }
    try { [IO.File]::Copy($tmp, $path, $true) } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Test-IsNumber([string]$s) { $d = 0.0; return [double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d) }

function Format-LikeCurrent([string]$current, [string]$new) {
    # 100 -> 100.000000 when the game writes decimals for that key (and back)
    if ((Test-IsNumber $current) -and (Test-IsNumber $new)) {
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $v = [double]::Parse($new, $inv)
        if ($current -match '\.(\d+)$') { return $v.ToString('F' + $Matches[1].Length, $inv) }
        if ($v -eq [math]::Floor($v)) { return ([long]$v).ToString($inv) }
    }
    return $new
}

function Test-ValueCompatible([string]$current, [string]$new) {
    if ($current -cmatch '^(true|false)$') { return $new -cmatch '^(true|false)$' }
    if ($current -cmatch '^(True|False)$') { return $new -cmatch '^(True|False)$' }
    if (Test-IsNumber $current) { return (Test-IsNumber $new) }
    return $true
}

# ---------------- backups / restore ----------------

function Test-GameConfigPath([string]$p) {
    if (-not (Test-UnderProfiles $p)) { return $false }
    $name = [IO.Path]::GetFileName($p)
    if ($name -match '^s\.\d+\.\d+\.(bt\.)?cod\d+\.txt[01]?$') { return ($p -match '\\Call of Duty\\players\\') }
    if ($name -eq 'GameUserSettings.ini') { return ($p -match '\\FortniteGame\\Saved\\Config\\|\\VALORANT\\Saved\\Config\\') }
    if ($name -eq 'videoconfig.txt') { return ($p -match '\\Respawn\\Apex\\local\\') }
    return $false
}

function New-GameBackup([string]$game) {
    $dir = Join-Path $script:BackupDir ("games\$game\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return [pscustomobject]@{ Dir = $dir; Entries = (New-Object System.Collections.ArrayList) }
}

function Save-GameBackup($bk) {
    if (-not $bk -or $bk.Entries.Count -eq 0) { if ($bk) { Remove-Item -LiteralPath $bk.Dir -Recurse -Force -ErrorAction SilentlyContinue }; return }
    @{ Created = (Get-Date).ToString('s'); Entries = @($bk.Entries) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $bk.Dir 'manifest.json') -Encoding UTF8
}

function Backup-GameFile($bk, [string]$path) {
    $n = $bk.Entries.Count + 1
    $copy = Join-Path $bk.Dir ("{0:00}-{1}" -f $n, [IO.Path]::GetFileName($path))
    Copy-Item -LiteralPath $path -Destination $copy -Force -ErrorAction Stop
    $ro = [bool]((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReadOnly)
    $entry = [ordered]@{ Type = 'File'; Path = $path; Backup = $copy; ReadOnly = $ro }
    [void]$bk.Entries.Add($entry)
    [void]$script:Journal.Add($entry)          # the whole-session Undo restores it too
    Save-Journal
}

function Get-RegSnapshot([string]$Path, [string]$Name) {
    $e = [ordered]@{ Type = 'Reg'; Path = $Path; Name = $Name; Existed = $false; Kind = $null; Value = $null }
    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($key.GetValueNames() -contains $Name) {
            $e.Existed = $true; $e.Kind = $key.GetValueKind($Name).ToString(); $e.Value = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
        }
    } catch { }
    return $e
}

function Restore-GameFileEntry($e) {
    # used by game Restore and by session Undo; refuses anything that is not a known game settings file
    $backup = [IO.Path]::GetFullPath([string]$e.Backup)
    if (-not $backup.StartsWith([IO.Path]::GetFullPath($script:BackupDir) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "backup outside the backup folder: $backup" }
    if (-not (Test-GameConfigPath ([string]$e.Path))) { throw "not a game settings file: $($e.Path)" }
    if (-not (Test-Path -LiteralPath $backup)) { throw "backup missing: $backup" }
    if (Test-Path -LiteralPath $e.Path) { Set-ItemProperty -LiteralPath $e.Path -Name IsReadOnly -Value $false }
    Copy-Item -LiteralPath $backup -Destination $e.Path -Force -ErrorAction Stop
    Set-ItemProperty -LiteralPath $e.Path -Name IsReadOnly -Value ([bool]$e.ReadOnly)
}

function Get-GameBackups([string]$game) {
    $root = Join-Path $script:BackupDir "games\$game"
    @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}-\d{6}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json')) } |
        Sort-Object Name -Descending)
}

function Restore-GameSettings([string]$game) {
    if (-not $script:GameDefs.Contains($game)) { throw "Unknown game: $game" }
    Write-Head "Restore $($script:GameNames[$game]) settings"
    if (Test-GameRunning $game) { Write-Fail 'Close the game first - it rewrites its settings file when it exits.'; return }
    $last = Get-GameBackups $game | Select-Object -First 1
    if (-not $last) { Write-Skip 'No backup to restore yet.'; return }
    $entries = @((Get-Content -LiteralPath (Join-Path $last.FullName 'manifest.json') -Raw | ConvertFrom-Json).Entries)
    if ($script:DryRun) { Write-Dry "restore $($entries.Count) items from $($last.Name)"; return }
    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        $e = $entries[$i]
        try {
            Restore-JournalEntry $e
            $what = if ($e.Type -eq 'File') { [IO.Path]::GetFileName($e.Path) } else { "$($e.Path | Split-Path -Leaf)\$($e.Name)" }
            Write-OK "Restored $what"
        } catch { Write-Fail "$($e.Path) - $($_.Exception.Message)" }
    }
    Rename-Item -LiteralPath $last.FullName -NewName "$($last.Name).restored" -ErrorAction SilentlyContinue
}

# ---------------- edit engines ----------------

function Update-CodFile([string]$path, [System.Collections.Specialized.OrderedDictionary]$want, $bk) {
    # Name@index -> value (or array of candidates, first valid wins)
    $doc = Read-TextFile $path
    $lines = [string[]]$doc.Lines.Clone()
    $re = '^(?<name>[A-Za-z0-9_]+)@(?<idx>\d+);(?<hash>[^=]*?)\s*=\s?(?<val>.*?)(?<cmt>\s+//\s.*)?$'
    $changed = 0; $same = 0; $rejected = New-Object System.Collections.ArrayList; $found = @{}
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $m = [regex]::Match($lines[$i], $re)
        if (-not $m.Success) { continue }
        $key = $m.Groups['name'].Value + '@' + $m.Groups['idx'].Value
        if (-not $want.Contains($key)) { continue }
        $found[$key] = $true
        $cur = $m.Groups['val'].Value.Trim()
        $cmt = $m.Groups['cmt'].Value
        $pick = $null
        foreach ($cand in @($want[$key])) {
            $v = Format-LikeCurrent $cur ([string]$cand)
            if ($cmt -match '//\s*one of\s+(.+)$') {
                $opts = @($Matches[1].Trim() -split ',\s*')
                if ($opts -ccontains $v) { $pick = $v; break }
            } elseif ($cmt -match '//\s*(-?[\d.]+)\s+to\s+(-?[\d.]+)\s*$') {
                $inv = [Globalization.CultureInfo]::InvariantCulture
                if ((Test-IsNumber $v) -and [double]::Parse($v, $inv) -ge [double]::Parse($Matches[1], $inv) -and [double]::Parse($v, $inv) -le [double]::Parse($Matches[2], $inv)) { $pick = $v; break }
            } elseif (Test-ValueCompatible $cur $v) { $pick = $v; break }
        }
        if ($null -eq $pick) { [void]$rejected.Add($key); continue }
        if ($pick -ceq $cur) { $same++; continue }
        $prefix = $lines[$i].Substring(0, $m.Groups['val'].Index)
        $lines[$i] = $prefix + $pick + $cmt
        Write-Log "  $([IO.Path]::GetFileName($path)): $key  $cur -> $pick"
        $changed++
    }
    $missing = @($want.Keys | Where-Object { -not $found.ContainsKey($_) }).Count
    return Complete-ConfigEdit $path $doc $lines $changed $same $missing $rejected $bk
}

function Update-IniFile([string]$path, [hashtable]$want, $bk) {
    # $want: section -> ordered (key -> value). Only existing keys are changed.
    $doc = Read-TextFile $path
    $lines = [string[]]$doc.Lines.Clone()
    $section = ''
    $changed = 0; $same = 0; $rejected = New-Object System.Collections.ArrayList; $total = 0
    foreach ($s in $want.Keys) { $total += $want[$s].Count }
    $hits = 0
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $l = $lines[$i]
        if ($l -match '^\s*\[(.+)\]\s*$') { $section = $Matches[1]; continue }
        if (-not $want.ContainsKey($section)) { continue }
        if ($l -notmatch '^(?<k>[^=;\s][^=]*?)=(?<v>.*)$') { continue }
        $k = $Matches['k']; $cur = $Matches['v']
        if (-not $want[$section].Contains($k)) { continue }
        $hits++
        $v = Format-LikeCurrent $cur ([string]$want[$section][$k])
        if (-not (Test-ValueCompatible $cur $v)) { [void]$rejected.Add($k); continue }
        if ($v -ceq $cur) { $same++; continue }
        $lines[$i] = "$k=$v"
        Write-Log "  $([IO.Path]::GetFileName($path)) [$section] $k  $cur -> $v"
        $changed++
    }
    return Complete-ConfigEdit $path $doc $lines $changed $same ($total - $hits) $rejected $bk
}

function Update-ApexVideoConfig([string]$path, [System.Collections.Specialized.OrderedDictionary]$want, $bk) {
    $doc = Read-TextFile $path
    $lines = [string[]]$doc.Lines.Clone()
    $re = '^(?<pre>\s*"(?<k>setting\.[^"]+)"\s+")(?<v>[^"]*)(?<post>".*)$'
    $changed = 0; $same = 0; $rejected = New-Object System.Collections.ArrayList; $found = @{}
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $m = [regex]::Match($lines[$i], $re)
        if (-not $m.Success) { continue }
        $k = $m.Groups['k'].Value
        if (-not $want.Contains($k)) { continue }
        $found[$k] = $true
        $cur = $m.Groups['v'].Value
        $v = [string]$want[$k]
        if (-not ((Test-IsNumber $cur) -and (Test-IsNumber $v))) { [void]$rejected.Add($k); continue }
        if ($v -ceq $cur) { $same++; continue }
        $lines[$i] = $m.Groups['pre'].Value + $v + $m.Groups['post'].Value
        Write-Log "  videoconfig.txt: $k  $cur -> $v"
        $changed++
    }
    $missing = @($want.Keys | Where-Object { -not $found.ContainsKey($_) }).Count
    return Complete-ConfigEdit $path $doc $lines $changed $same $missing $rejected $bk
}

function Complete-ConfigEdit($path, $doc, $lines, $changed, $same, $missing, $rejected, $bk) {
    $name = [IO.Path]::GetFileName($path)
    $where = Split-Path -Leaf (Split-Path -Parent $path)
    $tail = @()
    if ($same) { $tail += "$same already optimal" }
    if ($missing) { $tail += "$missing not in this game version" }
    if ($rejected.Count) { $tail += "$($rejected.Count) not supported here"; Write-Log "  rejected: $($rejected -join ', ')" }
    $suffix = if ($tail) { ' (' + ($tail -join ', ') + ')' } else { '' }
    if ($changed -eq 0) { Write-Skip "${name}: nothing to change$suffix"; return $false }
    if ($script:DryRun) { Write-Dry "${name} [$where]: $changed settings would change$suffix"; return $true }
    Backup-GameFile $bk $path
    Write-TextFile $path $doc $lines
    # read it back: same line count and our values present
    $check = Read-TextFile $path
    if ($check.Lines.Length -ne $lines.Length) { Restore-GameFileEntry $bk.Entries[$bk.Entries.Count - 1]; Write-Fail "${name}: verification failed, original restored"; return $false }
    Write-OK "${name} [$where]: $changed settings optimized$suffix"
    return $true
}

# ---------------- discovery ----------------

function Get-SteamLibraries {
    $libs = New-Object System.Collections.ArrayList
    $steam = Get-RegValue 'HKCU:\Software\Valve\Steam' 'SteamPath' $null
    if (-not $steam) { $steam = Get-RegValue 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath' $null }
    if (-not $steam) { return @() }
    $steam = ([string]$steam) -replace '/', '\'
    [void]$libs.Add($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
            $p = $m.Groups[1].Value -replace '\\\\', '\'
            if ($libs -notcontains $p) { [void]$libs.Add($p) }
        }
    }
    return @($libs)
}

function Get-CanonicalPath([string]$p) {
    # real on-disk casing (Steam reports paths in lower case)
    try {
        $full = [IO.Path]::GetFullPath($p)
        $cur = [IO.Path]::GetPathRoot($full).ToUpperInvariant()
        foreach ($seg in $full.Substring($cur.Length).Split([char]92)) {
            if (-not $seg) { continue }
            $hit = @([IO.Directory]::GetFileSystemEntries($cur, $seg)) | Select-Object -First 1
            if (-not $hit) { return $full }
            $cur = $hit
        }
        return $cur
    } catch { return $p }
}

function Find-GameExes([string]$game) {
    $out = New-Object System.Collections.ArrayList
    $add = { param($p) if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { $c = Get-CanonicalPath $p; if ($out -notcontains $c) { [void]$out.Add($c) } } }
    $steamLibs = Get-SteamLibraries
    switch ($game) {
        'cod' {
            $roots = New-Object System.Collections.ArrayList
            foreach ($l in $steamLibs) { foreach ($n in 'Call of Duty HQ', 'Call of Duty') { [void]$roots.Add((Join-Path $l "steamapps\common\$n")) } }
            foreach ($u in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
                foreach ($k in @(Get-ItemProperty $u -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'Call of Duty*' -and $_.InstallLocation })) { [void]$roots.Add([string]$k.InstallLocation) }
            }
            foreach ($r in $roots) {
                if (-not (Test-Path -LiteralPath $r -PathType Container)) { continue }
                foreach ($f in @(Get-ChildItem -LiteralPath $r -Filter '*.exe' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^cod\d*\.exe$' })) { & $add $f.FullName }
            }
        }
        'fortnite' {
            $man = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
            foreach ($f in @(Get-ChildItem -LiteralPath $man -Filter '*.item' -ErrorAction SilentlyContinue)) {
                try { $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }
                if ($j.AppName -eq 'Fortnite' -and $j.InstallLocation) { & $add (Join-Path $j.InstallLocation 'FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe') }
            }
        }
        'apex' {
            $roots = New-Object System.Collections.ArrayList
            foreach ($l in $steamLibs) { [void]$roots.Add((Join-Path $l 'steamapps\common\Apex Legends')) }
            $ea = Get-RegValue 'HKLM:\SOFTWARE\Respawn\Apex' 'Install Dir' $null
            if ($ea) { [void]$roots.Add([string]$ea) }
            foreach ($r in $roots) { foreach ($n in 'r5apex.exe', 'r5apex_dx12.exe') { & $add (Join-Path $r $n) } }
        }
        'valorant' {
            $roots = New-Object System.Collections.ArrayList
            $yaml = Join-Path $env:ProgramData 'Riot Games\Metadata\valorant.live\valorant.live.product_settings.yaml'
            if (Test-Path -LiteralPath $yaml) {
                $m = [regex]::Match((Get-Content -LiteralPath $yaml -Raw), 'product_install_full_path:\s*"?([^"\r\n]+)"?')
                if ($m.Success) { [void]$roots.Add(($m.Groups[1].Value.Trim() -replace '/', '\')) }
            }
            [void]$roots.Add("$env:SystemDrive\Riot Games\VALORANT\live")
            foreach ($r in $roots) { & $add (Join-Path $r 'ShooterGame\Binaries\Win64\VALORANT-Win64-Shipping.exe') }
        }
    }
    return @($out)
}

function Find-GameConfigs([string]$game) {
    $u = Get-UserPaths
    $out = New-Object System.Collections.ArrayList
    switch ($game) {
        'cod' {
            foreach ($d in (Join-Path $u.Local 'Activision\Call of Duty\players'), (Join-Path $u.Docs 'Call of Duty\players')) {
                foreach ($f in @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^s\.\d+\.\d+\.(bt\.)?cod(\d+)\.txt[01]?$' })) {
                    $null = $f.Name -match '^s\.\d+\.\d+\.(bt\.)?cod(\d+)\.'
                    $num = [int]$Matches[2]; $beta = [bool]$Matches[1]
                    $label = switch ($num) { 25 { 'Warzone / Black Ops 7' } 26 { 'Modern Warfare 4' } default { "Call of Duty (cod$num)" } }
                    if ($beta) { $label += ' Beta' }
                    [void]$out.Add([pscustomobject]@{ Path = $f.FullName; Name = $f.Name; Label = $label; Profile = $(if ($num -ge 26) { 'cod26' } else { 'cod25' }); Modified = $f.LastWriteTime.ToString('s') })
                }
            }
        }
        'fortnite' {
            $f = Join-Path $u.Local 'FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini'
            if (Test-Path -LiteralPath $f) { [void]$out.Add([pscustomobject]@{ Path = $f; Name = 'GameUserSettings.ini'; Label = 'Fortnite'; Profile = 'fortnite'; Modified = (Get-Item -LiteralPath $f).LastWriteTime.ToString('s') }) }
        }
        'apex' {
            $f = Join-Path $u.SavedGames 'Respawn\Apex\local\videoconfig.txt'
            if (Test-Path -LiteralPath $f) { [void]$out.Add([pscustomobject]@{ Path = $f; Name = 'videoconfig.txt'; Label = 'Apex Legends'; Profile = 'apex'; Modified = (Get-Item -LiteralPath $f).LastWriteTime.ToString('s') }) }
        }
        'valorant' {
            $root = Join-Path $u.Local 'VALORANT\Saved\Config'
            $cands = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'Windows\GameUserSettings.ini' })
            foreach ($f in $cands) {
                if (-not (Test-Path -LiteralPath $f)) { continue }
                $acct = Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $f))
                $label = if ($acct -eq 'Windows') { 'VALORANT (default)' } else { "VALORANT account $($acct.Substring(0, [Math]::Min(8, $acct.Length)))" }
                [void]$out.Add([pscustomobject]@{ Path = $f; Name = 'GameUserSettings.ini'; Label = $label; Profile = 'valorant'; Modified = (Get-Item -LiteralPath $f).LastWriteTime.ToString('s') })
            }
            $plain = Join-Path $root 'Windows\GameUserSettings.ini'
            if ((Test-Path -LiteralPath $plain) -and -not ($out | Where-Object { $_.Path -eq $plain })) { [void]$out.Add([pscustomobject]@{ Path = $plain; Name = 'GameUserSettings.ini'; Label = 'VALORANT (default)'; Profile = 'valorant'; Modified = (Get-Item -LiteralPath $plain).LastWriteTime.ToString('s') }) }
        }
    }
    # never offer a file that Restore would refuse to put back
    return @($out | Where-Object { Test-GameConfigPath $_.Path })
}

function Get-GamesState {
    $multiGpu = (@($script:Sys.GpuVendors).Count -gt 1) -or ([string]$script:Sys.GPU -match ' \+ ')
    foreach ($g in $script:GameDefs.Keys) {
        $cfg = @(Find-GameConfigs $g)
        $exe = @(Find-GameExes $g)
        $bk = Get-GameBackups $g | Select-Object -First 1
        [ordered]@{
            id = $g
            detected = ($cfg.Count -gt 0 -or $exe.Count -gt 0)
            running = (Test-GameRunning $g)
            configs = @($cfg | ForEach-Object { [ordered]@{ name = $_.Name; label = $_.Label; folder = (Split-Path -Leaf (Split-Path -Parent $_.Path)); modified = $_.Modified } })
            exes = @($exe)
            lastBackup = $(if ($bk) { $bk.CreationTime.ToString('s') } else { $null })
            multiGpu = $multiGpu
        }
    }
}

# ---------------- profiles ----------------

function Get-CodWant([string]$profile, $o) {
    $j = Get-Content -LiteralPath (Join-Path $script:FilesDir 'games\cod.json') -Raw | ConvertFrom-Json
    $p = $j.$profile
    $want = [ordered]@{}
    foreach ($grp in 'graphics', 'display') { foreach ($pr in $p.$grp.PSObject.Properties) { $want[$pr.Name] = [string]$pr.Value } }
    if ($o.clutter) { foreach ($pr in $j.clutter.PSObject.Properties) { $want[$pr.Name] = [string]$pr.Value } }
    if ($o.audio)   { foreach ($pr in $j.audio.PSObject.Properties)   { $want[$pr.Name] = [string]$pr.Value } }

    $v = @($script:Sys.GpuVendors)
    $nv = $v -contains 'NVIDIA'
    if ($nv) { $want['NvidiaReflex@0'] = 'Enabled' }
    elseif ($v -contains 'AMD') { $want['AmdAntilag2@0'] = 'true' }
    # frame generation adds input latency
    $want['DLSSFrameGeneration@0'] = 'false'; $want['FSRFrameInterpolation@0'] = 'false'; $want['IntelXeFG@0'] = 'false'
    if ($p.upscaler -eq 'dlss-on-nvidia' -and $nv) {
        $want['AATechniquePreferredMP@0'] = @('DLSS', 'SMAA')
        $want['DLSSModeMP@0'] = 'DLSS'
        $want['DLSSPerfModeMP@0'] = 'Maximum Performance'
        $want['DLSSModelUI@0'] = @('TRANSFORMER', 'CNN')
        $want['AMDFidelityFX@0'] = 'Off'; $want['AMDFidelityFX@1'] = 'Off'
    } else {
        # native resolution + SMAA, sharpened with AMD CAS (works on every GPU)
        $want['AATechniquePreferredMP@0'] = 'SMAA'
        $want['AMDFidelityFX@0'] = 'CAS'; $want['AMDFidelityFX@1'] = 'CAS'
        $want['AMDContrastAdaptiveSharpeningStrength@0'] = '0.700000'
    }
    $cores = 0
    foreach ($c in @(Get-CimSafe Win32_Processor)) { $cores += [int]$c.NumberOfCores }
    if ($cores -gt 0) { $want['RendererWorkerCount@0'] = [string][Math]::Max(2, [Math]::Min(16, $cores - 1)) }
    return $want
}

function Get-FortniteWant($o) {
    $sg = [ordered]@{}
    $sg['sg.ResolutionQuality'] = '100'
    foreach ($k in 'ViewDistance', 'AntiAliasing', 'Shadow', 'GlobalIllumination', 'Reflection', 'PostProcess', 'Texture', 'Effects', 'Foliage', 'Shading', 'Landscape') { $sg["sg.${k}Quality"] = '0' }
    $fort = [ordered]@{
        'bUseVSync' = 'False'; 'FrameRateLimit' = '0.000000'; 'bMotionBlur' = 'False'; 'bShowGrass' = 'False'
        'bRayTracing' = 'False'; 'bUseNanite' = 'False'; 'bDisableMouseAcceleration' = 'True'
        'FullscreenMode' = '0'; 'LastConfirmedFullscreenMode' = '0'; 'PreferredFullscreenMode' = '0'
    }
    $want = @{ 'ScalabilityGroups' = $sg; '/Script/FortniteGame.FortGameUserSettings' = $fort }
    # Performance rendering mode (Epic's documented "-FeatureLevelES31")
    if ($o.performanceMode) { $want['D3DRHIPreference'] = [ordered]@{ 'PreferredFeatureLevel' = 'es31' } }
    return $want
}

function Get-ValorantWant {
    $sg = [ordered]@{ 'sg.ResolutionQuality' = '100' }
    # anti-aliasing is left alone: MSAA helps target clarity in VALORANT
    foreach ($k in 'ViewDistance', 'Shadow', 'PostProcess', 'Texture', 'Effects', 'Foliage', 'Shading') { $sg["sg.${k}Quality"] = '0' }
    $gus = [ordered]@{ 'bUseVSync' = 'False'; 'bUseDynamicResolution' = 'False'; 'FullscreenMode' = '0'; 'LastConfirmedFullscreenMode' = '0'; 'PreferredFullscreenMode' = '0' }
    return @{ 'ScalabilityGroups' = $sg; '/Script/ShooterGame.ShooterGameUserSettings' = $gus }
}

function Get-ApexWant {
    $w = [ordered]@{}
    $w['setting.mat_vsync_mode'] = '0'            # V-Sync off
    $w['setting.mat_triplebuffered'] = '0'
    $w['setting.fullscreen'] = '1'                # exclusive fullscreen
    $w['setting.nowindowborder'] = '0'
    $w['setting.dvs_enable'] = '0'                # adaptive resolution FPS target off
    $w['setting.csm_enabled'] = '0'               # sun shadows off
    $w['setting.shadow_enable'] = '0'             # spot shadows off
    $w['setting.ssao_enabled'] = '0'              # ambient occlusion off
    $w['setting.volumetric_lighting'] = '0'
    $w['setting.mat_depthfeather_enable'] = '0'   # ADS depth of field off
    $w['setting.cl_ragdoll_self_collision'] = '0'
    $w['setting.cl_gib_allow'] = '0'
    $w['setting.r_createmodeldecals'] = '0'       # impact marks off
    $w['setting.particle_cpu_level'] = '0'
    return $w
}

# ---------------- Windows-side tweaks for the game executables ----------------

function Set-GameGpuPreference([string[]]$exes) {
    $key = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    foreach ($exe in $exes) {
        $cur = [string](Get-RegValue $key $exe '')
        $pairs = [ordered]@{}
        foreach ($p in ($cur -split ';')) { if ($p -match '^\s*([^=]+)=(.*)$') { $pairs[$Matches[1].Trim()] = $Matches[2].Trim() } }
        if ($pairs['GpuPreference'] -eq '2') { Write-Skip "High-performance GPU already set: $([IO.Path]::GetFileName($exe))"; continue }
        $pairs['GpuPreference'] = '2'
        $val = (($pairs.Keys | ForEach-Object { "$_=$($pairs[$_])" }) -join ';') + ';'
        $script:GameBk.Entries.Add((Get-RegSnapshot $key $exe)) | Out-Null
        Set-Reg $key $exe $val 'String' -Quiet
        if (-not $script:DryRun) { Write-OK "High-performance GPU: $([IO.Path]::GetFileName($exe))" }
    }
}

function Set-GamePriority([string[]]$names) {
    foreach ($n in $names) {
        $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$n\PerfOptions"
        if ([int](Get-RegValue $key 'CpuPriorityClass' 0) -eq 3) { Write-Skip "High CPU priority already set: $n"; continue }
        $script:GameBk.Entries.Add((Get-RegSnapshot $key 'CpuPriorityClass')) | Out-Null
        Set-Reg $key 'CpuPriorityClass' 3 'DWord' -Quiet
        if (-not $script:DryRun) { Write-OK "High CPU priority: $n" }
    }
}

# ---------------- main entry ----------------

function Invoke-GameOptimize {
    param([Parameter(Mandatory)][string]$Game, $Options)
    if (-not $script:GameDefs.Contains($Game)) { throw "Unknown game: $Game" }
    $o = @{ config = $true; clutter = $true; audio = $false; performanceMode = $true; readOnly = $false; gpuPref = $true; priority = $false }
    if ($Options) { foreach ($p in $Options.PSObject.Properties) { if ($o.ContainsKey($p.Name)) { $o[$p.Name] = [bool]$p.Value } } }
    Write-Head "$($script:GameNames[$Game]) - competitive settings"

    $script:GameBk = if ($script:DryRun) { [pscustomobject]@{ Dir = $null; Entries = (New-Object System.Collections.ArrayList) } } else { New-GameBackup $Game }
    try {
        if ($o.config) {
            $cfgs = @(Find-GameConfigs $Game)
            if ($cfgs.Count -eq 0) {
                Write-Skip 'No settings file found yet - start the game once, set your resolution, close it, then run this again.'
            } elseif (Test-GameRunning $Game) {
                Write-Fail 'The game is running. Close it completely first - it rewrites its settings file when it exits.'
            } else {
                $pre = ''
                foreach ($c in $cfgs) {
                    try {
                        $done = switch ($c.Profile) {
                            { $_ -like 'cod*' } { Update-CodFile $c.Path (Get-CodWant $c.Profile $o) $script:GameBk }
                            'fortnite'          { Update-IniFile $c.Path (Get-FortniteWant $o) $script:GameBk }
                            'valorant'          { Update-IniFile $c.Path (Get-ValorantWant) $script:GameBk }
                            'apex'              { Update-ApexVideoConfig $c.Path (Get-ApexWant) $script:GameBk }
                        }
                        if ($Game -eq 'apex' -and $o.readOnly -and -not $script:DryRun) {
                            if (-not ($script:GameBk.Entries | Where-Object { $_.Type -eq 'File' -and $_.Path -eq $c.Path })) { Backup-GameFile $script:GameBk $c.Path }
                            Set-ItemProperty -LiteralPath $c.Path -Name IsReadOnly -Value $true
                            Write-OK 'videoconfig.txt locked (read-only) so the game keeps these values'
                        }
                    } catch { Write-Fail "$($c.Name): $($_.Exception.Message)" }
                }
            }
        }
        $exes = @(Find-GameExes $Game)
        if ($o.gpuPref) {
            $multi = (@($script:Sys.GpuVendors).Count -gt 1) -or ([string]$script:Sys.GPU -match ' \+ ')
            if (-not $multi) { Write-Skip 'Only one GPU in this PC - the game already uses it.' }
            elseif ($exes.Count -eq 0) { Write-Skip 'Game install folder not found - GPU preference skipped.' }
            else { Set-GameGpuPreference $exes }
        }
        if ($o.priority) {
            $ifeo = @($script:GameDefs[$Game].Ifeo) + @($exes | ForEach-Object { [IO.Path]::GetFileName($_) })
            Set-GamePriority @($ifeo | Select-Object -Unique)
        }
    } finally {
        if (-not $script:DryRun) { Save-GameBackup $script:GameBk }
        $script:GameBk = $null
    }
}
