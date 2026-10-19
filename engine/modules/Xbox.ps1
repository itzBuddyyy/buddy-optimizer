# ==============================================================
#  Xbox / Microsoft Store
#  Rewrite of itzBuddy_XboxFix.bat and itzBuddy_XboxFix_REVERT.bat.
#  Fixes: "sc config X start=auto" was missing the space sc.exe needs
#  ("start= auto"), so most service changes silently failed; services now
#  go back to their real Windows defaults (several were forced to Auto);
#  the background-apps policy that also blocks Xbox is removed; the Store
#  cache can be reset. Lockdown never touches XboxGipSvc (controllers) or
#  wlidsvc (Microsoft Account sign-in for Windows itself).
# ==============================================================

$script:XboxServiceDefaults = [ordered]@{
    XblAuthManager    = 'Manual'
    XblGameSave       = 'Manual'
    XboxNetApiSvc     = 'Manual'
    XboxGipSvc        = 'Manual'
    GamingServices    = 'Automatic'
    GamingServicesNet = 'Automatic'
    InstallService    = 'Manual'
    wlidsvc           = 'Manual'
    ClipSVC           = 'Manual'
    LicenseManager    = 'Manual'
    StorSvc           = 'Manual'
    WpnService        = 'Automatic'
    wuauserv          = 'Manual'
    BITS              = 'Manual'
    CryptSvc          = 'Automatic'
}

$script:XboxBgApps = @('Microsoft.GamingApp_8wekyb3d8bbwe', 'Microsoft.XboxApp_8wekyb3d8bbwe', 'Microsoft.WindowsStore_8wekyb3d8bbwe',
                       'Microsoft.Xbox.TCUI_8wekyb3d8bbwe', 'Microsoft.XboxGamingOverlay_8wekyb3d8bbwe', 'Microsoft.XboxIdentityProvider_8wekyb3d8bbwe')

function Invoke-XboxFix {
    # -ResetStore runs wsreset without asking; -NoStoreReset never asks (app use)
    param([switch]$ResetStore, [switch]$NoStoreReset)
    Write-Head 'Xbox & Microsoft Store fix'
    Write-Info 'Restores the services, permissions and policies Xbox / Game Pass / Store need.'
    if (-not (Confirm-Action 'Run the fix?')) { return }

    Write-Head 'Services -> Windows defaults'
    foreach ($s in $script:XboxServiceDefaults.Keys) {
        Set-ServiceStart -Name $s -Start $script:XboxServiceDefaults[$s] -StartNow
    }

    Write-Head 'Permissions & background access'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 1
    foreach ($a in $script:XboxBgApps) {
        $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\$a"
        Set-Reg $k 'Disabled' 0 -Quiet
        Set-Reg $k 'DisabledByUser' 0 -Quiet
    }
    Write-OK 'Background access re-allowed for Xbox / Store apps'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground'
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\userAccountInformation' 'Value' 'Allow' 'String'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsMSACloudSearchEnabled' 1

    Write-Head 'Store policy'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' 'AutoDownload'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' 'RemoveWindowsStore'
    Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR'

    $doReset = $false
    if ($ResetStore) { $doReset = $true }
    elseif (-not $NoStoreReset -and -not $script:AutoYes) { $doReset = Confirm-Action 'Also reset the Microsoft Store cache (wsreset)?' -DefaultNo }
    if (-not $script:DryRun -and $doReset) {
        Start-Process -FilePath 'wsreset.exe' -WindowStyle Hidden
        Write-OK 'Store cache reset started (the Store opens when done)'
    }
    $script:XboxMode = $true
    $script:RebootNeeded = $true
    Write-Info 'Reboot, then open the Xbox app / Microsoft Store and sign in.'
}

function Invoke-XboxLockdown {
    Write-Head 'Xbox lockdown (old "REVERT" script)'
    Write-Warn 'Xbox app, Game Pass, Xbox Live sign-in and Microsoft Store downloads will STOP working.'
    Write-Info 'Xbox controllers keep working. Windows Microsoft-Account sign-in keeps working.'
    if (-not (Confirm-Action 'Disable Xbox services?' -DefaultNo)) { return }
    foreach ($s in @('XblAuthManager','XblGameSave','XboxNetApiSvc','GamingServices','GamingServicesNet')) {
        Set-ServiceStart -Name $s -Start Disabled
    }
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
    foreach ($a in $script:XboxBgApps) {
        Set-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\$a" 'Disabled' 1 -Quiet
    }
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    $script:XboxMode = $false
    $script:RebootNeeded = $true
    Write-Info 'Run "Xbox / Store Fix" any time to undo this.'
}
