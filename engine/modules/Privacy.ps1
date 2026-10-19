# ==============================================================
#  Privacy, telemetry, ads & suggestions
#  Merges: gaming-tweaks-v2.reg sections 4/9/11/13/14, suite STEP 14/16/17/19
#  and the privacy part of Tweak+ Registry.reg.
#  Removed on purpose:
#   - userAccountInformation=Deny and ToastEnabled=0: they broke Xbox /
#     Store sign-in (that's why XboxFix existed in the first place).
#   - Documents/Pictures/Videos library = Deny: breaks Photos and other
#     built-in apps without any gaming benefit.
#   - Automatic Maintenance OFF: it also stopped SSD TRIM & Defender scans.
#   - "Computer\HKEY_LOCAL_MACHINE\..." key in the old .reg was invalid.
# ==============================================================

function Invoke-Privacy {
    Write-Head 'Telemetry'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'MaxTelemetryAllowed' 0
    Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
    Remove-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' -Quiet
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DisableAutomaticRestartSignOn' 1
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0

    Write-Head 'Activity history / timeline'
    $sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    Set-Reg $sys 'EnableActivityFeed' 0
    Set-Reg $sys 'PublishUserActivities' 0
    Set-Reg $sys 'UploadUserActivities' 0

    Write-Head 'Advertising ID, tailored experiences, inking/typing'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
    Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
    Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
    Set-Reg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
    Set-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1

    Write-Head 'Start menu / search: web results & Copilot-style suggestions OFF'
    $ws = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    Set-Reg $ws 'AllowCortana' 0
    Set-Reg $ws 'DisableWebSearch' 1
    Set-Reg $ws 'ConnectedSearchUseWeb' 0
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
    $ss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
    Set-Reg $ss 'IsDeviceSearchHistoryEnabled' 0
    Set-Reg $ss 'IsDynamicSearchBoxEnabled' 0
    Set-Reg $ss 'IsAADCloudSearchEnabled' 0
    if (-not $script:XboxMode) { Set-Reg $ss 'IsMSACloudSearchEnabled' 0 }

    Write-Head 'Suggestions, tips, sponsored apps OFF'
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($v in @('SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-338393Enabled',
                     'SubscribedContent-353694Enabled','SubscribedContent-353696Enabled','SubscribedContent-310093Enabled',
                     'SystemPaneSuggestionsEnabled','SoftLandingEnabled','RotatingLockScreenOverlayEnabled',
                     'PreInstalledAppsEnabled','PreInstalledAppsEverEnabled','OemPreInstalledAppsEnabled',
                     'SilentInstalledAppsEnabled','ContentDeliveryAllowed','FeatureManagementEnabled')) {
        Set-Reg $cdm $v 0 -Quiet
    }
    Write-OK 'Content Delivery Manager suggestions disabled'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SmartActionPlatform\SmartClipboard' 'Disabled' 1

    Write-Head 'App permissions (camera & microphone stay allowed)'
    $cs = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
    foreach ($cap in @('location','contacts','appointments','phoneCall','phoneCallHistory','email',
                       'userDataTasks','chat','userNotificationListener','appDiagnostics','broadFileSystemAccess')) {
        Set-Reg "$cs\$cap" 'Value' 'Deny' 'String' -Quiet
    }
    Write-OK 'Location, contacts, calendar, calls, email, tasks, messaging, diagnostics -> Deny'
    Set-Reg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\VoiceActivation\UserPreferenceForAllApps' 'AgentActivationEnabled' 0

    Write-Head 'Browsers: no background running / startup boost'
    # Hardware acceleration is NOT disabled (old Registry.reg did): it moved
    # Discord/YouTube/stream decoding onto the CPU, costing FPS in games.
    # Edge/Chrome updaters are NOT disabled either (security).
    foreach ($b in @('HKLM:\SOFTWARE\Policies\Microsoft\Edge','HKLM:\SOFTWARE\Policies\Google\Chrome')) {
        Set-Reg $b 'StartupBoostEnabled' 0 -Quiet
        Set-Reg $b 'BackgroundModeEnabled' 0 -Quiet
    }
    Write-OK 'Edge & Chrome: startup boost and background mode OFF'
}
