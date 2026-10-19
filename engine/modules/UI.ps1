# ==============================================================
#  Windows look & feel (optional - pick groups)
#  From Tweak+ Registry.reg (taskbar/explorer/personalization/sound/
#  visual effects), gaming-tweaks-v2.reg section 3/6, Tiles.ps1 and the
#  wallpaper step of optimization.cmd.
#  Fixes: UserPreferencesMask was written as REG_EXPAND_SZ (hex(2)) -
#  Windows needs REG_BINARY, so the old value was ignored or broke the
#  visual settings. Forced 100% DPI scaling removed (made text tiny /
#  blurry on 1440p, 4K and laptop screens). Notification Center and
#  security-notification removal dropped (hid Defender warnings).
#  Tiles.ps1 used a Windows 10-only layout file that does nothing on
#  Windows 11 - Windows 11 now gets the proper Start settings instead.
#  Wallpaper is applied with SystemParametersInfo (the old RUNDLL32 trick
#  often didn't refresh it).
# ==============================================================

function Set-UIVisual {
    Write-Head 'Visual effects: best performance, readable fonts kept'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3
    Set-Reg 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) 'Binary'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'FontSmoothing' '2' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'FontSmoothingType' 2
    Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '0' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg $adv 'TaskbarAnimations' 0
    Set-Reg $adv 'ListviewAlphaSelect' 0
    Set-Reg $adv 'ListviewShadow' 0
    Set-Reg $adv 'IconsOnly' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'AlwaysHibernateThumbnails' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
}

function Set-UITaskbar {
    Write-Head 'Taskbar: left aligned, no Chat/Task View/Search/Widgets'
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    if ($script:Sys.IsWin11) { Set-Reg $adv 'TaskbarAl' 0; Set-Reg $adv 'TaskbarMn' 0 }
    Set-Reg $adv 'ShowTaskViewButton' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'HideSCAMeetNow' 1
    # Widgets: the HKCU TaskbarDa value is locked on 24H2+, the policy works everywhere
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0
    Set-Reg $adv 'MultiTaskingAltTabFilter' 3     # Alt+Tab: windows only, no Edge tabs
}

function Set-UIExplorer {
    Write-Head 'File Explorer'
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg $adv 'LaunchTo' 1                      # open to This PC
    Set-Reg $adv 'HideFileExt' 0                   # show extensions
    Set-Reg $adv 'Start_TrackDocs' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 0
    if ($script:Sys.IsWin11) {
        Set-Reg 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '' '' 'String'
        Write-Info 'Classic right-click menu restored'
    }
}

function Set-UIStart {
    Write-Head 'Start menu cleanup'
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecentlyAddedApps' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'ShowOrHideMostUsedApps' 2
    Set-Reg $adv 'Start_TrackProgs' 0
    if ($script:Sys.IsWin11) {
        Set-Reg $adv 'Start_IrisRecommendations' 0     # no "recommended" ads
        Set-Reg $adv 'Start_AccountNotifications' 0
        Set-Reg $adv 'Start_Layout' 1                  # more pins, less recommended
        Write-Info 'Windows 11: recommendations hidden, more pins layout.'
    } else {
        Clear-Win10StartTiles
    }
}

function Clear-Win10StartTiles {
    # Fixed version of Tiles.ps1 (Windows 10 only): blank layout applied once,
    # then unlocked so you can pin again. Errors are handled and the policy
    # values are removed afterwards instead of being left at 0.
    if ($script:DryRun) { Write-Dry 'Windows 10 blank start layout'; return }
    $layout = Join-Path $env:TEMP 'itzBuddy-StartLayout.xml'
    @'
<LayoutModificationTemplate xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" Version="1" xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification">
  <LayoutOptions StartTileGroupCellWidth="6" />
  <DefaultLayoutOverride><StartLayoutCollection><defaultlayout:StartLayout GroupCellWidth="6" /></StartLayoutCollection></DefaultLayoutOverride>
</LayoutModificationTemplate>
'@ | Set-Content -LiteralPath $layout -Encoding ASCII
    foreach ($h in @('HKLM','HKCU')) {
        $k = "${h}:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        Set-ItemProperty -Path $k -Name LockedStartLayout -Value 1 -Type DWord
        Set-ItemProperty -Path $k -Name StartLayoutFile -Value $layout -Type ExpandString
    }
    Restart-Explorer
    Start-Sleep -Seconds 5
    (New-Object -ComObject WScript.Shell).SendKeys('^{ESCAPE}')
    Start-Sleep -Seconds 4
    foreach ($h in @('HKLM','HKCU')) {
        $k = "${h}:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
        Remove-ItemProperty -Path $k -Name LockedStartLayout, StartLayoutFile -ErrorAction SilentlyContinue
    }
    Restart-Explorer
    Remove-Item -LiteralPath $layout -Force -ErrorAction SilentlyContinue
    Write-OK 'Windows 10 Start tiles cleared (you can pin apps again)'
}

function Set-UIDark {
    Write-Head 'Dark theme + dark grey accent'
    $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-Reg $p 'AppsUseLightTheme' 0
    Set-Reg $p 'SystemUsesLightTheme' 0
    $acc = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
    Set-Reg $acc 'StartColorMenu' 0xff3d3f41
    Set-Reg $acc 'AccentColorMenu' 0xff484a4c
    Set-Reg $acc 'AccentPalette' ([byte[]](0xDF,0xDE,0xDC,0x00,0xA6,0xA5,0xA1,0x00,0x68,0x65,0x62,0x00,0x4C,0x4A,0x48,0x00,0x41,0x3F,0x3D,0x00,0x27,0x25,0x24,0x00,0x10,0x0D,0x0D,0x00,0x10,0x7C,0x10,0x00)) 'Binary'
    $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
    Set-Reg $dwm 'EnableWindowColorization' 1
    Set-Reg $dwm 'AccentColor' 0xff484a4c
    Set-Reg $dwm 'ColorizationColor' 0xc44c4a48
    Set-Reg $dwm 'ColorizationAfterglow' 0xc44c4a48
}

function Set-UISounds {
    Write-Head 'System sounds OFF (no dings over game audio)'
    Set-Reg 'HKCU:\AppEvents\Schemes' '' '.None' 'String'
    $n = 0
    foreach ($k in @(Get-ChildItem -Path 'HKCU:\AppEvents\Schemes\Apps' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq '.Current' })) {
        $path = $k.Name -replace '^HKEY_CURRENT_USER', 'HKCU:'
        $cur = [string](Get-RegValue $path '(default)' '')
        if ($cur -ne '') { Set-Reg $path '' '' 'String' -Quiet; $n++ }
    }
    Write-OK "$n event sounds silenced"
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation' 'DisableStartupSound' 1
    Set-Reg 'HKCU:\Software\Microsoft\Multimedia\Audio' 'UserDuckingPreference' 3   # never lower game volume during calls
}

function Set-Wallpaper {
    Write-Head 'itzBuddy wallpaper'
    $srcImg = Join-Path $script:FilesDir 'Wallpaper.png'
    if (-not (Test-Path -LiteralPath $srcImg)) { Write-Fail 'files\Wallpaper.png missing'; return }
    $dest = Join-Path $script:DataRoot 'Wallpaper.png'
    $old = [string](Get-RegValue 'HKCU:\Control Panel\Desktop' 'WallPaper' '')
    if ($script:DryRun) { Write-Dry "wallpaper -> $dest"; return }
    Copy-Item -LiteralPath $srcImg -Destination $dest -Force
    Backup-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper'
    # SPI_SETDESKWALLPAPER = 0x14, update ini + broadcast
    if ([itzBuddy.Native]::SystemParametersInfoW(0x0014, 0, $dest, 0x03)) { Write-OK 'Wallpaper applied' }
    else { Write-Fail 'Wallpaper could not be applied' }
    if ($old) { Add-JournalCommand -Description 'Wallpaper' -UndoCommand "reg add `"HKCU\Control Panel\Desktop`" /v WallPaper /t REG_SZ /d `"$old`" /f" }
}

function Invoke-UITweaks {
    $groups = @(
        @{ Label = 'Visual effects - best performance';        Fn = 'Set-UIVisual';    Selected = $true }
        @{ Label = 'Taskbar - clean (no widgets/chat/search)'; Fn = 'Set-UITaskbar';   Selected = $true }
        @{ Label = 'File Explorer - This PC, extensions, classic menu'; Fn = 'Set-UIExplorer'; Selected = $true }
        @{ Label = 'Start menu cleanup (replaces Tiles.ps1)';  Fn = 'Set-UIStart';     Selected = $true }
        @{ Label = 'System sounds off';                         Fn = 'Set-UISounds';    Selected = $true }
        @{ Label = 'Dark theme';                                Fn = 'Set-UIDark';      Selected = $false }
        @{ Label = 'itzBuddy wallpaper';                        Fn = 'Set-Wallpaper';   Selected = $false }
    )
    $sel = Select-Items -Items $groups -Title 'LOOK & FEEL - choose groups to apply'
    Clear-Host
    if ($sel.Count -eq 0) { Write-Info 'Nothing selected.'; return }
    if (-not (Confirm-Action "Apply $($sel.Count) group(s)? (Explorer restarts at the end)")) { return }
    foreach ($s in $sel) { & $s.Fn }
    Write-Info 'Restarting Explorer to apply...'
    Restart-Explorer
}
