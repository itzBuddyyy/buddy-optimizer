# ==============================================================
#  Debloat (optional - choose what to remove)
#  Rewrite of Tweak+\files\Debloat.ps1.
#  Fixes: Remove-AppxPackage now uses -AllUsers and the provisioned copy
#  is removed too (otherwise apps came back for new users / after feature
#  updates); hard-coded C:\Users\Administrator\...\OneDrive paths replaced
#  with real detection; OneDrive removal warns if your Desktop/Documents
#  live in OneDrive; useful tools (Calculator, Snipping Tool, Camera,
#  Notepad, Paint, Clock...) are listed but NOT pre-selected; nothing
#  Xbox/Store related is ever in the list.
# ==============================================================

function Get-DebloatCatalog {
    return @(
        @{ Label = 'Clipchamp';                 Pkg = 'Clipchamp.Clipchamp';                      Selected = $true }
        @{ Label = 'Disney+';                   Pkg = 'Disney.37853FC22B2CE';                     Selected = $true }
        @{ Label = 'Spotify (Store promo)';     Pkg = 'SpotifyAB.SpotifyMusic';                   Selected = $true; Note = 'skip if you use the Store version' }
        @{ Label = 'Cortana (legacy)';          Pkg = 'Microsoft.549981C3F5F10';                  Selected = $true }
        @{ Label = 'Microsoft News';            Pkg = 'Microsoft.BingNews';                       Selected = $true }
        @{ Label = 'Weather';                   Pkg = 'Microsoft.BingWeather';                    Selected = $true }
        @{ Label = 'Bing Search app';           Pkg = 'Microsoft.BingSearch';                     Selected = $true }
        @{ Label = 'Get Help';                  Pkg = 'Microsoft.GetHelp';                        Selected = $true }
        @{ Label = 'Tips';                      Pkg = 'Microsoft.Getstarted';                     Selected = $true }
        @{ Label = '3D Viewer';                 Pkg = 'Microsoft.Microsoft3DViewer';              Selected = $true }
        @{ Label = 'Office Hub / M365 app';     Pkg = 'Microsoft.MicrosoftOfficeHub';             Selected = $true }
        @{ Label = 'Solitaire Collection';      Pkg = 'Microsoft.MicrosoftSolitaireCollection';   Selected = $true }
        @{ Label = 'Mixed Reality Portal';      Pkg = 'Microsoft.MixedReality.Portal';            Selected = $true }
        @{ Label = 'OneNote (Store)';           Pkg = 'Microsoft.Office.OneNote';                 Selected = $true }
        @{ Label = 'People';                    Pkg = 'Microsoft.People';                         Selected = $true }
        @{ Label = 'Power Automate';            Pkg = 'Microsoft.PowerAutomateDesktop';           Selected = $true }
        @{ Label = 'Skype';                     Pkg = 'Microsoft.SkypeApp';                       Selected = $true }
        @{ Label = 'Microsoft To Do';           Pkg = 'Microsoft.Todos';                          Selected = $true }
        @{ Label = 'Wallet';                    Pkg = 'Microsoft.Wallet';                         Selected = $true }
        @{ Label = 'Feedback Hub';              Pkg = 'Microsoft.WindowsFeedbackHub';             Selected = $true }
        @{ Label = 'Maps';                      Pkg = 'Microsoft.WindowsMaps';                    Selected = $true }
        @{ Label = 'Mail & Calendar (legacy)';  Pkg = 'microsoft.windowscommunicationsapps';      Selected = $true }
        @{ Label = 'Outlook (new)';             Pkg = 'Microsoft.OutlookForWindows';              Selected = $true; Note = 'skip if you use it' }
        @{ Label = 'Teams (personal / new)';    Pkg = 'MicrosoftTeams|MSTeams';                   Selected = $true; Note = 'skip if you use it' }
        @{ Label = 'Copilot app';               Pkg = 'Microsoft.Copilot|Microsoft.Windows.Ai.Copilot.Provider'; Selected = $true }
        @{ Label = 'Dev Home';                   Pkg = 'Microsoft.Windows.DevHome';                Selected = $true }
        @{ Label = 'Quick Assist';              Pkg = 'MicrosoftCorporationII.QuickAssist';       Selected = $true }
        @{ Label = 'Widgets (Web Experience)';  Pkg = 'MicrosoftWindows.Client.WebExperience';    Selected = $true }
        @{ Label = 'Phone Link';                Pkg = 'Microsoft.YourPhone';                      Selected = $false; Note = 'useful if you pair your phone' }
        @{ Label = 'Media Player / Groove';     Pkg = 'Microsoft.ZuneMusic';                      Selected = $false }
        @{ Label = 'Movies & TV';               Pkg = 'Microsoft.ZuneVideo';                      Selected = $true }
        @{ Label = 'Sound Recorder';            Pkg = 'Microsoft.WindowsSoundRecorder';           Selected = $false }
        @{ Label = 'Sticky Notes';              Pkg = 'Microsoft.MicrosoftStickyNotes';           Selected = $false }
        @{ Label = 'Clock / Alarms';            Pkg = 'Microsoft.WindowsAlarms';                  Selected = $false }
        @{ Label = 'Camera';                    Pkg = 'Microsoft.WindowsCamera';                  Selected = $false; Note = 'needed for webcam tests' }
        @{ Label = 'Calculator';                Pkg = 'Microsoft.WindowsCalculator';              Selected = $false }
        @{ Label = 'Snipping Tool';             Pkg = 'Microsoft.ScreenSketch';                   Selected = $false; Note = 'Win+Shift+S screenshots' }
        @{ Label = 'Paint';                     Pkg = 'Microsoft.Paint|Microsoft.MSPaint';        Selected = $false }
        @{ Label = 'OneDrive';                  Pkg = '__ONEDRIVE__';                             Selected = $false; Note = 'checks your folders first' }
        @{ Label = 'Windows Hello Face';        Pkg = '__HELLOFACE__';                            Selected = $false; Note = 'breaks face sign-in' }
    )
}

function Remove-AppPackage {
    param([string]$Pattern, [string]$Label)
    $names = $Pattern -split '\|'
    $found = $false
    foreach ($n in $names) {
        $pkgs = @(Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue)
        $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $n })
        if ($pkgs.Count -eq 0 -and $prov.Count -eq 0) { continue }
        $found = $true
        if ($script:DryRun) { Write-Dry "remove $n"; continue }
        foreach ($p in $pkgs) {
            try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
            catch {
                try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { Write-Fail "$Label - $($_.Exception.Message)"; continue }
            }
        }
        foreach ($p in $prov) {
            try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null } catch { }
        }
        Write-OK "Removed: $Label"
    }
    if (-not $found) { Write-Skip "Not installed: $Label" }
}

function Remove-OneDriveSafe {
    $od = $env:OneDrive
    $shell = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $redirected = @()
    foreach ($n in @('Desktop', 'Personal', 'My Pictures')) {
        $v = [string](Get-RegValue $shell $n '')
        if ($v -match 'OneDrive') { $redirected += $n }
    }
    if ($redirected.Count -gt 0) {
        Write-Warn "These folders are stored INSIDE OneDrive: $($redirected -join ', ')"
        Write-Warn 'Uninstalling OneDrive would leave them offline/cloud-only. Turn off folder backup in'
        Write-Warn 'OneDrive settings (Sync and backup > Manage backup) first, then run this again.'
        Write-Skip 'OneDrive kept for safety'
        return
    }
    $setup = @(
        (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
        (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
    ) + @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive') -Filter OneDriveSetup.exe -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName) +
        @(Get-ChildItem -Path "${env:ProgramFiles}\Microsoft OneDrive", "${env:ProgramFiles(x86)}\Microsoft OneDrive" -Filter OneDriveSetup.exe -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $exe = $setup | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $exe) { Write-Skip 'OneDrive not installed'; return }
    if ($script:DryRun) { Write-Dry "$exe /uninstall"; return }
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $exe -ArgumentList '/uninstall' -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -eq 0) { Write-OK 'OneDrive uninstalled (your files in the OneDrive folder were NOT deleted)' }
    else { Write-Fail "OneDrive uninstaller exit code $($p.ExitCode)" }
}

function Get-DebloatState {
    # Catalog + whether each entry is currently installed (one Appx query, not 40)
    $installed = @{}
    try { foreach ($p in @(Get-AppxPackage -AllUsers -ErrorAction Stop)) { $installed[$p.Name.ToLowerInvariant()] = $true } } catch { }
    foreach ($c in (Get-DebloatCatalog)) {
        $isIn = $false
        switch ($c.Pkg) {
            '__ONEDRIVE__'  { $isIn = [bool](Get-Process OneDrive -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe')) -or (Test-Path "${env:ProgramFiles}\Microsoft OneDrive\OneDrive.exe") }
            '__HELLOFACE__' { $isIn = Test-Path (Join-Path $env:SystemRoot 'System32\WinBioPlugIns\FaceDriver') }
            default { foreach ($n in ($c.Pkg -split '\|')) { if ($installed[$n.ToLowerInvariant()]) { $isIn = $true } } }
        }
        [pscustomobject]@{ Label = $c.Label; Pkg = $c.Pkg; Recommended = [bool]$c.Selected; Note = $c.Note; Installed = $isIn }
    }
}

function Remove-DebloatItems {
    # Non-interactive removal by catalog label (used by the app and the console menu)
    param([string[]]$Labels)
    $cat = Get-DebloatCatalog
    foreach ($l in $Labels) {
        $s = $cat | Where-Object { $_.Label -eq $l } | Select-Object -First 1
        if (-not $s) { Write-Skip "Unknown item: $l"; continue }
        switch ($s.Pkg) {
            '__ONEDRIVE__'  { Remove-OneDriveSafe }
            '__HELLOFACE__' { Remove-HelloFace }
            default { Remove-AppPackage -Pattern $s.Pkg -Label $s.Label }
        }
    }
}

function Remove-HelloFace {
    $caps = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'Hello.Face*' -and $_.State -eq 'Installed' })
    if ($caps.Count -eq 0) { Write-Skip 'Windows Hello Face not installed' }
    foreach ($c in $caps) {
        if ($script:DryRun) { Write-Dry "remove capability $($c.Name)"; continue }
        try { Remove-WindowsCapability -Online -Name $c.Name -ErrorAction Stop | Out-Null; Write-OK "Removed capability $($c.Name)" }
        catch { Write-Fail "$($c.Name) - $($_.Exception.Message)" }
    }
}

function Invoke-Debloat {
    $items = Get-DebloatCatalog
    $sel = Select-Items -Items $items -Title 'DEBLOAT - choose apps to remove  (pre-selected = safe for gaming PCs)'
    Clear-Host
    if ($sel.Count -eq 0) { Write-Info 'Nothing selected.'; return }
    Write-Head 'Debloat'
    Write-Host "  Selected: $(($sel | ForEach-Object Label) -join ', ')" -ForegroundColor Gray
    Write-Warn 'Removed apps can be reinstalled from the Microsoft Store, but not by the Undo menu.'
    if (-not (Confirm-Action "Remove these $($sel.Count) apps?")) { return }
    Remove-DebloatItems -Labels @($sel | ForEach-Object Label)
}
