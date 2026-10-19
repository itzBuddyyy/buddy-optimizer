# ==============================================================
#  Power plans
#  Replaces: Tweak+ powercfg block, suite STEP 1/2, RestorePowerPlans.ps1
#  Fixes: no longer deletes Balanced/High/Power Saver plans, GUID parsing
#  works on any Windows language, laptop-aware.
# ==============================================================

$script:GuidRx       = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
$script:BitsumGuid   = '77777777-7777-7777-7777-777777777777'
$script:UltimateTpl  = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$script:HighPerfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:DefaultPlans = @('381b4222-f694-41f0-9685-ff5bb260df2e', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'a1841308-3541-4fab-bc81-f71556f20b4a')

function Get-ActivePlanGuid {
    $o = powercfg /getactivescheme 2>$null | Out-String
    if ($o -match $script:GuidRx) { return $Matches[0].ToLower() }
    return $null
}

function Get-PowerPlans {
    $list = @()
    foreach ($line in (powercfg /list 2>$null)) {
        if ($line -match "($($script:GuidRx))\s+\((.+?)\)") {
            $list += [pscustomobject]@{ Guid = $Matches[1].ToLower(); Name = $Matches[2]; Active = $line -match '\*\s*$' }
        }
    }
    return $list
}

function Set-PlanTweaks {
    # Extra settings applied to the chosen plan (AC only - battery untouched).
    param([string]$Guid)
    $tweaks = @(
        @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', 0, 'USB selective suspend OFF'),
        @('501a4d13-42af-4429-9fd1-a8218c268e20', 'ee12f906-d277-404b-b6da-e5fa1a576df5', 0, 'PCIe Link State Power Management OFF')
    )
    if (-not $script:Sys.IsLaptop) {
        $tweaks += , @('54533251-82be-4824-96c1-47b60b740d00', '0cc5b647-c1df-4637-891a-dec35c318583', 100, 'Core parking OFF (min cores 100%)')
        $tweaks += , @('54533251-82be-4824-96c1-47b60b740d00', 'bc5038f7-23e0-4960-96da-33abaf5935ec', 100, 'Max processor state 100%')
    }
    foreach ($t in $tweaks) {
        if ($script:DryRun) { Write-Dry "powercfg $($t[3])"; continue }
        powercfg /setacvalueindex $Guid $t[0] $t[1] $t[2] 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-OK $t[3] } else { Write-Skip "$($t[3]) - not exposed by this plan" }
    }
    if (-not $script:DryRun) { powercfg /setactive $Guid 2>&1 | Out-Null }
}

function Invoke-PowerPlan {
    # -Choice 1/2/3 skips the prompt (used by the Buddy Optimizer app)
    param([switch]$Auto, [ValidateSet('', '1', '2', '3')][string]$Choice = '')
    Write-Head 'Power Plan'
    $prev = Get-ActivePlanGuid
    $choice = if ($script:Sys.IsLaptop) { '3' } else { '1' }
    if ($Choice) { $choice = $Choice; $Auto = $true }

    if (-not $Auto) {
        Write-Host ""
        Write-Host "  1  Bitsum Highest Performance (bundled - best for desktops)" -ForegroundColor White
        Write-Host "  2  Ultimate Performance (Windows built-in)" -ForegroundColor White
        Write-Host "  3  High Performance (best for laptops - keeps boost behavior sane)" -ForegroundColor White
        Write-Host "  Q  Cancel" -ForegroundColor DarkGray
        $suggest = if ($script:Sys.IsLaptop) { 'Laptop detected: 3 suggested.' } else { 'Desktop detected: 1 suggested.' }
        Write-Host "  $suggest" -ForegroundColor DarkGray
        $in = (Read-Host "  Choose plan [$choice]").Trim().ToUpper()
        if ($in -eq 'Q') { return }
        if ($in -in @('1','2','3')) { $choice = $in }
    }

    $target = $null
    $plans = Get-PowerPlans
    switch ($choice) {
        '1' {
            $pow = Join-Path $script:FilesDir 'Power.pow'
            $bitsum = $plans | Where-Object { $_.Guid -eq $script:BitsumGuid -or $_.Name -match 'Bitsum' } | Select-Object -First 1
            if ($bitsum) { $target = $bitsum.Guid; Write-Info 'Bitsum plan already installed' }
            elseif (Test-Path -LiteralPath $pow) {
                if ($script:DryRun) { Write-Dry "powercfg -import Power.pow"; $target = $script:BitsumGuid }
                else {
                    powercfg -import "$pow" $script:BitsumGuid 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) { $target = $script:BitsumGuid; Write-OK 'Bitsum Highest Performance imported' }
                    else { Write-Fail 'Bitsum import failed - falling back to Ultimate Performance'; $choice = '2' }
                }
            } else { Write-Fail 'files\Power.pow missing - falling back to Ultimate Performance'; $choice = '2' }
        }
    }
    if ($choice -eq '2') {
        $existing = $plans | Where-Object { $_.Name -match 'Ultimate|Prestazioni eccellenti|Ultimative|maximales|Rendimiento m.ximo|Performances optimales' } | Select-Object -First 1
        if ($existing) { $target = $existing.Guid; Write-Info 'Ultimate Performance already present' }
        elseif ($script:DryRun) { Write-Dry 'powercfg -duplicatescheme Ultimate'; $target = $script:UltimateTpl }
        else {
            $o = powercfg -duplicatescheme $script:UltimateTpl 2>&1 | Out-String
            if ($o -match $script:GuidRx) { $target = $Matches[0].ToLower(); Write-OK 'Ultimate Performance created' }
            else { Write-Fail 'Ultimate Performance unavailable on this edition - using High Performance'; $choice = '3' }
        }
    }
    if ($choice -eq '3') {
        if ($plans.Guid -notcontains $script:HighPerfGuid -and -not $script:DryRun) {
            powercfg -duplicatescheme $script:HighPerfGuid $script:HighPerfGuid 2>&1 | Out-Null
        }
        $target = $script:HighPerfGuid
    }

    if (-not $target) { Write-Fail 'No plan could be activated'; return }
    if ($script:DryRun) { Write-Dry "powercfg /setactive $target" }
    else {
        powercfg /setactive $target 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Active plan: $target"
            if ($prev -and $prev -ne $target) { Add-JournalCommand -Description 'Power plan changed' -UndoCommand "powercfg /setactive $prev" }
        } else { Write-Fail "Could not activate $target" }
    }
    Set-PlanTweaks -Guid $target

    # Hibernation: frees disk space equal to RAM and disables Fast Startup
    # (Fast Startup keeps a stale kernel/driver state between boots).
    if (-not $script:Sys.IsLaptop) {
        [void](Invoke-Native -Description 'Hibernation + Fast Startup OFF' -File 'powercfg.exe' -Arguments @('/hibernate','off') -UndoCommand 'powercfg /hibernate on')
    } else {
        Write-Skip 'Hibernation left ON (laptop - you may need it on battery)'
    }
}

function Invoke-RestorePowerPlans {
    Write-Head 'Restore default power plans'
    Write-Info 'Resets Windows to its default plans, re-adds Ultimate Performance,'
    Write-Info 'and re-imports the plan you are using now (e.g. Bitsum) so nothing is lost.'
    if (-not (Confirm-Action 'Proceed?')) { return }
    $active = Get-ActivePlanGuid
    if (-not $active) { Write-Fail 'Cannot read the active plan GUID'; return }
    $backup = Join-Path $script:BackupDir "powerplan-$($script:SessionId).pow"
    if ($script:DryRun) { Write-Dry "export $active, restoredefaultschemes, re-import"; return }

    $isDefault = $script:DefaultPlans -contains $active
    if (-not $isDefault) {
        powercfg -export "$backup" $active 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-OK "Current plan backed up: $backup" }
        else { Write-Fail 'Backup of current plan failed - aborting so nothing is lost'; return }
    }
    powercfg -restoredefaultschemes 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-OK 'Default plans restored (Balanced / High Performance / Power Saver)' } else { Write-Fail 'restoredefaultschemes failed' }
    $o = powercfg -duplicatescheme $script:UltimateTpl 2>&1 | Out-String
    if ($o -match $script:GuidRx) { Write-OK 'Ultimate Performance added' } else { Write-Skip 'Ultimate Performance not available on this edition' }

    if (-not $isDefault) {
        $o = powercfg -import "$backup" 2>&1 | Out-String
        if ($o -match $script:GuidRx) {
            powercfg /setactive $Matches[0] 2>&1 | Out-Null
            Write-OK 'Your previous plan was re-imported and set active'
        } else { Write-Fail "Re-import failed - the backup is still at $backup" }
    } else {
        powercfg /setactive $active 2>&1 | Out-Null
    }
}
