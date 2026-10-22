# ==============================================================
#  itzBuddy - Core helpers
#  Logging, confirmations, system detection, and a change journal
#  that lets every registry/service/command change be undone.
# ==============================================================

$script:DataRoot   = Join-Path $env:ProgramData 'itzBuddy'
$script:LogDir     = Join-Path $script:DataRoot 'logs'
$script:BackupDir  = Join-Path $script:DataRoot 'backups'
$script:SessionId  = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile    = Join-Path $script:LogDir "itzBuddy-$($script:SessionId).log"
$script:JournalFile = Join-Path $script:BackupDir "session-$($script:SessionId).json"
$script:Journal    = New-Object System.Collections.ArrayList
$script:JournalKeys = New-Object 'System.Collections.Generic.HashSet[string]'
$script:DryRun     = $false
$script:AutoYes    = $false
$script:RebootNeeded = $false
$script:Stats      = @{ OK = 0; SKIP = 0; FAIL = 0; DRY = 0 }

foreach ($d in @($script:LogDir, $script:BackupDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

if (-not ('itzBuddy.Native' -as [type])) {
    Add-Type -Namespace itzBuddy -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "SystemParametersInfoW")]
public static extern bool SystemParametersInfoW(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
'@
}

# ---------------- Logging ----------------

function Write-Log {
    param([string]$Text)
    try { Add-Content -LiteralPath $script:LogFile -Value ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $Text) -ErrorAction Stop } catch { }
}
function Write-OK   {
    param([string]$m)
    # In dry run nothing was really done, so never print a green [OK]
    if ($script:DryRun) { Write-Host "  [DRY] $m" -ForegroundColor DarkGray; Write-Log "[DRY]  $m"; return }
    $script:Stats.OK++; Write-Host "  [OK] $m" -ForegroundColor Green; Write-Log "[OK]   $m"
}
function Write-Skip { param([string]$m) $script:Stats.SKIP++; Write-Host "  [--] $m" -ForegroundColor DarkYellow; Write-Log "[SKIP] $m" }
function Write-Fail { param([string]$m) $script:Stats.FAIL++; Write-Host "  [!!] $m" -ForegroundColor Red;      Write-Log "[FAIL] $m" }
function Write-Info { param([string]$m) Write-Host "  [>>] $m" -ForegroundColor Cyan; Write-Log "[INFO] $m" }
function Write-Warn { param([string]$m) Write-Host "  [!]  $m" -ForegroundColor Yellow; Write-Log "[WARN] $m" }
function Write-Head {
    param([string]$m)
    Write-Host ""
    Write-Host "  === $m ===" -ForegroundColor White
    Write-Log "=== $m ==="
}
function Write-Dry  { param([string]$m) $script:Stats.DRY++; Write-Host "  [DRY] $m" -ForegroundColor DarkGray; Write-Log "[DRY]  $m" }

# ---------------- Prompts ----------------

function Confirm-Action {
    # Returns $true on Y. Honors $script:AutoYes (used by Quick Optimize so
    # the user only confirms once).
    param([string]$Question, [switch]$DefaultNo)
    if ($script:AutoYes) { return $true }
    $hint = if ($DefaultNo) { '[y/N]' } else { '[Y/n]' }
    while ($true) {
        $a = (Read-Host "  $Question $hint").Trim().ToUpper()
        if ($a -eq '') { return (-not $DefaultNo) }
        if ($a -in @('Y','S','YES','SI')) { return $true }
        if ($a -in @('N','NO')) { return $false }
    }
}

function Wait-Key {
    param([string]$Text = 'Press ENTER to return to the menu')
    if ($script:AutoYes) { return }
    [void](Read-Host "  $Text")
}

function Select-Items {
    # Interactive checklist. $Items = array of hashtables with Label/Selected
    # (and anything else). Returns the selected items.
    param([array]$Items, [string]$Title)
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "  $Title" -ForegroundColor Cyan
        Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $box = if ($Items[$i].Selected) { '[x]' } else { '[ ]' }
            $color = if ($Items[$i].Selected) { 'White' } else { 'DarkGray' }
            $note = if ($Items[$i].Note) { "  - $($Items[$i].Note)" } else { '' }
            Write-Host ("  {0,3}  {1} {2}{3}" -f ($i + 1), $box, $Items[$i].Label, $note) -ForegroundColor $color
        }
        Write-Host ""
        Write-Host "  Numbers (e.g. 1 4 7 or 2-5) = toggle   A = all   N = none" -ForegroundColor DarkGray
        Write-Host "  ENTER = continue with selection        Q = cancel" -ForegroundColor DarkGray
        $in = (Read-Host "  Choice").Trim().ToUpper()
        if ($in -eq '') { return @($Items | Where-Object { $_.Selected }) }
        if ($in -eq 'Q') { return @() }
        if ($in -eq 'A') { foreach ($it in $Items) { $it.Selected = $true }; continue }
        if ($in -eq 'N') { foreach ($it in $Items) { $it.Selected = $false }; continue }
        foreach ($tok in ($in -split '[\s,;]+')) {
            if ($tok -match '^(\d+)-(\d+)$') {
                $a = [int]$Matches[1]; $b = [int]$Matches[2]
                for ($n = [Math]::Min($a,$b); $n -le [Math]::Max($a,$b); $n++) {
                    if ($n -ge 1 -and $n -le $Items.Count) { $Items[$n-1].Selected = -not $Items[$n-1].Selected }
                }
            } elseif ($tok -match '^\d+$') {
                $n = [int]$tok
                if ($n -ge 1 -and $n -le $Items.Count) { $Items[$n-1].Selected = -not $Items[$n-1].Selected }
            }
        }
    }
}

# ---------------- System detection ----------------

$script:WmiHealthy = $true

function Invoke-WithTimeout {
    # Runs a scriptblock on a separate runspace and gives up after $Seconds.
    # WMI/CIM-based cmdlets (Get-CimInstance, Get-NetAdapter, Get-PhysicalDisk,
    # Get-ScheduledTask, Get-AppxPackage...) can hang for minutes when the WMI
    # service is busy or stuck; this guarantees the suite never freezes.
    # Returns the output, or $null on timeout/error (never throws).
    param([scriptblock]$Script, [int]$Seconds = 20, [object[]]$ArgumentList = @(), [string]$What = 'operation')
    $ps = [PowerShell]::Create()
    try {
        [void]$ps.AddScript($Script.ToString())
        foreach ($a in $ArgumentList) { [void]$ps.AddArgument($a) }
        $async = $ps.BeginInvoke()
        if ($async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($Seconds))) {
            $out = $ps.EndInvoke($async)
            if ($ps.HadErrors -and $ps.Streams.Error.Count) { Write-Log "$What reported: $($ps.Streams.Error[0])" }
            return $out
        }
        Write-Log "$What timed out after ${Seconds}s"
        [void]$ps.BeginStop($null, $null)   # don't wait for a hung call
        $ps = $null                         # abandon the stuck runspace
        return $null
    } catch {
        Write-Log "$What failed: $($_.Exception.Message)"
        return $null
    } finally {
        if ($ps) { $ps.Dispose() }
    }
}

function Get-CimSafe {
    param([Parameter(Position = 0)][string]$ClassName, [string]$Namespace = 'root\cimv2', [int]$Seconds = 15)
    if (-not $script:WmiHealthy) { return $null }
    Invoke-WithTimeout -Seconds $Seconds -What "CIM $ClassName" -ArgumentList $Namespace, $ClassName -Script {
        param($ns, $cls) Get-CimInstance -Namespace $ns -ClassName $cls -OperationTimeoutSec 10 -ErrorAction Stop
    }
}

function Test-WmiHealth {
    $r = Invoke-WithTimeout -Seconds 15 -What 'WMI health check' -Script {
        (Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 10 -ErrorAction Stop).BuildNumber
    }
    $script:WmiHealthy = [bool]$r
    return $script:WmiHealthy
}

function Get-SystemProfile {
    # Registry first (always works), WMI only for extras, so detection
    # still works when WMI is broken.
    $p = [ordered]@{}
    $nt = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $p.Build     = [int]$nt.CurrentBuildNumber
    $p.IsWin11   = $p.Build -ge 22000
    $name = [string]$nt.ProductName
    if ($p.IsWin11) { $name = $name -replace 'Windows 10', 'Windows 11' }   # ProductName still says 10 on Win11
    $p.OSName    = if ($name) { $name } else { 'Windows' }
    $cpuKey = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction SilentlyContinue
    $p.CPU       = if ($cpuKey.ProcessorNameString) { $cpuKey.ProcessorNameString.Trim() } else { 'Unknown CPU' }
    $p.CpuVendor = if ($cpuKey.VendorIdentifier -match 'AMD') { 'AMD' } elseif ($cpuKey.VendorIdentifier -match 'Intel') { 'Intel' } else { 'Other' }

    $vendors = New-Object System.Collections.ArrayList
    $gpuNames = @()
    $classRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($k in @(Get-ChildItem -LiteralPath $classRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
        $id = [string]$k.GetValue('MatchingDeviceId')
        $v = $null
        if ($id -match 'ven_10de') { $v = 'NVIDIA' } elseif ($id -match 'ven_1002') { $v = 'AMD' } elseif ($id -match 'ven_8086') { $v = 'Intel' }
        if ($v) {
            if (-not $vendors.Contains($v)) { [void]$vendors.Add($v) }
            $gpuNames += [string]$k.GetValue('DriverDesc')
        }
    }
    $refresh = 0
    foreach ($g in @(Get-CimSafe Win32_VideoController)) {
        if ($g.CurrentRefreshRate -gt $refresh) { $refresh = [int]$g.CurrentRefreshRate }
    }
    $p.GpuVendors  = @($vendors)
    $p.GPU         = if ($gpuNames) { ($gpuNames | Select-Object -Unique) -join ' + ' } else { 'Unknown GPU' }
    $p.RefreshRate = $refresh

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $noBattery = ([int][System.Windows.Forms.SystemInformation]::PowerStatus.BatteryChargeStatus -band 128) -ne 0
        $p.IsLaptop = -not $noBattery
    } catch { $p.IsLaptop = $false }
    if (-not $p.IsLaptop) {
        $chassis = (Get-CimSafe Win32_SystemEnclosure).ChassisTypes
        $p.IsLaptop = [bool]($chassis | Where-Object { $_ -in 8,9,10,11,12,14,18,21,30,31,32 })
    }

    $p.SystemSSD = $true
    if ($script:WmiHealthy) {
        $media = Invoke-WithTimeout -Seconds 15 -What 'disk type' -ArgumentList $env:SystemDrive.TrimEnd(':') -Script {
            param($letter)
            $disk = Get-Partition -DriveLetter $letter -ErrorAction Stop | Get-Disk -ErrorAction Stop
            (Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq [string]$disk.Number }).MediaType
        }
        if ([string]$media -eq 'HDD') { $p.SystemSSD = $false }
    }

    # Xbox app / Gaming Services installed? (registry only - Get-AppxPackage can hang too)
    $p.XboxInstalled = [bool](Get-Service -Name 'GamingServices' -ErrorAction SilentlyContinue)
    if (-not $p.XboxInstalled) {
        $repo = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages'
        $p.XboxInstalled = [bool](Get-ChildItem -LiteralPath $repo -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'Microsoft.GamingApp_*' })
    }

    $p.BitLocker = $false
    if ($script:WmiHealthy) {
        $bl = Invoke-WithTimeout -Seconds 15 -What 'BitLocker status' -ArgumentList $env:SystemDrive -Script {
            param($d) [string](Get-BitLockerVolume -MountPoint $d -ErrorAction Stop).ProtectionStatus
        }
        $p.BitLocker = ([string]$bl -eq 'On')
    }

    $split = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' $null
    $ramKB = 0
    try { Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop; $ramKB = [long]((New-Object Microsoft.VisualBasic.Devices.ComputerInfo).TotalPhysicalMemory / 1KB) } catch { }
    $p.RamGB = [math]::Round($ramKB / 1MB)
    # Splitting is off when the threshold is >= installed RAM
    $p.SvcHostGrouped = ($null -ne $split -and $ramKB -gt 0 -and [long]$split -ge $ramKB)
    return [pscustomobject]$p
}

# ---------------- Journal (undo support) ----------------

function Save-Journal {
    if ($script:Journal.Count -eq 0) { return }
    try {
        $obj = [ordered]@{
            Session = $script:SessionId
            Created = (Get-Date).ToString('s')
            Computer = $env:COMPUTERNAME
            Entries = @($script:Journal)
        }
        $obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:JournalFile -Encoding UTF8
    } catch { Write-Log "Journal save failed: $($_.Exception.Message)" }
}

function Add-JournalCommand {
    # Records a non-registry action plus the command line that undoes it.
    param([string]$Description, [string]$UndoCommand)
    if ($script:DryRun) { return }
    [void]$script:Journal.Add([ordered]@{ Type = 'Cmd'; Description = $Description; Undo = $UndoCommand })
    Save-Journal
}

function Convert-RegPath {
    param([string]$Path)
    $p = $Path -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM:\' -replace '^HKEY_CURRENT_USER\\', 'HKCU:\' `
               -replace '^HKLM\\', 'HKLM:\' -replace '^HKCU\\', 'HKCU:\'
    return $p
}

function Backup-RegValue {
    param([string]$Path, [string]$Name)
    if ($script:DryRun) { return }
    $id = "$Path|$Name".ToLowerInvariant()
    if (-not $script:JournalKeys.Add($id)) { return }   # first touch per session only
    $entry = [ordered]@{ Type = 'Reg'; Path = $Path; Name = $Name; Existed = $false; Kind = $null; Value = $null }
    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($key.GetValueNames() -contains $Name) {
            $entry.Existed = $true
            $entry.Kind  = $key.GetValueKind($Name).ToString()
            $val = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
            if ($val -is [byte[]]) { $val = [int[]]$val }
            $entry.Value = $val
        }
    } catch { }
    [void]$script:Journal.Add($entry)
    Save-Journal
}

function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()]$Value,
        [ValidateSet('DWord','QWord','String','ExpandString','Binary','MultiString')][string]$Type = 'DWord',
        [switch]$Quiet
    )
    $Path = Convert-RegPath $Path
    $label = if ($Name -eq '') { '(default)' } else { $Name }
    if ($script:DryRun) { Write-Dry "$Path -> $label = $Value"; return }
    try {
        Backup-RegValue -Path $Path -Name $Name
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        if ($Type -eq 'Binary' -and $Value -isnot [byte[]]) { $Value = [byte[]]$Value }
        New-ItemProperty -LiteralPath $Path -Name $label -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        if (-not $Quiet) { Write-OK "$label = $(if ($Value -is [array]) { '(binary)' } else { $Value })" }
    } catch {
        Write-Fail "$Path\$label - $($_.Exception.Message)"
    }
}

function Remove-RegValueRaw {
    # .NET delete - also handles the (default) value, which Remove-ItemProperty can't
    param([string]$Path, [string]$Name)
    $Path = Convert-RegPath $Path
    if ($Path -notmatch '^(HKLM|HKCU|HKU):\\(.+)$') { return }
    $base = switch ($Matches[1]) { 'HKLM' { [Microsoft.Win32.Registry]::LocalMachine } 'HKU' { [Microsoft.Win32.Registry]::Users } default { [Microsoft.Win32.Registry]::CurrentUser } }
    $k = $base.OpenSubKey($Matches[2], $true)
    if ($k) { try { $k.DeleteValue($Name, $false) } finally { $k.Close() } }
}

function Remove-Reg {
    param([string]$Path, [string]$Name, [switch]$Quiet)
    $Path = Convert-RegPath $Path
    if ($script:DryRun) { Write-Dry "remove $Path\$Name"; return }
    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($key.GetValueNames() -notcontains $Name) { return }
        Backup-RegValue -Path $Path -Name $Name
        Remove-RegValueRaw -Path $Path -Name $Name
        if (-not $Quiet) { Write-OK "Removed $Name" }
    } catch { }
}

function Get-RegValue {
    param([string]$Path, [string]$Name, $Default = $null)
    try {
        $v = (Get-ItemProperty -LiteralPath (Convert-RegPath $Path) -Name $Name -ErrorAction Stop).$Name
        if ($null -eq $v) { return $Default }
        return $v
    } catch { return $Default }
}

function Set-ServiceStart {
    # Start: Automatic | Manual | Disabled. Journals the registry Start value
    # so it can be restored exactly (including delayed-auto).
    # Running services are NOT stopped live: on PCs where many services share
    # one svchost process (SvcHostSplitThresholdInKB tweak), stopping one live
    # can freeze WMI / Task Scheduler / User Manager in the same process.
    # The new start type takes effect at the next reboot.
    param([string]$Name, [ValidateSet('Automatic','Manual','Disabled')][string]$Start, [switch]$StartNow)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) { Write-Skip "Service not present: $Name"; return }
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $num = @{ Automatic = 2; Manual = 3; Disabled = 4 }[$Start]
    if ($script:DryRun) { Write-Dry "service $Name -> $Start"; return }
    Backup-RegValue -Path $regPath -Name 'Start'
    Backup-RegValue -Path $regPath -Name 'DelayedAutostart'
    try {
        try { Set-Service -Name $Name -StartupType $Start -ErrorAction Stop }
        catch { New-ItemProperty -LiteralPath $regPath -Name 'Start' -Value $num -PropertyType DWord -Force -ErrorAction Stop | Out-Null }
        # sc start returns immediately (Start-Service can block on a hung service)
        if ($StartNow -and $svc.Status -ne 'Running') { & sc.exe start $Name 2>&1 | Out-Null }
        $note = if ($Start -eq 'Disabled' -and $svc.Status -eq 'Running') { ' (stops after reboot)' } else { '' }
        Write-OK "$($svc.DisplayName) [$Name] -> $Start$note"
        $script:RebootNeeded = $true
    } catch {
        Write-Fail "$Name - $($_.Exception.Message)"
    }
}

function Invoke-Native {
    # Runs a native command, reports exit code honestly (the old scripts
    # printed OK even when the command failed).
    param([string]$Description, [string]$File, [string[]]$Arguments, [string]$UndoCommand, [int[]]$OkCodes = @(0))
    if ($script:DryRun) { Write-Dry "$File $($Arguments -join ' ')"; return $true }
    try {
        $out = & $File @Arguments 2>&1
        if ($OkCodes -contains $LASTEXITCODE) {
            Write-OK $Description
            if ($UndoCommand) { Add-JournalCommand -Description $Description -UndoCommand $UndoCommand }
            return $true
        }
        Write-Fail "$Description (exit $LASTEXITCODE) $((($out | Out-String).Trim() -split "`n")[0])"
    } catch { Write-Fail "$Description - $($_.Exception.Message)" }
    return $false
}

# ---------------- Restore point ----------------

function New-RestorePoint {
    param([string]$Description = "itzBuddy $($script:SessionId)")
    Write-Head 'System Restore Point'
    if ($script:DryRun) { Write-Dry 'restore point not created'; return }
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        # Windows only allows one restore point per 24h unless this is 0.
        $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $old = Get-RegValue $srKey 'SystemRestorePointCreationFrequency'
        New-ItemProperty -LiteralPath $srKey -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
        $rv = $null
        if ($script:WmiHealthy) {
            $rv = Invoke-WithTimeout -Seconds 120 -What 'restore point' -ArgumentList $Description -Script {
                param($d)
                (Invoke-CimMethod -Namespace root/default -ClassName SystemRestore -MethodName CreateRestorePoint `
                    -Arguments @{ Description = $d; RestorePointType = [uint32]12; EventType = [uint32]100 } -ErrorAction Stop).ReturnValue
            }
        }
        if ($null -eq $old) { Remove-ItemProperty -LiteralPath $srKey -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue }
        else { New-ItemProperty -LiteralPath $srKey -Name 'SystemRestorePointCreationFrequency' -Value $old -PropertyType DWord -Force | Out-Null }
        if ($null -eq $rv) {
            Write-Fail 'Restore point could not be created (WMI not responding)'
            Write-Info 'Continuing - every change is still journaled and can be undone from the menu.'
        }
        elseif ([int]$rv -eq 0) { Write-OK "Restore point created: $Description" }
        else { Write-Fail "Restore point returned code $rv (System Protection may be off)" }
    } catch {
        Write-Fail "Restore point: $($_.Exception.Message)"
        Write-Info 'Continuing - every change is still journaled and can be undone from the menu.'
    }
}

function Restart-Explorer {
    # Windows relaunches the shell by itself (as the normal user) after it is
    # stopped. We only step in if it hasn't come back, and then start it with
    # a basic-user token: launching explorer.exe straight from this elevated
    # process would make the whole desktop shell run as administrator.
    if ($script:DryRun) { return }
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 16; $i++) {
        Start-Sleep -Milliseconds 500
        if (Get-Process -Name explorer -ErrorAction SilentlyContinue) { return }
    }
    Start-Process -FilePath "$env:SystemRoot\System32\runas.exe" -ArgumentList '/trustlevel:0x20000', "`"$env:SystemRoot\explorer.exe`"" -WindowStyle Hidden
}
