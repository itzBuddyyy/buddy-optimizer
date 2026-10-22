<#
    itzBuddy engine agent - headless mode for the Buddy Optimizer app.

    The app starts this script elevated (one UAC prompt per app session) and
    talks to it over a private named pipe. Protocol: one JSON object per line.

      app -> agent   {"id":7,"cmd":"run","action":"gaming","args":{...},"dryRun":false,"xboxMode":true}
      agent -> app   {"type":"log","id":7,"level":"ok","text":"..."}
                     {"type":"result","id":7,"ok":true,"data":...,"stats":{...},"reboot":true}

    The agent first sends its one-time proof; the app's first message must then
    carry the one-time token (both passed on the command line), otherwise the
    agent exits. Every action reuses the console
    suite's modules, so behaviour, journaling and undo are identical.
#>
param(
    [Parameter(Mandatory)][string]$PipeName,
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$Proof,
    [Parameter(Mandatory)][int]$AppPid
)

$ErrorActionPreference = 'Continue'
$script:Root     = Split-Path -Parent $PSCommandPath
$script:FilesDir = Join-Path $script:Root 'files'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { exit 5 }

. (Join-Path $script:Root 'lib\Core.ps1')
foreach ($m in Get-ChildItem -LiteralPath (Join-Path $script:Root 'modules') -Filter '*.ps1' | Sort-Object Name) { . $m.FullName }

# ---- pipe ----
$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $PipeName, [System.IO.Pipes.PipeDirection]::InOut)
try { $pipe.Connect(15000) } catch { exit 2 }
# The secrets travel on a command line that same-user processes can read, so also
# require that the pipe server is the app process that launched us.
Add-Type -Namespace itzBuddy -Name PipeInfo -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetNamedPipeServerProcessId(Microsoft.Win32.SafeHandles.SafePipeHandle pipe, out uint pid);'
$serverPid = [uint32]0
if (-not [itzBuddy.PipeInfo]::GetNamedPipeServerProcessId($pipe.SafePipeHandle, [ref]$serverPid) -or $serverPid -ne $AppPid) { exit 6 }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$reader = New-Object System.IO.StreamReader($pipe, $utf8)
$writer = New-Object System.IO.StreamWriter($pipe, $utf8)
$writer.AutoFlush = $true
$script:CurrentId = 0

function Send-Message($obj) {
    try { $writer.WriteLine(($obj | ConvertTo-Json -Compress -Depth 8)) } catch { exit 3 }
}

# ---- headless overrides: stream every log line to the app, never block on input ----
function Send-Log([string]$level, [string]$text) { Send-Message ([ordered]@{ type = 'log'; id = $script:CurrentId; level = $level; text = $text }) }
function Write-OK   { param([string]$m) if ($script:DryRun) { $script:Stats.DRY++; Send-Log 'dry' $m; Write-Log "[DRY]  $m"; return }; $script:Stats.OK++; Send-Log 'ok' $m; Write-Log "[OK]   $m" }
function Write-Skip { param([string]$m) $script:Stats.SKIP++; Send-Log 'skip' $m; Write-Log "[SKIP] $m" }
function Write-Fail { param([string]$m) $script:Stats.FAIL++; Send-Log 'fail' $m; Write-Log "[FAIL] $m" }
function Write-Info { param([string]$m) Send-Log 'info' $m; Write-Log "[INFO] $m" }
function Write-Warn { param([string]$m) Send-Log 'warn' $m; Write-Log "[WARN] $m" }
function Write-Head { param([string]$m) Send-Log 'head' $m; Write-Log "=== $m ===" }
function Write-Dry  { param([string]$m) $script:Stats.DRY++; Send-Log 'dry' $m; Write-Log "[DRY]  $m" }
function Read-Host  { param($Prompt) return '' }
function Clear-Host { }
function Write-Host { param([Parameter(Position = 0, ValueFromRemainingArguments)]$Object, $ForegroundColor, $BackgroundColor, [switch]$NoNewline)
    $t = ($Object -join ' ').Trim(); if ($t) { Send-Log 'text' $t } }
$script:AutoYes = $true

# ---- auth handshake: prove ourselves first, then check the app's token ----
try { $writer.WriteLine((@{ proof = $Proof } | ConvertTo-Json -Compress)) } catch { exit 3 }
$hello = $null
try { $hello = $reader.ReadLine() | ConvertFrom-Json } catch { }
if (-not $hello -or $hello.token -ne $Token) { exit 4 }

# The data folder holds the undo journals this elevated agent replays, so only
# Administrators/SYSTEM may write there (ProgramData lets standard users create files).
try {
    New-Item -ItemType Directory -Path $script:DataRoot -Force | Out-Null
    & icacls.exe $script:DataRoot /setowner '*S-1-5-32-544' /T /C /Q | Out-Null
    & icacls.exe $script:DataRoot /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /T /C /Q | Out-Null
} catch { Write-Log "ACL hardening failed: $($_.Exception.Message)" }

Write-Log 'Agent connected to Buddy Optimizer'
[void](Test-WmiHealth)
$script:Sys = Get-SystemProfile
$script:XboxMode = $script:Sys.XboxInstalled
Send-Message ([ordered]@{ type = 'ready'; sys = $script:Sys; wmi = $script:WmiHealthy; xboxDefault = $script:XboxMode; backupDir = $script:BackupDir; logDir = $script:LogDir })

function Invoke-Quick {
    param($a)
    $steps = @(
        @{ Name = 'restorePoint'; Run = { New-RestorePoint } },
        @{ Name = 'power';        Run = { Invoke-PowerPlan -Auto } },
        @{ Name = 'gaming';       Run = { Invoke-GamingCore } },
        @{ Name = 'services';     Run = { Invoke-Services } },
        @{ Name = 'privacy';      Run = { Invoke-Privacy } },
        @{ Name = 'cleanup';      Run = { Invoke-Cleanup } }
    )
    if ($a -and $a.skipRestorePoint) { $steps = $steps | Where-Object { $_.Name -ne 'restorePoint' } }
    $failed = @()
    $i = 0
    foreach ($st in $steps) {
        $i++
        Send-Message ([ordered]@{ type = 'progress'; id = $script:CurrentId; step = $st.Name; index = $i; total = $steps.Count })
        try { & $st.Run } catch { $failed += $st.Name; Write-Fail "$($st.Name) stopped early: $($_.Exception.Message)" }
        Save-Journal
    }
    return @{ failed = $failed }
}

function Invoke-Action([string]$action, $a) {
    switch ($action) {
        'quick'        { return (Invoke-Quick $a) }
        'power'        { $c = if ($a -and $a.choice) { [string]$a.choice } else { '' }; Invoke-PowerPlan -Auto -Choice $c }
        'gaming'       { Invoke-GamingCore }
        'services'     { Invoke-Services }
        'privacy'      { Invoke-Privacy }
        'cleanup'      { Invoke-Cleanup }
        'network'      { Invoke-NetworkReset }
        'deepnet'      { Invoke-DeepNetworkReset }
        'restorePoint' { New-RestorePoint }
        'xboxFix'      { if ($a -and $a.resetStore) { Invoke-XboxFix -ResetStore } else { Invoke-XboxFix -NoStoreReset } }
        'xboxLock'     { Invoke-XboxLockdown }
        'restorePower' { Invoke-RestorePowerPlans }
        'timerInstall' { Install-TimerRes }
        'timerRemove'  { Uninstall-TimerRes }
        'noWuDrivers'  { Set-NoWUDrivers }
        'nvidia'       { $cap = if ($a -and $null -ne $a.cap) { [int]$a.cap } else { 0 }; Import-NvidiaProfile -Cap $cap }
        'openNvidia'   { Open-NvidiaPanel }
        'openAmd'      { Open-AmdPanel }
        'driverPages'  { Open-DriverPages }
        'ui' {
            $map = @{ visual = 'Set-UIVisual'; taskbar = 'Set-UITaskbar'; explorer = 'Set-UIExplorer'; start = 'Set-UIStart'; sounds = 'Set-UISounds'; dark = 'Set-UIDark'; wallpaper = 'Set-Wallpaper' }
            foreach ($g in @($a.groups)) { if ($map.ContainsKey([string]$g)) { & $map[[string]$g] } }
            if (-not $script:DryRun) { Restart-Explorer }
        }
        'debloat'      { Remove-DebloatItems -Labels @($a.labels) }
        'startup' {
            $entries = Get-StartupEntries
            foreach ($c in @($a.changes)) {
                $e = $entries | Where-Object { $_.Name -eq $c.name -and $_.Approved -eq $c.approved } | Select-Object -First 1
                if ($e) { Set-StartupState -Entry $e -Enable ([bool]$c.enable) } else { Write-Skip "Startup entry not found: $($c.name)" }
            }
        }
        'toggle'       { Set-AdvancedToggle -Id ([string]$a.id) -Enable ([bool]$a.enable) }
        'gameOptimize' { Invoke-GameOptimize -Game ([string]$a.game) -Options $a.options }
        'gameRestore'  { Restore-GameSettings -Game ([string]$a.game) }
        'undo'         { Undo-SessionFile -Path (Join-Path $script:BackupDir ([IO.Path]::GetFileName([string]$a.file))) }
        # ---- WinUtil ----
        'wuTweaks'     { $null = & { foreach ($k in @($a.keys)) { Invoke-BuddyTweak -Key ([string]$k) -Undo:([bool]$a.undo) }; Save-Journal } }
        'wuApps'       { $null = & { Invoke-BuddyApps -Action ([string]$a.action) -Keys @($a.keys) -Manager ([string]$a.manager) } }
        'wuUpgradeAll' { $null = & { Invoke-BuddyUpgradeAll -Manager ([string]$a.manager) } }
        'wuAppx'       { $null = & { Invoke-BuddyAppx -Action ([string]$a.action) -Keys @($a.keys) } }
        'wuFeatures'   { $null = & { Invoke-BuddyFeatures -Keys @($a.keys) } }
        'wuFix'        { $null = & { Invoke-BuddyFix -Id ([string]$a.id) } }
        'wuUpdates'    { $null = & { Set-BuddyUpdatePolicy -Mode ([string]$a.mode) } }
        'wuDns'        { $null = & { Set-BuddyDns -Provider ([string]$a.provider) } }
        'wuExtra'      { $null = & { Invoke-BuddyExtra -Id ([string]$a.id) } }
        'isoVerify'    { return (Invoke-BuddyIsoVerify -Path ([string]$a.path)) }
        'isoModify'    { return (Invoke-BuddyIsoModify -Index ([int]$a.index) -InjectDrivers ([bool]$a.drivers)) }
        'isoExport'    { $null = & { Invoke-BuddyIsoExport -Output ([string]$a.output) } }
        'isoUsb'       { $null = & { Invoke-BuddyIsoUsb -Disk ([int]$a.disk) } }
        'isoReset'     { $null = & { Invoke-BuddyIsoReset } }
        default        { throw "Unknown action: $action" }
    }
}

function Invoke-Query([string]$what) {
    switch ($what) {
        'debloat'  { return @(Get-DebloatState) }
        'startup'  { return @(Get-StartupEntries | ForEach-Object { [ordered]@{ name = $_.Name; approved = $_.Approved; where = $_.Where; command = $_.Command; enabled = $_.Enabled } }) }
        'toggles'  { return @(Get-AdvancedToggles | ForEach-Object { [ordered]@{ id = $_.Id; label = $_.Label; on = $_.On; info = $_.Info } }) }
        'sessions' { return @(Get-UndoSessions) }
        'timer'    { $s = Get-StrService; return [ordered]@{ installed = [bool]$s; state = if ($s) { [string]$s.State } else { $null } } }
        'power'    { return [ordered]@{ active = (Get-ActivePlanGuid); plans = @(Get-PowerPlans) } }
        'games'    { return @(Get-GamesState) }
        'wuTweakState'      { return @(Get-BuddyTweakState) }
        'wuInstalled:winget' { return @(Get-BuddyInstalledApps 'winget') }
        'wuInstalled:choco'  { return @(Get-BuddyInstalledApps 'choco') }
        'wuPm'     { return [ordered]@{ winget = (Test-WinUtilPackageManager -winget) -eq 'installed'; choco = (Test-WinUtilPackageManager -choco) -eq 'installed' } }
        'wuAppx'   { return @(Get-WinUtilInstalledAPPX) }
        'wuDnsBench' { return @(Get-WinUtilDNSBenchmark | ForEach-Object { [ordered]@{ provider = $_.Provider; ip = $_.PrimaryIP; ms = $_.LatencyMs } }) }
        'isoState' { return (Get-BuddyIsoState) }
        'isoUsb'   { return @(Get-BuddyUsbDisks) }
        default    { throw "Unknown query: $what" }
    }
}

# ---- main loop ----
while ($true) {
    $line = $null
    try { $line = $reader.ReadLine() } catch { break }
    if ($null -eq $line) { break }                     # app closed the pipe
    $msg = $null
    try { $msg = $line | ConvertFrom-Json } catch { continue }
    $script:CurrentId = [int]$msg.id
    if ($msg.cmd -eq 'quit') { break }
    if ($msg.env) { $script:UserEnv = $msg.env }
    $script:DryRun = [bool]$msg.dryRun
    if ($null -ne $msg.xboxMode) { $script:XboxMode = [bool]$msg.xboxMode }
    $script:Stats.OK = 0; $script:Stats.SKIP = 0; $script:Stats.FAIL = 0; $script:Stats.DRY = 0
    $script:RebootNeeded = $false
    $ok = $true; $data = $null; $err = $null
    try {
        switch ($msg.cmd) {
            'run'   { Write-Log ">>> app action: $($msg.action) (dry=$script:DryRun)"; $data = Invoke-Action ([string]$msg.action) $msg.args }
            'query' { $data = Invoke-Query ([string]$msg.what) }
            'ping'  { $data = 'pong' }
            default { throw "Unknown command: $($msg.cmd)" }
        }
    } catch {
        $ok = $false; $err = $_.Exception.Message
        Write-Log "Agent error: $err`n$($_.ScriptStackTrace)"
    }
    Save-Journal
    Send-Message ([ordered]@{
        type = 'result'; id = $script:CurrentId; ok = $ok; error = $err; data = $data
        stats = [ordered]@{ ok = $script:Stats.OK; skip = $script:Stats.SKIP; fail = $script:Stats.FAIL; dry = $script:Stats.DRY }
        reboot = [bool]$script:RebootNeeded; journal = $(if ($script:Journal.Count) { $script:JournalFile } else { $null })
    })
}
try { $pipe.Dispose() } catch { }
