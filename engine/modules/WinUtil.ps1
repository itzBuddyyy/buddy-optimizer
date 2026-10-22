# ==============================================================
#  WinUtil integration
#  Chris Titus Tech's WinUtil (MIT, see winutil\LICENSE and
#  winutil\UPSTREAM for the exact commit). Its functions in
#  winutil\functions run unchanged on top of the small headless shim
#  below. Registry and service changes go through the itzBuddy journal,
#  so every tweak can be undone from Repair like the rest of the suite.
# ==============================================================

$script:WinUtilRoot = Join-Path $script:Root 'winutil'
$script:sync = [Hashtable]::Synchronized(@{})
$sync.winutildir = Join-Path $script:DataRoot 'winutil'
$sync.preferences = @{ packagemanager = 'Winget' }
$sync.ToggleStatusCache = @{}
$sync.configs = @{}
foreach ($n in 'tweaks', 'applications', 'feature', 'dns', 'appx', 'preset') {
    $sync.configs[$n] = Get-Content -LiteralPath (Join-Path $script:WinUtilRoot "config\$n.json") -Raw -Encoding UTF8 | ConvertFrom-Json
}
$sync.configs.applicationsHashtable = @{}
foreach ($p in $sync.configs.applications.PSObject.Properties) { $sync.configs.applicationsHashtable[$p.Name] = $p.Value }
$global:WinUtilJobErrorCount = 0
if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) { New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS -Scope Global | Out-Null }

foreach ($f in Get-ChildItem -LiteralPath (Join-Path $script:WinUtilRoot 'functions') -Filter '*.ps1') { . $f.FullName }

# ---------------- headless shim (replaces WinUtil's WPF/job layer) ----------------

function Write-WinUtilLog {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message, [string]$Level = 'INFO', [string]$Component = '', [switch]$Detail)
    Write-Log "[WinUtil/$Component] $Message"
    if ($Level -eq 'ERROR') { $global:WinUtilJobErrorCount++; Write-Fail $Message }
    elseif ($Level -eq 'WARN') { Write-Warn $Message }
}
function Write-WinUtilErrorRecord { param($ErrorRecord, [string]$Component, [string]$Context) Write-Fail "$Context - $ErrorRecord" }
function Write-Warning { param([Parameter(Position = 0)][string]$Message) Write-Warn $Message }
function Step-WinUtilJob {
    param([string]$Status, [int]$Percent = -1, [string]$State, [switch]$Hide)
    if ($Status) { Write-Info $Status }
    if ($Percent -ge 0 -and (Get-Command Send-Message -ErrorAction SilentlyContinue)) {
        Send-Message ([ordered]@{ type = 'progress'; id = $script:CurrentId; step = $Status; index = $Percent; total = 100 })
    }
}
function Start-WinUtilJob { param([string]$Name, [string]$Description, [hashtable]$Parameters = @{}, [scriptblock]$ScriptBlock) & $ScriptBlock @Parameters }
function Measure-WinUtilStep { param([string]$Scope, [string]$Name, [scriptblock]$ScriptBlock) & $ScriptBlock }
function Invoke-WPFRunspace { param([scriptblock]$ScriptBlock, [object[]]$ArgumentList = @(), $ParameterList) & $ScriptBlock @ArgumentList }
function Invoke-WPFUIThread { param([scriptblock]$ScriptBlock, [hashtable]$Parameters, [switch]$Async) }
function Invoke-WinUtilWhenIdle { param([int]$DelayMilliseconds, [scriptblock]$Callback) }
function Invoke-WinutilThemeChange { param($theme) }
function Show-WinUtilMessage {
    # The app asks the user before it starts an action, so nothing here waits for input
    param([string]$Message, [string]$Title, [string]$Button = 'OK', [string]$Icon)
    Write-Info "$($Title): $($Message -replace '\s+', ' ')"
    if ($Button -eq 'YesNo') { return 'Yes' } else { return 'OK' }
}
function Complete-WinUtilPackageRun { param([string]$Action, $Results) Write-PackageResults $Results }
function Invoke-WinUtilExplorerUpdate {
    param([string]$action = 'refresh')
    if ($script:DryRun) { return }
    if ($action -eq 'restart') { Restart-Explorer; return }
    if (-not ('itzBuddy.Broadcast' -as [type])) {
        Add-Type -Namespace itzBuddy -Name Broadcast -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, string l, uint f, uint t, out IntPtr r);'
    }
    $r = [IntPtr]::Zero
    [void][itzBuddy.Broadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [IntPtr]::Zero, 'ImmersiveColorSet', 2, 100, [ref]$r)
}

# Journaled replacements for WinUtil's registry/service setters
function Set-WinUtilRegistry {
    param($Name, $Path, $Type, $Value)
    if ($Value -eq '<RemoveEntry>') { Remove-Reg -Path $Path -Name $Name; return }
    Set-Reg -Path $Path -Name $Name -Value $Value -Type $Type
}
function Set-WinUtilService {
    param($Name, $StartupType)
    if ($StartupType -eq 'AutomaticDelayedStart') {
        Set-ServiceStart -Name $Name -Start Automatic
        if (Get-Service -Name $Name -ErrorAction SilentlyContinue) { Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" 'DelayedAutostart' 1 -Quiet }
        return
    }
    if ($StartupType -notin 'Automatic', 'Manual', 'Disabled') { Write-Skip "$Name - unsupported start type $StartupType"; return }
    Set-ServiceStart -Name $Name -Start $StartupType
}

# ---------------- helpers ----------------

function Test-BuddyDry([string]$What) { if ($script:DryRun) { Write-Dry $What; return $true }; return $false }

function Write-PackageResults($Results) {
    foreach ($r in @($Results | Where-Object { $_ })) {
        $line = "$($r.Action) $($r.Package): $($r.Detail)"
        switch ($r.Outcome) { 'Succeeded' { Write-OK $line } 'Skipped' { Write-Skip $line } default { Write-Fail $line } }
        if ($r.Detail -match 'restart') { $script:RebootNeeded = $true }
    }
}

function Get-WinUtilEntry([string]$Config, [string]$Key) {
    $e = $sync.configs.$Config.PSObject.Properties[$Key]
    if (-not $e) { throw "Unknown $Config entry: $Key" }
    return $e.Value
}

function Save-SignedDownload {
    # Downloads to the admin-only data folder and refuses to run anything without a valid signature from the expected publisher
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$FileName, [Parameter(Mandatory)][string]$Signer)
    New-Item -ItemType Directory -Path $sync.winutildir -Force | Out-Null
    $dest = Join-Path $sync.winutildir $FileName
    Save-WinUtilFile -Uri $Uri -DestinationPath $dest -ProgressCallback { param($pct, $total) Step-WinUtilJob -Status "Downloading $FileName" -Percent $pct }
    $sig = Get-AuthenticodeSignature -LiteralPath $dest
    # exact CN/O match, so a certificate that merely contains the name is refused
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch "(^|,\s*)(CN|O)=$([regex]::Escape($Signer))(,|$)") {
        Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
        throw "$FileName has no valid signature from $Signer ($($sig.Status)); it was deleted and not started."
    }
    return $dest
}

# ---------------- tweaks ----------------

function Invoke-BuddyTweak {
    param([Parameter(Mandatory)][string]$Key, [switch]$Undo)
    $t = Get-WinUtilEntry 'tweaks' $Key
    Write-Head "$($t.Content)$(if ($Undo) { ' - undo' })"
    if ($script:DryRun) {
        # Shadow the parts that do not dry-run by themselves; registry/service setters already do
        function Invoke-WinUtilScript { param($Name, [scriptblock]$scriptblock) Write-Dry "script: $Name" }
        function Remove-WinUtilAPPX { param($Name) Write-Dry "remove app: $Name" }
        function Remove-WinUtilProvisionedAPPX { param([string[]]$PackageList) }
    }
    $before = $script:Stats.FAIL
    Invoke-WinUtilTweaks -CheckBox $Key -undo ([bool]$Undo)
    $sync.ToggleStatusCache.Clear()
    if (-not $script:DryRun -and -not $Undo -and $t.UndoScript) {
        # Undo replays the bundled UndoScript for this key; the journal stores the key only, never script text
        [void]$script:Journal.Add([ordered]@{ Type = 'Tweak'; Key = $Key; Description = [string]$t.Content })
        Save-Journal
    }
    if ($script:Stats.FAIL -eq $before -and -not $script:DryRun) { Write-OK "$($t.Content) $(if ($Undo) { 'undone' } else { 'applied' })" }
}

function Get-BuddyTweakState { @(Invoke-WinUtilCurrentSystem -CheckBox 'tweaks') }

# ---------------- apps (WinGet / Chocolatey) ----------------

function Invoke-BuddyApps {
    param([ValidateSet('Install', 'Uninstall', 'Upgrade')][string]$Action, [string[]]$Keys, [ValidateSet('winget', 'choco')][string]$Manager = 'winget')
    $entries = foreach ($k in @($Keys)) { if ($sync.configs.applicationsHashtable.ContainsKey($k)) { $sync.configs.applicationsHashtable[$k] } else { Write-Skip "Unknown app: $k" } }
    if (-not $entries) { Write-Skip 'Nothing selected'; return }
    $pref = if ($Manager -eq 'choco') { 'Choco' } else { 'Winget' }
    $selAction = if ($Action -eq 'Uninstall') { 'Uninstall' } else { 'Install' }
    $packages = Get-WinUtilSelectedPackages -PackageList @($entries) -Preference $pref -Action $selAction
    Write-Head "$Action $(@($entries).Count) app(s)"
    if (Test-BuddyDry "$Action winget: $($packages.Winget -join ', ')  choco: $($packages.Choco -join ', ')") { return }
    $results = @()
    if ($packages.Choco.Count) { Install-WinUtilChoco; $results += Install-WinUtilProgramChoco -Action $Action -Programs @($packages.Choco) }
    if ($packages.Winget.Count) { Install-WinUtilWinget; $results += Install-WinUtilProgramWinget -Action $Action -Programs @($packages.Winget) }
    Write-PackageResults $results
}

function Invoke-BuddyUpgradeAll([string]$Manager = 'winget') {
    Write-Head 'Update all apps'
    if (Test-BuddyDry "$Manager upgrade --all") { return }
    if ($Manager -eq 'choco') { Install-WinUtilChoco; Write-PackageResults (Install-WinUtilProgramChoco -Action Upgrade -Programs @('all')) }
    else { Install-WinUtilWinget; Write-PackageResults (Install-WinUtilProgramWinget -Action Upgrade -Programs @('all')) }
}

function Get-BuddyInstalledApps([string]$Manager) {
    if ($Manager -eq 'choco' -and (Test-WinUtilPackageManager -choco) -ne 'installed') { return @() }
    if ($Manager -ne 'choco' -and (Test-WinUtilPackageManager -winget) -ne 'installed') { return @() }
    @(Invoke-WinUtilCurrentSystem -CheckBox $Manager)
}

# ---------------- Store (AppX) apps ----------------

function Invoke-BuddyAppx {
    param([ValidateSet('Remove', 'Install')][string]$Action, [string[]]$Keys)
    Write-Head "$Action Microsoft Store apps"
    $items = @(foreach ($k in @($Keys)) { Get-WinUtilEntry 'appx' $k })
    if (Test-BuddyDry "$Action $(($items | ForEach-Object { $_.PackageId }) -join ', ')") { return }
    if ($Action -eq 'Remove') {
        foreach ($i in $items) { Remove-WinUtilAPPX -Name $i.PackageId; Write-OK "Removed $($i.Content)" }
        try { Remove-WinUtilProvisionedAPPX -PackageList @($items.PackageId) } catch { Write-Fail $_.Exception.Message }
    } else {
        Write-PackageResults @(foreach ($i in $items) { Install-WinUtilAPPX -Name $i.PackageId -StoreId $i.StoreId })
    }
}

# ---------------- features, fixes, updates, DNS, extras ----------------

function Invoke-BuddyFeatures([string[]]$Keys) {
    foreach ($k in @($Keys)) {
        $f = Get-WinUtilEntry 'feature' $k
        if ($k -notlike 'WPFFeature*' -or $k -eq 'WPFFeatureInstall') { throw "Not a Windows feature: $k" }
        Write-Head $f.Content
        if (Test-BuddyDry "enable $(@($f.feature) -join ', ')") { continue }
        $before = $script:Stats.FAIL
        try { Invoke-WinUtilFeatureInstall $k } catch { Write-Fail "$($f.Content) - $($_.Exception.Message)" }
        if ($script:Stats.FAIL -eq $before) { Write-OK "$($f.Content) done" }
        $script:RebootNeeded = $true
    }
}

function Invoke-BuddyFix([string]$Id) {
    $map = [ordered]@{
        update    = @{ Label = 'Reset Windows Update'; Run = { Invoke-WPFFixesUpdate } }
        updateDeep = @{ Label = 'Reset Windows Update (aggressive)'; Run = { Invoke-WPFFixesUpdate -Aggressive $true } }
        network   = @{ Label = 'Reset network'; Run = { Invoke-WPFFixesNetwork } }
        ntp       = @{ Label = 'Use pool.ntp.org for time sync'; Run = { Invoke-WPFFixesNTPPool } }
        winget    = @{ Label = 'Reinstall WinGet'; Run = { Invoke-WPFFixesWinget } }
        repair    = @{ Label = 'System corruption scan (CHKDSK, SFC, DISM)'; Run = { Invoke-WPFSystemRepair } }
        autologon = @{ Label = 'AutoLogon (Sysinternals)'; Run = { $exe = Save-SignedDownload -Uri 'https://live.sysinternals.com/Autologon.exe' -FileName 'Autologon.exe' -Signer 'Microsoft Corporation'; Start-Process -FilePath $exe -ArgumentList '/accepteula' } }
    }
    if (-not $map.Contains($Id)) { throw "Unknown fix: $Id" }
    Write-Head $map[$Id].Label
    if (Test-BuddyDry $map[$Id].Label) { return }
    & $map[$Id].Run
    Write-OK "$($map[$Id].Label) finished"
    if ($Id -in 'update', 'updateDeep', 'network', 'repair') { $script:RebootNeeded = $true }
}

function Set-BuddyUpdatePolicy([ValidateSet('default', 'security', 'disable')][string]$Mode) {
    Write-Head "Windows Update - $Mode"
    if (Test-BuddyDry "Windows Update policy -> $Mode") { return }
    switch ($Mode) { 'default' { Invoke-WPFUpdatesdefault } 'security' { Invoke-WPFUpdatessecurity } 'disable' { Invoke-WPFUpdatesdisable -Confirmed } }
    Write-OK "Windows Update set to $Mode"
    $script:RebootNeeded = $true
}

function Set-BuddyDns([string]$Provider) {
    $known = @('Default', 'DHCP', 'Fastest') + @($sync.configs.dns.PSObject.Properties.Name)
    if ($Provider -notin $known) { throw "Unknown DNS provider: $Provider" }
    Write-Head "DNS - $Provider"
    if (Test-BuddyDry "DNS -> $Provider on every connected adapter") { return }
    if (Set-WinUtilDNS -DNSProvider $Provider) { Write-OK "DNS set to $Provider" } else { Write-Fail "DNS could not be set to $Provider" }
}

function Invoke-BuddyExtra([string]$Id) {
    switch ($Id) {
        'oosu' {
            Write-Head 'O&O ShutUp10++'
            if (Test-BuddyDry 'download and open O&O ShutUp10++') { return }
            $exe = Save-SignedDownload -Uri 'https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe' -FileName 'OOSU10.exe' -Signer 'O&O Software GmbH'
            Start-Process -FilePath $exe; Write-OK 'O&O ShutUp10++ opened'
        }
        'ultPerfOn'  { Write-Head 'Ultimate Performance plan'; if (-not (Test-BuddyDry 'add Ultimate Performance')) { Invoke-WPFUltimatePerformance -Enable; Write-OK 'Ultimate Performance added and active' } }
        'ultPerfOff' { Write-Head 'Default power plans'; if (-not (Test-BuddyDry 'restore default plans')) { Invoke-WPFUltimatePerformance; Write-OK 'Default power plans restored' } }
        'ssh'        { Write-Head 'OpenSSH Server'; if (-not (Test-BuddyDry 'enable OpenSSH Server')) { Invoke-WPFSSHServer; Write-OK 'OpenSSH Server enabled' } }
        'profileOn'  { Write-Head 'CTT PowerShell profile'; if (-not (Test-BuddyDry 'install CTT PowerShell profile')) { Invoke-WinUtilInstallPSProfile; Write-OK 'Profile installed' } }
        'profileOff' { Write-Head 'CTT PowerShell profile'; if (-not (Test-BuddyDry 'remove CTT PowerShell profile')) { Invoke-WinUtilUninstallPSProfile; Write-OK 'Profile removed' } }
        default { throw "Unknown action: $Id" }
    }
}

# ---------------- Windows 11 ISO creator (headless port of WinUtil's Win11 Creator) ----------------

$script:Iso = @{}
# Working files live in the admin-only data folder: in the user's %TEMP% a normal process could swap them
$script:IsoRoot = Join-Path $script:DataRoot 'iso'

function Get-BuddyIsoState {
    if (-not $script:Iso.ContentsDir) {
        # resume work left by an earlier session
        $prev = Get-ChildItem -Path (Join-Path $script:IsoRoot 'BuddyISO_*') -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($prev -and (Test-Path -LiteralPath (Join-Path $prev.FullName 'iso_contents'))) {
            $script:Iso.WorkDir = $prev.FullName; $script:Iso.ContentsDir = Join-Path $prev.FullName 'iso_contents'
        }
    }
    [ordered]@{
        isoPath = $script:Iso.IsoPath; drive = $script:Iso.Drive; image = $script:Iso.WimPath
        editions = @($script:Iso.Editions | Where-Object { $_ }); defaultIndex = $script:Iso.DefaultIndex
        workDir = $script:Iso.WorkDir; ready = [bool]($script:Iso.ContentsDir -and (Test-Path -LiteralPath $script:Iso.ContentsDir))
    }
}

function Invoke-BuddyIsoVerify([string]$Path) {
    Write-Head 'Verify Windows 11 ISO'
    if (-not $Path -or [IO.Path]::GetExtension($Path) -ne '.iso' -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Not an ISO file: $Path" }
    if (Test-BuddyDry "mount and read $Path") { return }
    $prev = $script:Iso.IsoPath
    if ($prev -and $prev -ne $Path -and (Get-DiskImage -ImagePath $prev -ErrorAction SilentlyContinue).Attached) { Dismount-DiskImage -ImagePath $prev -ErrorAction Stop | Out-Null }
    $script:Iso = @{}
    $verified = $false
    try {
        Step-WinUtilJob -Status 'Mounting ISO' -Percent 10
        Mount-DiskImage -ImagePath $Path -ErrorAction Stop | Out-Null
        $letter = $null; $clock = [Diagnostics.Stopwatch]::StartNew()
        while (-not $letter -and $clock.Elapsed.TotalSeconds -lt 60) { Start-Sleep -Milliseconds 500; $letter = (Get-DiskImage -ImagePath $Path | Get-Volume).DriveLetter }
        if (-not $letter) { throw 'The ISO mounted but no drive letter appeared within 60 seconds.' }
        $drive = "${letter}:"
        $wim = @("$drive\sources\install.wim", "$drive\sources\install.esd") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $wim) { throw 'install.wim / install.esd not found - this is not a Windows installation ISO.' }
        Step-WinUtilJob -Status 'Reading editions' -Percent 50
        $info = @(Get-WindowsImage -ImagePath $wim | Select-Object ImageIndex, ImageName)
        if (-not ($info | Where-Object { $_.ImageName -match 'Windows 11' })) { throw 'No Windows 11 edition found. Only official Windows 11 ISOs are supported.' }
        $default = $info[0].ImageIndex
        foreach ($img in $info) { if ((Get-WinUtilImageEditionId -ImagePath $wim -ImageIndex $img.ImageIndex -EditionName $img.ImageName) -eq 'Professional') { $default = $img.ImageIndex; break } }
        $script:Iso = @{ IsoPath = $Path; Drive = $drive; WimPath = $wim; DefaultIndex = $default; Editions = @($info | ForEach-Object { [ordered]@{ index = [int]$_.ImageIndex; name = [string]$_.ImageName } }) }
        $verified = $true
        Write-OK "ISO verified: $($info.Count) edition(s) on $drive"
    } finally {
        if (-not $verified) { try { Dismount-DiskImage -ImagePath $Path -ErrorAction Stop | Out-Null } catch { } }
    }
    return (Get-BuddyIsoState)
}

function Invoke-BuddyIsoModify([int]$Index, [bool]$InjectDrivers) {
    Write-Head 'Prepare Windows 11 setup media'
    if (-not $script:Iso.IsoPath) { throw 'Verify an ISO first.' }
    $ed = $script:Iso.Editions | Where-Object { $_.index -eq $Index } | Select-Object -First 1
    if (-not $ed) { throw "Edition index $Index is not in this ISO." }
    if (Test-BuddyDry "copy ISO, add autounattend.xml for $($ed.name)$(if ($InjectDrivers) { ' + this PC''s drivers' })") { return }
    $work = Join-Path $script:IsoRoot "BuddyISO_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $contents = Join-Path $work 'iso_contents'
    $done = $false
    try {
        New-Item -ItemType Directory -Path $contents -Force | Out-Null
        Step-WinUtilJob -Status 'Copying ISO contents' -Percent 10
        Invoke-WinUtilRobocopy -Source $script:Iso.Drive -Destination $contents -Arguments @('/E', '/NFL', '/NDL', '/NJH', '/NJS')
        $localWim = Join-Path $contents "sources\$(Split-Path $script:Iso.WimPath -Leaf)"
        Step-WinUtilJob -Status 'Writing autounattend.xml and edition' -Percent 30
        $xml = Get-Content -LiteralPath (Join-Path $script:WinUtilRoot 'tools\autounattend.xml') -Raw
        $injected = [ref]$false
        # WinUtil's driver export uses %TEMP%; point it at the admin-only work folder for this call
        $oldTemp = $env:TEMP; $env:TEMP = $work
        try {
        Invoke-WinUtilISOScript -ISOContentsDir $contents -AutoUnattendXml $xml -InjectCurrentSystemDrivers $InjectDrivers `
            -InstallImagePath $localWim -InstallImageIndex $Index `
            -InstallEditionId (Get-WinUtilImageEditionId -ImagePath $localWim -ImageIndex $Index -EditionName $ed.name) `
            -Log { param($m) if ($m -like 'Warning:*') { Write-Warn $m } else { Write-Info $m } } -DriversInjected $injected
        } finally { $env:TEMP = $oldTemp }
        Step-WinUtilJob -Status 'Dismounting source ISO' -Percent 90
        Dismount-DiskImage -ImagePath $script:Iso.IsoPath -ErrorAction Stop | Out-Null
        $script:Iso.WorkDir = $work; $script:Iso.ContentsDir = $contents
        $done = $true
        Write-OK "Setup media prepared for $($ed.name)$(if ($injected.Value) { ' with this PC''s drivers' })"
    } finally {
        if (-not $done) {
            try { Dismount-DiskImage -ImagePath $script:Iso.IsoPath -ErrorAction Stop | Out-Null } catch { }
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    return (Get-BuddyIsoState)
}

function Invoke-BuddyIsoExport([string]$Output) {
    Write-Head 'Build ISO file'
    $dir = $script:Iso.ContentsDir
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { throw 'Prepare the setup media first.' }
    if (-not $Output -or [IO.Path]::GetExtension($Output) -ne '.iso' -or -not (Test-Path -LiteralPath (Split-Path $Output) -PathType Container)) { throw "Invalid output file: $Output" }
    if (Test-BuddyDry "oscdimg -> $Output") { return }
    $oscdimg = Get-WinUtilOscdimgPath
    if (-not $oscdimg) { throw 'oscdimg.exe could not be found or installed (winget install -e --id Microsoft.OSCDIMG).' }
    Step-WinUtilJob -Status 'Building ISO' -Percent 10
    $boot = "2#p0,e,b`"$dir\boot\etfsboot.com`"#pEF,e,b`"$dir\efi\microsoft\boot\efisys.bin`""
    $out = & $oscdimg -m -o -u2 -udfver102 "-bootdata:$boot" '-lCTOS_MODIFIED' $dir $Output 2>&1
    foreach ($l in @($out | Select-Object -Last 6)) { if ("$l".Trim()) { Write-Log "oscdimg: $l" } }
    if ($LASTEXITCODE -ne 0) { throw "oscdimg exited with code $LASTEXITCODE" }
    Write-OK "ISO saved: $Output"
}

function Get-BuddyUsbDisks {
    $boot = @(Get-Disk | Where-Object { $_.IsBoot -or $_.IsSystem } | ForEach-Object Number)
    @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.Number -notin $boot } | Sort-Object Number | ForEach-Object {
        [ordered]@{ number = [int]$_.Number; name = [string]$_.FriendlyName; sizeGB = [math]::Round($_.Size / 1GB, 1); style = [string]$_.PartitionStyle }
    })
}

function Invoke-BuddyIsoUsb([int]$Disk) {
    Write-Head "Write USB installer to disk $Disk"
    $dir = $script:Iso.ContentsDir
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { throw 'Prepare the setup media first.' }
    # never wipe anything but a removable USB disk that is not the boot/system disk
    if (-not (Get-BuddyUsbDisks | Where-Object { $_.number -eq $Disk })) { throw "Disk $Disk is not a USB drive (or it is the system disk); nothing was erased." }
    $esd = Join-Path $dir 'sources\install.esd'
    if ((Test-Path -LiteralPath $esd) -and (Get-Item -LiteralPath $esd).Length -ge 4GB) { throw 'install.esd is larger than 4 GB and cannot be stored on FAT32. Export an ISO instead.' }
    if (Test-BuddyDry "erase disk $Disk and copy setup files") { return }
    Step-WinUtilJob -Status 'Erasing USB drive' -Percent 10
    # commands go to diskpart on stdin: a script file could be swapped before diskpart reads it
    "select disk $Disk`nclean`nconvert gpt`ncreate partition primary$(if ((Get-Disk -Number $Disk).Size -gt 32GB) { ' size=32768' })`nexit" | & diskpart.exe | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Log "diskpart: $_" }
    Start-Sleep -Seconds 3; Update-Disk -Number $Disk
    $part = Get-Partition -DiskNumber $Disk | Where-Object Type -eq 'Basic' | Select-Object -Last 1
    if (-not $part) { throw "No data partition was created on disk $Disk." }
    Step-WinUtilJob -Status 'Formatting FAT32' -Percent 25
    $part | Format-Volume -FileSystem FAT32 -NewFileSystemLabel ('W11-' + (Get-Date).ToString('yyMMdd')) -Force -Confirm:$false | Out-Null
    $letter = Get-WinUtilFreeDriveLetter
    if (-not $letter) { throw 'No free drive letter (D-Z) for the USB drive.' }
    Set-Partition -DiskNumber $Disk -PartitionNumber $part.PartitionNumber -NewDriveLetter $letter
    $usb = "${letter}:"
    for ($i = 0; $i -lt 6 -and -not (Test-Path $usb); $i++) { Start-Sleep -Seconds 2 }
    if (-not (Test-Path $usb)) { throw "$usb is not accessible." }
    Step-WinUtilJob -Status 'Copying setup files' -Percent 45
    $wim = Join-Path $dir 'sources\install.wim'
    if ((Test-Path -LiteralPath $wim) -and (Get-Item -LiteralPath $wim).Length -gt 3800MB) {
        Write-Info 'install.wim is larger than FAT32 allows - splitting it (several minutes)'
        New-Item -ItemType Directory -Path "$usb\sources" -Force | Out-Null
        Split-WindowsImage -ImagePath $wim -SplitImagePath "$usb\sources\install.swm" -FileSize 3800 -CheckIntegrity | Out-Null
        Invoke-WinUtilRobocopy -Source $dir -Destination $usb -Arguments @('/E', '/XF', 'install.wim', '/NFL', '/NDL', '/NJH', '/NJS')
    } else {
        Invoke-WinUtilRobocopy -Source $dir -Destination $usb -Arguments @('/E', '/NFL', '/NDL', '/NJH', '/NJS')
    }
    Write-OK "USB drive $usb is ready to boot"
}

function Invoke-BuddyIsoReset {
    Write-Head 'Start over'
    if (Test-BuddyDry 'delete the ISO working folder') { return }
    if ($script:Iso.IsoPath -and (Get-DiskImage -ImagePath $script:Iso.IsoPath -ErrorAction SilentlyContinue).Attached) { Dismount-DiskImage -ImagePath $script:Iso.IsoPath | Out-Null }
    foreach ($m in @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$script:IsoRoot\BuddyISO_*" })) { Dismount-WindowsImage -Path $m.Path -Discard | Out-Null }
    foreach ($d in @(Get-ChildItem -Path (Join-Path $script:IsoRoot 'BuddyISO_*') -Directory -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    $script:Iso = @{}
    Write-OK 'Working files removed'
}

# ---------------- console menus (itzBuddy.ps1 options 20-23) ----------------
# Same actions and categories as the app; buddy-categories.json is shared with it.

$script:BuddyCats = Get-Content -LiteralPath (Join-Path $script:WinUtilRoot 'buddy-categories.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$script:AppCatOf = @{}
foreach ($k in $sync.configs.applicationsHashtable.Keys) {
    $c = $script:BuddyCats.appFromWinUtil.([string]$sync.configs.applicationsHashtable[$k].category)
    $script:AppCatOf[$k] = if ($c) { $c } else { 'utilities' }
}
foreach ($p in $script:BuddyCats.appMoves.PSObject.Properties) { foreach ($k in $p.Value) { $script:AppCatOf[$k] = $p.Name } }

function Read-MenuChoice([string]$Prompt = 'Choice') { (Read-Host "  $Prompt").Trim().ToUpper() }

function Show-MenuList([string]$Title, [array]$Lines, [string]$Footer = 'B = back') {
    Clear-Host
    Write-Host ''
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray
    for ($i = 0; $i -lt $Lines.Count; $i++) { Write-Host ("  {0,3}  {1}" -f ($i + 1), $Lines[$i]) }
    Write-Host ''
    Write-Host "  $Footer" -ForegroundColor DarkGray
}

function Read-MenuIndex([int]$Count, [string]$Prompt = 'Number') {
    # 0-based index, or -1 for back / anything invalid
    $c = Read-MenuChoice $Prompt
    if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $Count) { return [int]$c - 1 }
    return -1
}

function Get-TweakCat([string]$Key) { $c = $script:BuddyCats.tweaks.$Key; if ($c) { $c } else { 'system' } }
function Test-TweakCaution($p) { ([string]$p.Value.category).StartsWith('z__') -or $p.Name -eq 'WPFTweaksDisableBitLocker' }

function Invoke-WinUtilTweaksMenu {
    $all = @($sync.configs.tweaks.PSObject.Properties | Where-Object { $_.Value.registry -or $_.Value.service -or $_.Value.InvokeScript -or $_.Value.appx })
    $catIds = @($script:BuddyCats.tweakCats.PSObject.Properties.Name)
    while ($true) {
        Clear-Host; Write-Info 'Reading which tweaks are already applied...'
        $applied = @(Get-BuddyTweakState)
        $lines = foreach ($c in $catIds) { '{0}  ({1})' -f $script:BuddyCats.tweakCats.$c, @($all | Where-Object { (Get-TweakCat $_.Name) -eq $c }).Count }
        Show-MenuList "WINUTIL TWEAKS - $($all.Count) tweaks, $($applied.Count) already applied" $lines 'M / S / A = Minimal / Standard / Advanced preset     B = back'
        $c = Read-MenuChoice
        if ($c -in 'B', '') { return }
        $preset = @{ M = 'Minimal'; S = 'Standard'; A = 'Advanced' }[$c]
        if ($preset) { $pool = @($all | Where-Object { $_.Name -in @($sync.configs.preset.$preset) }); $title = "$preset preset" }
        elseif ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $catIds.Count) { $cat = $catIds[[int]$c - 1]; $pool = @($all | Where-Object { (Get-TweakCat $_.Name) -eq $cat }); $title = $script:BuddyCats.tweakCats.$cat }
        else { continue }
        $items = @(foreach ($p in $pool) {
            $notes = @()
            if ($p.Name -in $applied) { $notes += 'applied' }
            if (Test-TweakCaution $p) { $notes += 'CAUTION' }
            if ($p.Value.Type -eq 'Toggle') { $notes += 'on/off switch' }
            @{ Label = [string]$p.Value.Content; Key = $p.Name; Selected = [bool]$preset; Note = ($notes -join ', ') }
        })
        $sel = @(Select-Items -Items $items -Title "TWEAKS - $title  (applied = already active; undo turns a switch off)")
        if (-not $sel.Count) { continue }
        Clear-Host
        $undo = (Read-MenuChoice "A = apply, U = undo the $($sel.Count) selected (ENTER = apply)") -eq 'U'
        if ($sel | Where-Object { $_.Note -match 'CAUTION' }) { Write-Warn 'Some selected tweaks are marked CAUTION. Check what they do on winutil.christitus.com first.' }
        if (-not (Confirm-Action "$(if ($undo) { 'Undo' } else { 'Apply' }) $($sel.Count) tweak(s)?")) { continue }
        foreach ($s in $sel) { try { Invoke-BuddyTweak -Key $s.Key -Undo:$undo } catch { Write-Fail "$($s.Label) - $($_.Exception.Message)" } }
        Save-Journal; Show-Stats; Wait-Key
    }
}

function Invoke-WinUtilAppsMenu {
    $mgr = 'winget'
    $installed = $null
    $catIds = @($script:BuddyCats.appCats.PSObject.Properties.Name)
    while ($true) {
        $lines = foreach ($c in $catIds) { '{0}  ({1})' -f $script:BuddyCats.appCats.$c, @($script:AppCatOf.Keys | Where-Object { $script:AppCatOf[$_] -eq $c }).Count }
        $mgrName = if ($mgr -eq 'choco') { 'Chocolatey' } else { 'WinGet' }
        Show-MenuList "WINUTIL APPS - $($sync.configs.applicationsHashtable.Count) apps, installed with $mgrName" $lines 'F = find by name   U = update all apps   P = switch WinGet / Chocolatey   B = back'
        $c = Read-MenuChoice
        if ($c -in 'B', '') { return }
        if ($c -eq 'P') { $mgr = if ($mgr -eq 'winget') { 'choco' } else { 'winget' }; $installed = $null; continue }
        if ($c -eq 'U') {
            Clear-Host
            if (Confirm-Action "Update every app $mgrName can update on this PC?") { Invoke-BuddyUpgradeAll -Manager $mgr; Show-Stats; Wait-Key }
            continue
        }
        if ($c -eq 'F') {
            $q = (Read-Host '  Search for').Trim()
            if (-not $q) { continue }
            $keys = @($sync.configs.applicationsHashtable.Keys | Where-Object { $a = $sync.configs.applicationsHashtable[$_]; "$($a.content) $($a.description)" -like "*$q*" })
            $title = "search: $q"
        } elseif ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $catIds.Count) {
            $cat = $catIds[[int]$c - 1]; $keys = @($script:AppCatOf.Keys | Where-Object { $script:AppCatOf[$_] -eq $cat }); $title = $script:BuddyCats.appCats.$cat
        } else { continue }
        if (-not $keys.Count) { Write-Skip 'No app matches.'; Start-Sleep -Seconds 2; continue }
        if ($null -eq $installed) { Clear-Host; Write-Info "Checking which apps are installed ($mgrName)..."; $installed = @(Get-BuddyInstalledApps $mgr) }
        $items = @($keys | Sort-Object { $sync.configs.applicationsHashtable[$_].content } | ForEach-Object {
            $a = $sync.configs.applicationsHashtable[$_]
            $notes = @(); if ($_ -in $installed) { $notes += 'installed' }; if ($a.foss) { $notes += 'FOSS' }
            @{ Label = [string]$a.content; Key = $_; Selected = $false; Note = ($notes -join ', ') }
        })
        $sel = @(Select-Items -Items $items -Title "APPS - $title")
        if (-not $sel.Count) { continue }
        Clear-Host
        $remove = (Read-MenuChoice "I = install, R = remove the $($sel.Count) selected (ENTER = install)") -eq 'R'
        Write-Host "  $(($sel | ForEach-Object { $_.Label }) -join ', ')" -ForegroundColor Gray
        if (-not (Confirm-Action "$(if ($remove) { 'Uninstall' } else { 'Install' }) $($sel.Count) app(s) with $($mgrName)?" -DefaultNo:$remove)) { continue }
        Invoke-BuddyApps -Action $(if ($remove) { 'Uninstall' } else { 'Install' }) -Keys @($sel | ForEach-Object { $_.Key }) -Manager $mgr
        $installed = $null
        Show-Stats; Wait-Key
    }
}

$script:PanelCommands = [ordered]@{
    'Computer Management' = @('mmc.exe', 'compmgmt.msc'); 'Control Panel' = @('control.exe'); 'Mouse' = @('control.exe', 'main.cpl')
    'Network Connections' = @('control.exe', 'ncpa.cpl'); 'Power Options' = @('control.exe', 'powercfg.cpl')
    'Printers' = @('explorer.exe', 'shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}'); 'Programs and Features' = @('control.exe', 'appwiz.cpl')
    'Region' = @('control.exe', 'intl.cpl'); 'Security and Maintenance' = @('control.exe', 'wscui.cpl'); 'Sound' = @('control.exe', 'mmsys.cpl')
    'System Properties' = @('control.exe', 'sysdm.cpl'); 'Date and Time' = @('control.exe', 'timedate.cpl'); 'Windows Firewall' = @('control.exe', 'firewall.cpl')
    'System Restore' = @('rstrui.exe')
}
$script:FixList = [ordered]@{
    repair = 'System corruption scan: CHKDSK, SFC and DISM (15-45 minutes)'; update = 'Reset Windows Update'
    updateDeep = 'Reset Windows Update (deep: system file repair first, slow)'; network = 'Reset network (clears custom DNS and static IPs, restart needed)'
    ntp = 'Better time sync (pool.ntp.org)'; winget = 'Reinstall WinGet'; autologon = 'AutoLogon (Sysinternals, signature checked)'
}

function Invoke-WinUtilSystemMenu {
    $entries = @('Windows features (Hyper-V, WSL, Sandbox, .NET...)', 'Repair tools (SFC/DISM, Windows Update, network, time, WinGet, AutoLogon)',
        'Windows Update policy', 'Microsoft Store apps (remove / reinstall)', 'Classic control panels', 'DNS server',
        'Ultimate Performance power plan', 'O&O ShutUp10++ (download, check signature, open)', 'OpenSSH server', 'Chris Titus PowerShell profile')
    while ($true) {
        Show-MenuList 'WINUTIL SYSTEM TOOLS' $entries
        $c = Read-MenuChoice
        if ($c -in 'B', '') { return }
        $ran = $true
        try {
            switch ($c) {
                '1' {
                    $items = @($sync.configs.feature.PSObject.Properties | Where-Object { $_.Name -like 'WPFFeature*' -and $_.Name -ne 'WPFFeatureInstall' } |
                        ForEach-Object { @{ Label = [string]$_.Value.Content; Key = $_.Name; Selected = $false } })
                    $sel = @(Select-Items -Items $items -Title 'WINDOWS FEATURES - choose what to enable')
                    Clear-Host
                    if ($sel.Count -and (Confirm-Action "Enable $($sel.Count) feature(s)?")) { Invoke-BuddyFeatures -Keys @($sel | ForEach-Object { $_.Key }) } else { $ran = $false }
                }
                '2' {
                    Show-MenuList 'REPAIR TOOLS' @($script:FixList.Values)
                    $i = Read-MenuIndex $script:FixList.Count
                    $id = if ($i -ge 0) { @($script:FixList.Keys)[$i] }
                    if ($id -and (Confirm-Action "$($script:FixList[$id])?" -DefaultNo:($id -in 'network', 'updateDeep'))) { Invoke-BuddyFix -Id $id } else { $ran = $false }
                }
                '3' {
                    Show-MenuList 'WINDOWS UPDATE POLICY' @('Windows defaults (remove every update policy)', 'Security updates only (features wait a year, quality 4 days, drivers stay yours) - recommended', 'Turn updates OFF (no security fixes until you switch back)')
                    $mode = @{ '1' = 'default'; '2' = 'security'; '3' = 'disable' }[(Read-MenuChoice)]
                    if ($mode -eq 'disable') { Write-Warn 'Your PC will get no security fixes while updates are off.' }
                    if ($mode -and (Confirm-Action "Set Windows Update to '$mode'?" -DefaultNo:($mode -eq 'disable'))) { Set-BuddyUpdatePolicy -Mode $mode } else { $ran = $false }
                }
                '4' {
                    Clear-Host; Write-Info 'Reading installed Store apps...'
                    $names = @(Get-WinUtilInstalledAPPX)
                    $items = @($sync.configs.appx.PSObject.Properties | ForEach-Object {
                        @{ Label = [string]$_.Value.Content; Key = $_.Name; Selected = $false; Note = $(if ($_.Value.PackageId -in $names) { 'installed' } else { 'not installed' }) } })
                    $sel = @(Select-Items -Items $items -Title 'MICROSOFT STORE APPS')
                    Clear-Host
                    if (-not $sel.Count) { $ran = $false }
                    else {
                        $reinstall = (Read-MenuChoice "R = remove, I = reinstall the $($sel.Count) selected (ENTER = remove)") -eq 'I'
                        if (Confirm-Action "$(if ($reinstall) { 'Reinstall' } else { 'Remove' }) $($sel.Count) app(s)?" -DefaultNo:(-not $reinstall)) { Invoke-BuddyAppx -Action $(if ($reinstall) { 'Install' } else { 'Remove' }) -Keys @($sel | ForEach-Object { $_.Key }) } else { $ran = $false }
                    }
                }
                '5' {
                    $ran = $false
                    Show-MenuList 'CLASSIC CONTROL PANELS' @($script:PanelCommands.Keys)
                    $i = Read-MenuIndex $script:PanelCommands.Count
                    if ($i -ge 0) {
                        $cmd = @(@($script:PanelCommands.Values)[$i])
                        $exe = Join-Path $env:SystemRoot $(if ($cmd[0] -eq 'explorer.exe') { $cmd[0] } else { "System32\$($cmd[0])" })
                        if ($cmd.Count -gt 1) { Start-Process -FilePath $exe -ArgumentList $cmd[1] } else { Start-Process -FilePath $exe }
                    }
                }
                '6' {
                    Clear-Host; Write-Info 'Measuring DNS providers...'
                    $bench = @{}; foreach ($b in @(Get-WinUtilDNSBenchmark)) { $bench[$b.Provider] = $b.LatencyMs }
                    $providers = @('DHCP', 'Fastest') + @($sync.configs.dns.PSObject.Properties.Name)
                    $lines = foreach ($p in $providers) {
                        $ms = if ($bench.ContainsKey($p)) { $(if ($bench[$p] -ge 9999) { '  (no answer)' } else { "  ($($bench[$p]) ms)" }) } else { '' }
                        $what = switch ($p) { 'DHCP' { 'DHCP - back to your router' } 'Fastest' { 'Fastest - measure and pick automatically' } default { $p -replace '_', ' ' } }
                        "$what$ms"
                    }
                    Show-MenuList 'DNS SERVER - applies to every connected adapter' $lines
                    $i = Read-MenuIndex $providers.Count
                    if ($i -ge 0 -and (Confirm-Action "Set DNS to $($providers[$i])? The connection may drop for a second.")) { Set-BuddyDns -Provider $providers[$i] } else { $ran = $false }
                }
                '7' {
                    Clear-Host
                    $c2 = Read-MenuChoice 'E = add and activate Ultimate Performance, R = restore the default plans (B = back)'
                    if ($c2 -eq 'E') { Invoke-BuddyExtra -Id 'ultPerfOn' } elseif ($c2 -eq 'R' -and (Confirm-Action 'Restore the default Windows power plans?')) { Invoke-BuddyExtra -Id 'ultPerfOff' } else { $ran = $false }
                }
                '8' { Clear-Host; if (Confirm-Action 'Download O&O ShutUp10++ (about 82 MB) and open it?') { Invoke-BuddyExtra -Id 'oosu' } else { $ran = $false } }
                '9' {
                    Clear-Host
                    Write-Warn 'This lets people sign in to this PC over SSH (port 22 is opened in the firewall). Use key sign-in only.'
                    if (Confirm-Action 'Enable the OpenSSH server?' -DefaultNo) { Invoke-BuddyExtra -Id 'ssh' } else { $ran = $false }
                }
                '10' {
                    Clear-Host
                    Write-Warn 'Install downloads and runs the CTT profile setup script from GitHub with PowerShell 7, as administrator.'
                    $c2 = Read-MenuChoice 'I = install, R = remove (B = back)'
                    if ($c2 -eq 'I' -and (Confirm-Action 'Install the Chris Titus PowerShell profile?' -DefaultNo)) { Invoke-BuddyExtra -Id 'profileOn' }
                    elseif ($c2 -eq 'R' -and (Confirm-Action 'Remove it and restore your previous profile?')) { Invoke-BuddyExtra -Id 'profileOff' }
                    else { $ran = $false }
                }
                default { $ran = $false }
            }
        } catch { Write-Fail $_.Exception.Message }
        if ($ran) { Show-Stats; Wait-Key }
    }
}

function Select-IsoPath([switch]$Save) {
    # file dialog when possible (the console is STA), otherwise a typed path
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dlg = if ($Save) { [System.Windows.Forms.SaveFileDialog]::new() } else { [System.Windows.Forms.OpenFileDialog]::new() }
        $dlg.Filter = 'ISO files (*.iso)|*.iso'
        $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        if ($Save) { $dlg.FileName = "Win11_Buddy_$(Get-Date -Format yyyyMMdd).iso" }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
        return $null
    } catch {
        $p = (Read-Host "  Full path of the $(if ($Save) { 'new' } else { 'Windows 11' }) .iso file").Trim().Trim('"')
        if ($p) { return $p } else { return $null }
    }
}

function Invoke-WinUtilIsoMenu {
    while ($true) {
        $st = Get-BuddyIsoState
        $status = if ($st.ready) { "setup media ready: $($st.workDir)" } elseif (@($st.editions).Count) { "checked: $($st.isoPath)" } else { 'no ISO chosen yet' }
        Show-MenuList "WINDOWS 11 ISO CREATOR  -  $status" @('Choose and check an official Windows 11 ISO', 'Pick the edition and prepare the setup media (about 6 GB)',
            'Save as a new ISO file', 'Write a bootable USB drive (ERASES the drive)', 'Start over (delete the working files)') 'B = back     Get the ISO from microsoft.com/software-download/windows11'
        $c = Read-MenuChoice
        if ($c -in 'B', '') { return }
        $ran = $true
        try {
            if ($c -eq '1') { $p = Select-IsoPath; if ($p) { [void](Invoke-BuddyIsoVerify -Path $p) } else { $ran = $false } }
            elseif ($c -eq '2') {
                $eds = @($st.editions)
                if (-not $eds.Count) { Write-Skip 'Choose and check an ISO first (1).' }
                else {
                    Show-MenuList 'EDITION' @($eds | ForEach-Object { "$($_.name)$(if ($_.index -eq $st.defaultIndex) { '  (suggested)' })" }) 'ENTER = suggested edition'
                    $raw = Read-MenuChoice
                    $ed = if ($raw -eq '') { $eds | Where-Object { $_.index -eq $st.defaultIndex } | Select-Object -First 1 } elseif ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $eds.Count) { $eds[[int]$raw - 1] }
                    if (-not $ed) { $ran = $false }
                    else {
                        $drivers = Confirm-Action 'Add the storage and network drivers of this PC to the media?' -DefaultNo
                        if (Confirm-Action "Prepare setup media for $($ed.name)?") { [void](Invoke-BuddyIsoModify -Index $ed.index -InjectDrivers $drivers) } else { $ran = $false }
                    }
                }
            }
            elseif ($c -eq '3') {
                if (-not $st.ready) { Write-Skip 'Prepare the setup media first (2).' }
                else { $out = Select-IsoPath -Save; if ($out) { Invoke-BuddyIsoExport -Output $out } else { $ran = $false } }
            }
            elseif ($c -eq '4') {
                $disks = @(Get-BuddyUsbDisks)
                if (-not $st.ready) { Write-Skip 'Prepare the setup media first (2).' }
                elseif (-not $disks.Count) { Write-Skip 'No USB drive found. Plug one in and try again.' }
                else {
                    Show-MenuList 'USB DRIVE - everything on it will be erased' @($disks | ForEach-Object { "Disk $($_.number): $($_.name)  [$($_.sizeGB) GB]" })
                    $i = Read-MenuIndex $disks.Count
                    if ($i -lt 0) { $ran = $false }
                    else {
                        $d = $disks[$i]
                        Write-Warn "ALL data on disk $($d.number) ($($d.name), $($d.sizeGB) GB) will be erased permanently."
                        if ((Read-Host '  Type ERASE to continue').Trim() -ceq 'ERASE') { Invoke-BuddyIsoUsb -Disk $d.number } else { Write-Info 'Cancelled.'; $ran = $false }
                    }
                }
            }
            elseif ($c -eq '5') { if (Confirm-Action 'Delete the ISO working files and start over?' -DefaultNo) { Invoke-BuddyIsoReset } else { $ran = $false } }
            else { $ran = $false }
        } catch { Write-Fail $_.Exception.Message }
        if ($ran) { Show-Stats; Wait-Key }
    }
}
