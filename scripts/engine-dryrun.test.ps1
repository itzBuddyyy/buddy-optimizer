# Engine dry-run test: loads the real engine, replaces every command that could
# change the system with a recorder, runs every agent action with Preview on and
# fails if anything would have been changed or an action crashed.
# Run it NON-elevated (npm run test:engine) so a missed gate cannot touch HKLM.
param([string]$EngineRoot = (Join-Path $PSScriptRoot '..\engine'))
$ErrorActionPreference = 'Continue'
$EngineRoot = (Resolve-Path $EngineRoot).Path
$script:Root = $EngineRoot
$script:FilesDir = Join-Path $EngineRoot 'files'
. (Join-Path $EngineRoot 'lib\Core.ps1')
foreach ($m in Get-ChildItem -LiteralPath (Join-Path $EngineRoot 'modules') -Filter '*.ps1' | Sort-Object Name) { . $m.FullName }

# the real dispatcher from Agent.ps1
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $EngineRoot 'Agent.ps1'), [ref]$null, [ref]$null)
foreach ($f in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in 'Invoke-Quick', 'Invoke-Action', 'Invoke-Query' }, $true)) { . ([scriptblock]::Create($f.Extent.Text)) }
function Send-Message { }

$script:Leaks = New-Object System.Collections.ArrayList
$script:Action = ''
function Write-Host { param([Parameter(Position = 0, ValueFromRemainingArguments)]$Object, $ForegroundColor, $BackgroundColor, [switch]$NoNewline) }
function Read-Host { '' }
function Clear-Host { }
$script:AutoYes = $true

$mutating = 'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty', 'New-Item', 'Remove-Item', 'Copy-Item', 'Move-Item', 'Rename-Item',
    'Set-Content', 'Out-File', 'Add-Content', 'Set-Service', 'Stop-Service', 'Start-Service', 'Restart-Service', 'Stop-Process', 'Start-Process',
    'Set-NetAdapterAdvancedProperty', 'Disable-NetAdapterBinding', 'Set-NetAdapterBinding', 'Disable-ScheduledTask', 'Enable-ScheduledTask',
    'Remove-AppxPackage', 'Remove-AppxProvisionedPackage', 'Add-AppxPackage', 'Remove-WindowsCapability', 'Add-WindowsCapability', 'Enable-ComputerRestore',
    'Enable-WindowsOptionalFeature', 'Set-Acl', 'Invoke-CimMethod', 'Set-MpPreference', 'Add-MpPreference', 'Set-NetTCPSetting', 'Set-NetOffloadGlobalSetting',
    'Set-DnsClientServerAddress', 'Add-DnsClientDohServerAddress', 'Set-DnsClientDohServerAddress', 'Clear-DnsClientCache', 'Suspend-BitLocker', 'Restart-Computer',
    'Register-ScheduledTask', 'Unregister-ScheduledTask', 'New-NetFirewallRule', 'Set-NetFirewallRule', 'Install-Module', 'Install-PackageProvider',
    'Repair-WinGetPackageManager', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Mount-DiskImage', 'Dismount-DiskImage', 'Format-Volume', 'Set-Partition',
    'Set-Disk', 'Initialize-Disk', 'Update-Disk', 'Split-WindowsImage', 'Dismount-WindowsImage', 'Restart-Explorer', 'Save-WinUtilFile'
$natives = 'powercfg', 'bcdedit', 'netsh', 'sc', 'schtasks', 'ipconfig', 'reg', 'icacls', 'takeown', 'cmd', 'wsreset', 'shutdown', 'dism', 'fsutil',
    'w32tm', 'rundll32', 'winget', 'choco', 'diskpart', 'robocopy', 'oscdimg', 'msiexec', 'taskkill', 'nfsadmin', 'chkdsk', 'sfc'
foreach ($n in $mutating) { Set-Item "function:script:$n" ([scriptblock]::Create("[void]`$script:Leaks.Add(`"[`$script:Action] $n `$(`$args -join ' ')`")")) }
foreach ($n in $natives) {
    foreach ($nm in $n, "$n.exe") {
        Set-Item "function:script:$nm" ([scriptblock]::Create("
            `$a = `$args -join ' '
            if (`$a -match '^(/l(ist)?|/q(uery)?|/getactivescheme|/enum|qc |query|int tcp show|list|pin list|-?\?)') { & (Get-Command -CommandType Application '$n.exe' | Select-Object -First 1).Source @args; return }
            [void]`$script:Leaks.Add(`"[`$script:Action] $n.exe `$a`"); `$global:LASTEXITCODE = 0"))
    }
}

$script:DryRun = $true
$script:Sys = Get-SystemProfile
$script:XboxMode = $script:Sys.XboxInstalled
$errors = New-Object System.Collections.ArrayList
$cases = @(
    @('quick', @{}), @('power', @{}), @('gaming', @{}), @('services', @{}), @('privacy', @{}), @('cleanup', @{}),
    @('network', @{}), @('deepnet', @{}), @('restorePoint', @{}), @('xboxFix', @{ resetStore = $true }), @('xboxLock', @{}),
    @('restorePower', @{}), @('timerInstall', @{}), @('timerRemove', @{}), @('noWuDrivers', @{}), @('nvidia', @{ cap = 0 }),
    @('ui', @{ groups = @('visual', 'taskbar', 'explorer', 'start', 'sounds', 'dark', 'wallpaper') }),
    @('debloat', @{ labels = @(Get-DebloatCatalog | ForEach-Object { $_.Label }) }),
    @('startup', @{ changes = @() }),
    @('wuTweaks', @{ keys = @($sync.configs.tweaks.PSObject.Properties | Where-Object { $_.Value.registry -or $_.Value.service -or $_.Value.InvokeScript -or $_.Value.appx } | ForEach-Object Name) }),
    @('wuTweaks', @{ keys = @($sync.configs.tweaks.PSObject.Properties | Where-Object { $_.Value.registry -or $_.Value.service -or $_.Value.UndoScript } | ForEach-Object Name); undo = $true }),
    @('wuApps', @{ action = 'Install'; keys = @($sync.configs.applicationsHashtable.Keys); manager = 'winget' }),
    @('wuApps', @{ action = 'Uninstall'; keys = @('7zip', 'githubdesktop'); manager = 'choco' }),
    @('wuUpgradeAll', @{ manager = 'winget' }), @('wuUpgradeAll', @{ manager = 'choco' }),
    @('wuAppx', @{ action = 'Remove'; keys = @($sync.configs.appx.PSObject.Properties.Name) }),
    @('wuAppx', @{ action = 'Install'; keys = @('WPFAppxMicrosoft_WindowsCalculator') }),
    @('wuFeatures', @{ keys = @($sync.configs.feature.PSObject.Properties.Name | Where-Object { $_ -like 'WPFFeature*' -and $_ -ne 'WPFFeatureInstall' }) })
)
foreach ($id in 'update', 'updateDeep', 'network', 'ntp', 'winget', 'repair', 'autologon') { $cases += , @('wuFix', @{ id = $id }) }
foreach ($m in 'default', 'security', 'disable') { $cases += , @('wuUpdates', @{ mode = $m }) }
foreach ($p in 'DHCP', 'Cloudflare', 'Fastest') { $cases += , @('wuDns', @{ provider = $p }) }
foreach ($x in 'oosu', 'ultPerfOn', 'ultPerfOff', 'ssh', 'profileOn', 'profileOff') { $cases += , @('wuExtra', @{ id = $x }) }
$cases += , @('isoReset', @{})
foreach ($t in @(Get-AdvancedToggles)) { $cases += , @('toggle', @{ id = $t.Id; enable = (-not $t.On) }) }
foreach ($g in $script:GameDefs.Keys) {
    $cases += , @('gameOptimize', @{ game = $g; options = [pscustomobject]@{ config = $true; clutter = $true; audio = $true; performanceMode = $true; readOnly = $true; gpuPref = $true; priority = $true } })
    $cases += , @('gameRestore', @{ game = $g })
}
foreach ($c in $cases) {
    $script:Action = "$($c[0]) $(if ($c[1].id) { $c[1].id } elseif ($c[1].game) { $c[1].game } elseif ($c[1].mode) { $c[1].mode } elseif ($c[1].provider) { $c[1].provider })".Trim()
    try { [void](Invoke-Action $c[0] ([pscustomobject]$c[1])) }
    catch {
        # Get-AppxPackage -AllUsers needs admin; this test runs without it on purpose
        if ($_.Exception.HResult -eq -2147024891) { continue }
        [void]$errors.Add("[$script:Action] $($_.Exception.Message) @ $($_.InvocationInfo.ScriptName | Split-Path -Leaf):$($_.InvocationInfo.ScriptLineNumber)")
    }
}
foreach ($q in 'debloat', 'startup', 'toggles', 'sessions', 'timer', 'power', 'games', 'wuTweakState', 'wuPm', 'isoState', 'isoUsb') {
    $script:Action = "query $q"
    try { [void](Invoke-Query $q) } catch { if ($_.Exception.HResult -ne -2147024891) { [void]$errors.Add("[query $q] $($_.Exception.Message)") } }
}
# hostile input must be refused
$refused = @(
    @('bogus', @{}), @('gameOptimize', @{ game = '..\..\x' }), @('wuTweaks', @{ keys = @('NotATweak') }), @('wuApps', @{ action = 'Format'; keys = @('7zip') }),
    @('wuFeatures', @{ keys = @('WPFFeatureInstall') }), @('wuFix', @{ id = 'x' }), @('wuUpdates', @{ mode = 'x' }), @('wuDns', @{ provider = '1.1.1.1;calc' }),
    @('wuExtra', @{ id = 'x' }), @('isoVerify', @{ path = 'C:\Windows\win.ini' }), @('isoModify', @{ index = 1 }), @('isoExport', @{ output = 'C:\x.iso' }), @('isoUsb', @{ disk = 0 })
)
foreach ($r in $refused) { try { [void](Invoke-Action $r[0] ([pscustomobject]$r[1])); [void]$errors.Add("not refused: $($r[0]) $($r[1] | ConvertTo-Json -Compress)") } catch { } }

# console menus (itzBuddy.ps1 options 20-23), driven by scripted key presses
$menuAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $EngineRoot 'itzBuddy.ps1'), [ref]$null, [ref]$null)
$menuDef = $menuAst.Find({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and $args[0].Left.Extent.Text -eq '$script:Menu' }, $true)
$script:Menu = & ([scriptblock]::Create($menuDef.Right.Extent.Text))
foreach ($f in $menuAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in 'Get-MenuSelection', 'Show-Stats' }, $true)) { . ([scriptblock]::Create($f.Extent.Text)) }
foreach ($k in 20..23) { if (-not ($script:Menu | Where-Object { $_.Key -eq "$k" -and $_.Kind -eq 'WinUtil' })) { [void]$errors.Add("menu item $k missing") } }
if ((Get-MenuSelection '20-23').Count -ne 4) { [void]$errors.Add('menu selection 20-23 failed') }
$script:AutoYes = $false   # the menus must ask, not auto-confirm
$previewSteps = $script:Stats.DRY   # Show-Stats in the menus resets the counters
$script:Keys = New-Object System.Collections.Queue
function Read-Host { param($Prompt) if ($script:Keys.Count) { $script:Keys.Dequeue() } else { 'B' } }
function Select-IsoPath { param([switch]$Save) $null }
$sessions = [ordered]@{
    'Invoke-WinUtilTweaksMenu' = @('1', 'A', '', '', 'Y', '', 'S', '', 'U', 'Y', '', 'M', 'Q', '9', 'B')
    'Invoke-WinUtilAppsMenu'   = @('3', '1 2', '', '', 'Y', '', 'F', 'steam', 'A', '', 'R', 'Y', '', 'U', 'Y', '', 'P', '1', '1', '', 'I', 'Y', '', 'X', 'B')
    'Invoke-WinUtilSystemMenu' = @('1', 'A', '', 'Y', '', '2', '5', 'Y', '', '3', '2', 'Y', '', '3', '3', 'Y', '', '4', '1-3', '', '', 'Y', '', '6', '3', 'Y', '', '7', 'E', '', '8', 'Y', '', '9', 'Y', '', '10', 'R', 'Y', '', '2', '99', '')
    'Invoke-WinUtilIsoMenu'    = @('1', '2', '', '3', '', '4', '', '5', 'Y', '', 'B')
}
foreach ($m in $sessions.Keys) {
    $script:Action = "menu $m"
    $script:Keys.Clear(); foreach ($k in $sessions[$m]) { $script:Keys.Enqueue($k) }
    try { & $m } catch { [void]$errors.Add("[$m] $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)") }
    if ($script:Keys.Count) { [void]$errors.Add("[$m] exited with $($script:Keys.Count) key(s) unused") }
}

$leaks = @($script:Leaks | Where-Object { $_ -notmatch '\] (Add-Content|New-Item) .*\\(logs|backups|itzBuddy)' })
"cases: $($cases.Count) + 4 console menus  preview steps: $previewSteps  journal entries: $($script:Journal.Count)"
if ($leaks.Count) { "LEAKS ($($leaks.Count)):"; $leaks | Select-Object -First 30 }
if ($errors.Count) { "ERRORS ($($errors.Count)):"; $errors }
if ($leaks.Count -or $errors.Count -or $script:Journal.Count) { exit 1 }
'engine dry-run: ok'
