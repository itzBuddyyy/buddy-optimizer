# ==============================================================
#  Startup apps manager (optional)
#  Replaces: Tweak+ Registry.reg "[-HKCU\...\Run]" (which silently
#  DELETED every startup entry, including audio/mouse/keyboard software)
#  and the suite's hard-coded Discord/Steam/Spotify removal.
#  Now: you see every startup entry and pick which ones to disable. It
#  uses the same "StartupApproved" switch as Task Manager, so entries
#  are disabled, not deleted, and can be turned back on anytime.
# ==============================================================

$script:Approved = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'

function Get-StartupEntries {
    $list = @()
    $sources = @(
        @{ Hive = 'HKCU'; Run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKCU:\$script:Approved\Run" },
        @{ Hive = 'HKLM'; Run = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKLM:\$script:Approved\Run" },
        @{ Hive = 'HKLM'; Run = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$script:Approved\Run32" }
    )
    foreach ($s in $sources) {
        $k = Get-Item -LiteralPath $s.Run -ErrorAction SilentlyContinue
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            if ($n -eq '') { continue }
            $list += @{ Name = $n; Approved = $s.Approved; Where = "$($s.Hive) Run"; Command = [string]$k.GetValue($n) }
        }
    }
    $folders = @(
        @{ Path = [Environment]::GetFolderPath('Startup');       Approved = "HKCU:\$script:Approved\StartupFolder"; Where = 'Startup folder (user)' },
        @{ Path = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$script:Approved\StartupFolder"; Where = 'Startup folder (all)' }
    )
    foreach ($f in $folders) {
        foreach ($file in @(Get-ChildItem -LiteralPath $f.Path -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini')) {
            $list += @{ Name = $file.Name; Approved = $f.Approved; Where = $f.Where; Command = $file.FullName }
        }
    }
    foreach ($e in $list) {
        $b = Get-RegValue $e.Approved $e.Name $null
        $e.Enabled = -not ($b -is [byte[]] -and $b.Length -gt 0 -and ($b[0] -band 1))
    }
    return $list
}

function Set-StartupState {
    param($Entry, [bool]$Enable)
    if ($Enable) { $bytes = [byte[]](2,0,0,0,0,0,0,0,0,0,0,0) }
    else {
        $ft = [BitConverter]::GetBytes([DateTime]::Now.ToFileTime())
        $bytes = [byte[]](@(3,0,0,0) + $ft)
    }
    Set-Reg $Entry.Approved $Entry.Name $bytes 'Binary' -Quiet
    $state = if ($Enable) { 'enabled' } else { 'disabled' }
    Write-OK "$($Entry.Name) $state at startup"
}

function Invoke-StartupManager {
    $entries = Get-StartupEntries
    if ($entries.Count -eq 0) { Write-Info 'No startup entries found.'; return }
    # Things a gamer usually wants at boot are never pre-selected
    $keepRx = 'Realtek|Audio|Nahimic|Sonic|Logi|G HUB|Razer|Synapse|Corsair|iCUE|SteelSeries|HyperX|NGENUITY|Wooting|Glorious|Armoury|AMD|Radeon|NVIDIA|Intel|SecurityHealth|Defender|Bluetooth|Synaptics|Elan|Precision'
    $offerRx = 'OneDrive|Teams|Skype|Spotify|EpicGames|Edge|GoogleDrive|Dropbox|Adobe|CCleaner|Opera|uTorrent|Cortana|Copilot|Ubisoft|EADesktop|Origin|Battle\.net|Riot'
    $items = @()
    foreach ($e in $entries) {
        $sel = $e.Enabled -and ($e.Name -match $offerRx) -and ($e.Name -notmatch $keepRx)
        $state = if ($e.Enabled) { 'ON ' } else { 'off' }
        $items += @{ Label = ("[{0}] {1}" -f $state, $e.Name); Note = $e.Where; Selected = $sel; Entry = $e }
    }
    $picked = Select-Items -Items $items -Title 'STARTUP APPS - selected entries will be TOGGLED (ON -> off, off -> ON)'
    Clear-Host
    if ($picked.Count -eq 0) { Write-Info 'No changes.'; return }
    Write-Head 'Startup apps'
    foreach ($p in $picked) {
        $desc = if ($p.Entry.Enabled) { 'disable' } else { 'enable' }
        Write-Host "  $desc  $($p.Entry.Name)" -ForegroundColor Gray
    }
    if (-not (Confirm-Action 'Apply these changes?')) { return }
    foreach ($p in $picked) { Set-StartupState -Entry $p.Entry -Enable (-not $p.Entry.Enabled) }
    Write-Info 'Discord / Steam etc. can still be launched normally; they just do not auto-start.'
}
