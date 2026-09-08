#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Run','Status','Build')]
    [string]$Action = 'Run',
    [string]$PolicyFile,
    [switch]$Rebuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UpdaterCommon.ps1')

$script:RunDetailsPath = $null
$script:LastBanner = $null

function Invoke-SelfElevation {
    if (Test-Administrator) { return }
    $arguments = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath),'-Action',$Action)
    if ($PolicyFile) { $arguments += @('-PolicyFile',('"{0}"' -f $PolicyFile)) }
    if ($Rebuild) { $arguments += '-Rebuild' }
    $process = Start-Process -Verb RunAs -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -PassThru -Wait
    exit $process.ExitCode
}

function Ensure-UpdaterBuilt {
    param([switch]$Force)
    if ($script:IsPortableRuntime) {
        if ($Force) { throw 'This portable runtime cannot rebuild itself. Use the complete V0.831 source package.' }
        Assert-PortableRuntimeIntegrity
        if (Test-UpdaterExecutable) { return }
        throw 'The portable updater failed its integrity or startup check.'
    }
    if (-not $Force -and (Test-UpdaterExecutable)) { return }
    & (Join-Path $PSScriptRoot 'Build-Windows11-x64.ps1')
    if (-not (Test-UpdaterExecutable)) { throw 'The build completed, but the updater failed its startup check.' }
}

function Initialize-RunDetailsLog {
    Ensure-Directories
    $script:RunDetailsPath = Join-Path $script:LogDir ("run-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    @(
        'IFX TPM Firmware Updater V0.831 - detailed run log'
        "Started UTC: $((Get-Date).ToUniversalTime().ToString('o'))"
        "Package: $script:PackageVersion"
        "Build ID: $script:BuildId"
        "Computer: $env:COMPUTERNAME"
        "Portable root: $script:PackageRoot"
        "Action: $Action"
        ''
    ) | Set-Content -LiteralPath $script:RunDetailsPath -Encoding UTF8
}

function Write-RunDetail {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($script:RunDetailsPath) { Add-Content -LiteralPath $script:RunDetailsPath -Value $Text -Encoding UTF8 }
}

function Write-RunObject {
    param([Parameter(Mandatory)][string]$Label,[AllowNull()]$Value)
    Write-RunDetail "$Label`:"
    if ($null -eq $Value) { Write-RunDetail '<null>' }
    else { Write-RunDetail ($Value | ConvertTo-Json -Depth 12) }
    Write-RunDetail ''
}

function Write-RunFileSection {
    param([Parameter(Mandatory)][string]$Label,[AllowNull()][string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    Write-RunDetail "===== $Label ====="
    Write-RunDetail "Source file: $Path"
    try { Write-RunDetail (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop) }
    catch { Write-RunDetail "Could not copy this diagnostic file into the run log: $($_.Exception.Message)" }
    Write-RunDetail "===== END $Label ====="
    Write-RunDetail ''
}

function New-WorkflowForState {
    param([Parameter(Mandatory)]$DirectState,[Parameter(Mandatory)][string]$ComputerFingerprint,[AllowNull()][string]$EndorsementKeyHash)
    $chain = @(Get-FirmwareUpgradeChain -Version ([string]$DirectState.Version))
    $path = @($chain | ForEach-Object {
        [ordered]@{
            SourceVersion = [string]$_.SourceVersion
            TargetVersion = [string]$_.TargetVersion
            FirmwareFile = [string]$_.FirmwareFile
            FirmwareSha256 = [string]$_.FirmwareSha256
        }
    })
    return [ordered]@{
        SchemaVersion = 100
        PackageBuildId = $script:BuildId
        ComputerFingerprint = $ComputerFingerprint
        TpmEndorsementKeyHash = $EndorsementKeyHash
        InitialVersion = [string]$DirectState.Version
        Path = $path
        CompletedTargets = @()
        RebootedAfterTargets = @()
        PendingRebootTarget = $null
        PendingRebootBootId = $null
        UefiDisableRequestedUtc = $null
        UefiEnableRequestedUtc = $null
        CreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-WorkflowVersions {
    param([Parameter(Mandatory)]$Workflow)
    $versions = New-Object System.Collections.Generic.List[string]
    $versions.Add([string]$Workflow.InitialVersion)
    foreach ($route in @($Workflow.Path)) {
        if (-not $versions.Contains([string]$route.TargetVersion)) { $versions.Add([string]$route.TargetVersion) }
    }
    return $versions.ToArray()
}

function Test-WorkflowUsable {
    param([AllowNull()]$Workflow,[Parameter(Mandatory)]$DirectState,[Parameter(Mandatory)][string]$ComputerFingerprint,[AllowNull()][string]$EndorsementKeyHash)
    if ($null -eq $Workflow) { return $false }
    try {
        if ([int]$Workflow.SchemaVersion -ne 100 -or [string]$Workflow.PackageBuildId -ne $script:BuildId) { return $false }
        if ([string]$Workflow.ComputerFingerprint -ne $ComputerFingerprint) { return $false }
        if ($EndorsementKeyHash -and [string]$Workflow.TpmEndorsementKeyHash -and [string]$Workflow.TpmEndorsementKeyHash -ne $EndorsementKeyHash) { return $false }
        if (@(Get-WorkflowVersions -Workflow $Workflow) -notcontains [string]$DirectState.Version) { return $false }
        $expected = @(Get-FirmwareUpgradeChain -Version ([string]$Workflow.InitialVersion))
        $saved = @($Workflow.Path)
        if ($expected.Count -ne $saved.Count) { return $false }
        for ($index = 0; $index -lt $expected.Count; $index++) {
            if ([string]$expected[$index].SourceVersion -ne [string]$saved[$index].SourceVersion -or
                [string]$expected[$index].TargetVersion -ne [string]$saved[$index].TargetVersion -or
                [string]$expected[$index].FirmwareSha256 -ne [string]$saved[$index].FirmwareSha256) { return $false }
        }
    } catch { return $false }
    return $true
}

function Add-UniqueWorkflowValue {
    param([Parameter(Mandatory)]$Workflow,[Parameter(Mandatory)][string]$Property,[Parameter(Mandatory)][string]$Value)
    $items = @($Workflow.$Property)
    if ($items -notcontains $Value) { $Workflow.$Property = @($items + $Value) }
}

function Update-WorkflowFromLiveState {
    param([Parameter(Mandatory)]$Workflow,[Parameter(Mandatory)]$DirectState,[Parameter(Mandatory)][string]$BootIdentifier,[AllowNull()][string]$EndorsementKeyHash)
    if ($EndorsementKeyHash -and -not [string]$Workflow.TpmEndorsementKeyHash) { $Workflow.TpmEndorsementKeyHash = $EndorsementKeyHash }
    $versions = @(Get-WorkflowVersions -Workflow $Workflow)
    $liveIndex = [array]::IndexOf($versions, [string]$DirectState.Version)
    if ($liveIndex -lt 0) { throw 'The live TPM firmware does not match the saved update workflow.' }

    # Live firmware is authoritative. Saved update checkmarks survive only
    # when the current version proves that the target was reached or passed.
    $verifiedTargets = New-Object System.Collections.Generic.List[string]
    foreach ($route in @($Workflow.Path)) {
        $targetIndex = [array]::IndexOf($versions, [string]$route.TargetVersion)
        if ($targetIndex -ge 0 -and $liveIndex -ge $targetIndex) { $verifiedTargets.Add([string]$route.TargetVersion) }
    }
    $Workflow.CompletedTargets = $verifiedTargets.ToArray()

    if ([string]$Workflow.PendingRebootTarget) {
        $pendingIndex = [array]::IndexOf($versions, [string]$Workflow.PendingRebootTarget)
        if ($liveIndex -lt $pendingIndex) { throw 'The saved workflow reports a completed update that the live TPM firmware does not confirm.' }
        if ([string]$Workflow.PendingRebootBootId -ne $BootIdentifier) {
            Add-UniqueWorkflowValue -Workflow $Workflow -Property 'RebootedAfterTargets' -Value ([string]$Workflow.PendingRebootTarget)
            $Workflow.PendingRebootTarget = $null
            $Workflow.PendingRebootBootId = $null
        }
    }
    $Workflow.UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    Save-Workflow $Workflow
    return $Workflow
}

function Get-CurrentRouteFromWorkflow {
    param([Parameter(Mandatory)]$Workflow,[Parameter(Mandatory)][string]$Version)
    foreach ($route in @($Workflow.Path)) { if ([string]$route.SourceVersion -eq $Version) { return $route } }
    return $null
}

function Get-UiAction {
    param([Parameter(Mandatory)]$Workflow,[Parameter(Mandatory)]$DirectState,[Parameter(Mandatory)][string]$TrustedComputingStatus,[Parameter(Mandatory)][string]$BootIdentifier)
    $version = [string]$DirectState.Version
    $pending = [string]$Workflow.PendingRebootTarget
    if ($pending -and [string]$Workflow.PendingRebootBootId -eq $BootIdentifier) {
        if ($pending -eq '5.67.19690.2') { return [pscustomobject]@{ Type='EnterUefiEnable'; RowKey='final-enable'; Route=$null } }
        return [pscustomobject]@{ Type='Reboot'; RowKey=("reboot-{0}" -f $pending); Route=$null }
    }
    if ($version -eq '5.67.19690.2') {
        if ($TrustedComputingStatus -eq 'Enabled') { return [pscustomobject]@{ Type='Complete'; RowKey=$null; Route=$null } }
        if ($TrustedComputingStatus -eq 'Disabled') { return [pscustomobject]@{ Type='EnterUefiEnable'; RowKey='final-enable'; Route=$null } }
        return [pscustomobject]@{ Type='Blocked'; RowKey=$null; Route=$null }
    }
    if ($TrustedComputingStatus -eq 'Enabled') { return [pscustomobject]@{ Type='EnterUefiDisable'; RowKey='disable'; Route=$null } }
    if ($TrustedComputingStatus -eq 'Disabled') {
        $route = Get-CurrentRouteFromWorkflow -Workflow $Workflow -Version $version
        if ($null -eq $route) { throw "No update route was found for firmware $version." }
        return [pscustomobject]@{ Type='Flash'; RowKey=("update-{0}" -f $route.TargetVersion); Route=$route }
    }
    return [pscustomobject]@{ Type='Blocked'; RowKey=$null; Route=$null }
}

function Get-ChecklistRows {
    param([Parameter(Mandatory)]$Workflow,[Parameter(Mandatory)]$DirectState,[Parameter(Mandatory)][string]$TrustedComputingStatus,[Parameter(Mandatory)]$UiAction)
    $rows = New-Object System.Collections.Generic.List[object]
    $completedTargets = @($Workflow.CompletedTargets)
    $rebootedTargets = @($Workflow.RebootedAfterTargets)
    $atFinal = [string]$DirectState.Version -eq '5.67.19690.2'
    if (@($Workflow.Path).Count -gt 0) {
        $rows.Add([pscustomobject]@{ Key='disable'; Text='Disable Trusted Computing in BIOS/UEFI'; Completed=($TrustedComputingStatus -eq 'Disabled' -or $completedTargets.Count -gt 0 -or $atFinal) })
        $path = @($Workflow.Path)
        for ($index = 0; $index -lt $path.Count; $index++) {
            $route = $path[$index]
            $target = [string]$route.TargetVersion
            $rows.Add([pscustomobject]@{ Key="update-$target"; Text=("Update TPM 2.0 module firmware from {0} to {1}" -f $route.SourceVersion,$target); Completed=($completedTargets -contains $target) })
            if ($index -lt ($path.Count - 1)) {
                $rebootComplete = $rebootedTargets -contains $target
                $rows.Add([pscustomobject]@{ Key="reboot-$target"; Text='Reboot'; Completed=$rebootComplete })
                $rows.Add([pscustomobject]@{ Key="rerun-$target"; Text='Run this program again'; Completed=$rebootComplete })
            }
        }
        $rows.Add([pscustomobject]@{ Key='final-enable'; Text='Reboot and enable Trusted Computing in BIOS/UEFI'; Completed=($atFinal -and $TrustedComputingStatus -eq 'Enabled') })
    } elseif ($atFinal) {
        $rows.Add([pscustomobject]@{ Key='up-to-date'; Text='TPM firmware is up to date'; Completed=$true })
        if ($TrustedComputingStatus -eq 'Disabled') { $rows.Add([pscustomobject]@{ Key='final-enable'; Text='Reboot and enable Trusted Computing in BIOS/UEFI'; Completed=$false }) }
    }
    return $rows.ToArray()
}

function Write-ChecklistRow {
    param([Parameter(Mandatory)]$Row,[Parameter(Mandatory)][bool]$Current)
    $arrow = if ($Current) { [char]0x2192 } else { ' ' }
    $check = if ([bool]$Row.Completed) { [char]0x2713 } else { ' ' }
    $line = (' {0}  {1,-72} {2}' -f $arrow,[string]$Row.Text,$check)
    if ([bool]$Row.Completed) { Write-Host $line -ForegroundColor Green }
    elseif ($Current) { Write-Host $line -ForegroundColor White }
    else { Write-Host $line -ForegroundColor Gray }
}

function Show-Interface {
    param([Parameter(Mandatory)]$Workflow,[Parameter(Mandatory)]$DirectState,[Parameter(Mandatory)][string]$TrustedComputingStatus,[Parameter(Mandatory)]$UiAction,[AllowNull()][string]$Banner)
    try { [Console]::Clear() } catch { Clear-Host }
    Write-Host 'TPM Firmware Updater' -ForegroundColor Cyan
    Write-Host '====================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host ("You have a TPM 2.0 module running firmware version {0}." -f $DirectState.Version)
    $remaining = @(Get-FirmwareUpgradeChain -Version ([string]$DirectState.Version))
    if ($remaining.Count -eq 0) { Write-Host 'Your TPM firmware is up to date.' -ForegroundColor Green }
    elseif ($remaining.Count -eq 1) { Write-Host ("The firmware can be updated to {0}." -f $remaining[0].TargetVersion) }
    else {
        $targets = @($remaining | ForEach-Object { [string]$_.TargetVersion })
        Write-Host ("The firmware can be updated to {0} and then to {1}." -f $targets[0],$targets[1])
    }
    Write-Host ''
    if ($Banner) { Write-Host $Banner -ForegroundColor Green; Write-Host '' }
    foreach ($row in @(Get-ChecklistRows -Workflow $Workflow -DirectState $DirectState -TrustedComputingStatus $TrustedComputingStatus -UiAction $UiAction)) {
        Write-ChecklistRow -Row $row -Current ([string]$row.Key -eq [string]$UiAction.RowKey)
    }
    Write-Host ''
    if ($UiAction.Type -eq 'Complete') { Write-Host 'Everything is complete. Press Esc to exit.' -ForegroundColor Green }
    elseif ($UiAction.Type -eq 'Blocked') { Write-Host 'The BIOS TPM state could not be determined safely. Press Esc to exit.' -ForegroundColor Yellow }
    else { Write-Host 'Press Enter to perform the indicated step, or Esc to exit.' -ForegroundColor DarkGray }
}

function Confirm-Action {
    param([Parameter(Mandatory)][string[]]$Lines)
    Write-Host ''
    foreach ($line in $Lines) { Write-Host $line -ForegroundColor Yellow }
    Write-Host 'Continue? [Y/N] ' -NoNewline -ForegroundColor White
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Y) { Write-Host 'Y'; return $true }
        if ($key.Key -eq [ConsoleKey]::N -or $key.Key -eq [ConsoleKey]::Escape) { Write-Host 'N'; return $false }
    }
}

function Invoke-ShutdownAction {
    param([Parameter(Mandatory)][string]$Mode,[Parameter(Mandatory)]$Workflow)
    if ($Mode -eq 'UefiDisable') {
        Assert-BitLockerProtectionOff
        if (-not (Confirm-Action -Lines @('The computer will reboot and enter UEFI settings.','Save your work. In UEFI, disable Trusted Computing / Security Device Support.'))) { return $false }
        $Workflow.UefiDisableRequestedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Save-Workflow $Workflow
        Write-RunDetail 'Requested shutdown.exe /r /fw /t 0 for the disable-Trusted-Computing step.'
        $arguments = @('/r','/fw','/t','0')
    } elseif ($Mode -eq 'UefiEnable') {
        if (-not (Confirm-Action -Lines @('The computer will reboot and enter UEFI settings.','Save your work. In UEFI, enable Trusted Computing / Security Device Support.'))) { return $false }
        $Workflow.UefiEnableRequestedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Save-Workflow $Workflow
        Write-RunDetail 'Requested shutdown.exe /r /fw /t 0 for the enable-Trusted-Computing step.'
        $arguments = @('/r','/fw','/t','0')
    } else {
        if (-not (Confirm-Action -Lines @('The firmware update is complete and Windows must restart before the next step.','Save your work. The computer will reboot.'))) { return $false }
        Write-RunDetail 'Requested shutdown.exe /r /t 0 for a mandatory intermediate reboot.'
        $arguments = @('/r','/t','0')
    }
    $process = Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList $arguments -PassThru -Wait
    Write-RunDetail "shutdown.exe exit code: $($process.ExitCode)"
    if ($process.ExitCode -ne 0) { throw 'Windows could not start the requested reboot.' }
    return $true
}

function Invoke-SelectedFirmwareUpdate {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Workflow,[Parameter(Mandatory)]$UiAction)
    $route = Get-RouteForVersion ([string]$Context.DirectState.Version)
    if ([string]$route.TargetVersion -ne [string]$UiAction.Route.TargetVersion) { throw 'The selected firmware route changed. Run the updater again.' }
    if (-not (Confirm-Action -Lines @(("The TPM firmware will be updated from {0} to {1}." -f $route.SourceVersion,$route.TargetVersion),'Do not turn off or restart the computer while the progress bar is moving.'))) { return $false }
    Assert-BitLockerProtectionOff
    $live = Get-IfxTpmState
    Write-RunObject -Label 'Immediate pre-flash direct TPM state' -Value $live
    if ([string]$live.Version -ne [string]$Context.DirectState.Version) { throw 'The TPM firmware changed after the initial check.' }
    Assert-StateReadyForUpdate $live
    if ([string]$live.PlatformAuth -ne 'Empty Buffer') { throw 'Trusted Computing is still enabled in BIOS/UEFI.' }
    $firmware = Assert-FirmwareForRoute $route
    $exeHash = Assert-UpdaterExecutable
    $authorization = Resolve-AuthorizationMode -State $live -PolicyFile $PolicyFile
    $plan = New-Plan -State $live -Route $route -Firmware $firmware -ExeSha256 $exeHash -Authorization $authorization
    Save-Plan $plan

    $live2 = Get-IfxTpmState
    Write-RunObject -Label 'Final pre-flash direct TPM state' -Value $live2
    Assert-StateReadyForUpdate $live2
    $authorization2 = Resolve-AuthorizationMode -State $live2 -PolicyFile $PolicyFile
    $route2 = Get-RouteForVersion ([string]$live2.Version)
    $firmware2 = Assert-FirmwareForRoute $route2
    $exeHash2 = Assert-UpdaterExecutable
    if (-not (Test-PlanStillMatches -Plan $plan -State $live2 -Route $route2 -Firmware $firmware2 -ExeSha256 $exeHash2 -Authorization $authorization2)) {
        throw 'The final safety check did not match the approved update.'
    }
    try { [Console]::Clear() } catch { Clear-Host }
    Write-Host 'TPM Firmware Updater' -ForegroundColor Cyan
    Write-Host '====================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host ("Updating firmware from {0} to {1}" -f $route2.SourceVersion,$route2.TargetVersion) -ForegroundColor White
    Write-Host ''
    $flashLog = Invoke-FirmwareFlash -Plan $plan -Route $route2 -Firmware $firmware2 -Authorization $authorization2
    Write-RunDetail "Successful flash log: $flashLog"
    Add-UniqueWorkflowValue -Workflow $Workflow -Property 'CompletedTargets' -Value ([string]$route2.TargetVersion)
    $Workflow.PendingRebootTarget = [string]$route2.TargetVersion
    $Workflow.PendingRebootBootId = [string]$Context.BootIdentifier
    $Workflow.UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    Save-Workflow $Workflow
    # Native success output proves the target. Do not query the TPM again
    # before the mandatory reboot just to redraw the checklist.
    $Context.DirectState.Version = [string]$route2.TargetVersion
    $Context.Workflow = $Workflow
    $script:LastBanner = 'Firmware update completed successfully.'
    return $true
}

function Get-FriendlyErrorMessage {
    param([Parameter(Mandatory)][string]$TechnicalMessage)
    if ($TechnicalMessage -match '(?i)BitLocker protection is ON') { return 'BitLocker protection must be suspended before TPM maintenance can continue.' }
    if ($TechnicalMessage -match '(?i)BitLocker|manage-bde') { return 'The updater could not verify that BitLocker protection is suspended.' }
    if ($TechnicalMessage -match '(?i)did not positively identify|not a supported Infineon|usable TPM 2\.0') { return 'No supported discrete Infineon TPM 2.0 module was detected.' }
    if ($TechnicalMessage -match '(?i)Unsupported TPM firmware version|No update route') { return 'This TPM firmware version is not supported by the firmware files in this updater.' }
    if ($TechnicalMessage -match '(?i)Trusted Computing is still enabled|Security Device Support is enabled') { return 'Trusted Computing is still enabled in BIOS/UEFI. Disable it before updating the TPM firmware.' }
    if ($TechnicalMessage -match '(?i)shutdown|requested reboot') { return 'Windows could not reboot into the requested settings. Restart and enter BIOS/UEFI manually.' }
    if ($TechnicalMessage -match '(?i)timed out') { return 'The TPM did not respond in time. No firmware update was started.' }
    return 'The updater could not continue.'
}

function Show-FatalError {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    try { [Console]::Clear() } catch { Clear-Host }
    Write-Host 'TPM Firmware Updater' -ForegroundColor Cyan
    Write-Host '====================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host (Get-FriendlyErrorMessage -TechnicalMessage $ErrorRecord.Exception.Message) -ForegroundColor Red
    Write-Host ''
    Write-Host ("Details were saved to:`n{0}" -f $script:RunDetailsPath) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Press any key to exit.' -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

function Get-InitialContext {
    $computerFingerprint = Get-ComputerFingerprint
    $bootIdentifier = Get-CurrentBootIdentifier
    $directState = Get-IfxTpmState
    $windowsStatus = Get-WindowsTpmStatus
    $trustedStatus = Get-TrustedComputingStatus -DirectState $directState -WindowsStatus $windowsStatus
    $ekHash = if ($trustedStatus -eq 'Enabled') { Get-TpmEndorsementKeyFingerprint } else { $null }
    Write-RunDetail "Computer fingerprint: $computerFingerprint"
    Write-RunDetail "Boot identifier: $bootIdentifier"
    Write-RunDetail "Trusted Computing status: $trustedStatus"
    Write-RunDetail "TPM endorsement-key SHA-256: $(if($ekHash){$ekHash}else{'<unavailable while hidden from Windows>'})"
    Write-RunObject -Label 'Direct TPM state' -Value $directState
    Write-RunObject -Label 'Windows TPM state' -Value $windowsStatus
    Write-RunFileSection -Label 'DIRECT TPM PROBE' -Path ([string]$directState.InfoLog)
    Write-RunFileSection -Label 'WINDOWS TPM PROBE' -Path ([string]$windowsStatus.LogPath)
    $workflow = Get-Workflow
    Write-RunObject -Label 'Loaded workflow' -Value $workflow
    if (-not (Test-WorkflowUsable -Workflow $workflow -DirectState $directState -ComputerFingerprint $computerFingerprint -EndorsementKeyHash $ekHash)) {
        $workflow = New-WorkflowForState -DirectState $directState -ComputerFingerprint $computerFingerprint -EndorsementKeyHash $ekHash
        Save-Workflow $workflow
        Write-RunDetail 'Created a new workflow because no saved workflow was valid for this computer, TPM identity, firmware path, and package build.'
    }
    $workflow = Update-WorkflowFromLiveState -Workflow $workflow -DirectState $directState -BootIdentifier $bootIdentifier -EndorsementKeyHash $ekHash
    Write-RunObject -Label 'Revalidated workflow' -Value $workflow
    return [pscustomobject]@{
        DirectState=$directState
        WindowsStatus=$windowsStatus
        TrustedComputingStatus=$trustedStatus
        EndorsementKeyHash=$ekHash
        ComputerFingerprint=$computerFingerprint
        BootIdentifier=$bootIdentifier
        Workflow=$workflow
    }
}

try {
    try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false); [Console]::Title = 'TPM Firmware Updater' } catch { }
    Invoke-SelfElevation
    Assert-Administrator
    Ensure-Directories
    Initialize-RunDetailsLog
    if ($Action -eq 'Build') { Ensure-UpdaterBuilt -Force; return }
    Ensure-UpdaterBuilt -Force:$Rebuild
    $context = Get-InitialContext
    while ($true) {
        $uiAction = Get-UiAction -Workflow $context.Workflow -DirectState $context.DirectState -TrustedComputingStatus $context.TrustedComputingStatus -BootIdentifier $context.BootIdentifier
        Show-Interface -Workflow $context.Workflow -DirectState $context.DirectState -TrustedComputingStatus $context.TrustedComputingStatus -UiAction $uiAction -Banner $script:LastBanner
        $script:LastBanner = $null
        if ($Action -eq 'Status') { return }
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Escape) { return }
        if ($key.Key -ne [ConsoleKey]::Enter) { continue }
        switch ($uiAction.Type) {
            'EnterUefiDisable' { if (Invoke-ShutdownAction -Mode 'UefiDisable' -Workflow $context.Workflow) { return } }
            'EnterUefiEnable' { if (Invoke-ShutdownAction -Mode 'UefiEnable' -Workflow $context.Workflow) { return } }
            'Reboot' { if (Invoke-ShutdownAction -Mode 'Reboot' -Workflow $context.Workflow) { return } }
            'Flash' { [void](Invoke-SelectedFirmwareUpdate -Context $context -Workflow $context.Workflow -UiAction $uiAction) }
            default { }
        }
    }
}
catch {
    Write-RunDetail ''
    Write-RunDetail 'FATAL ERROR'
    Write-RunDetail $_.Exception.ToString()
    Write-RunDetail $_.ScriptStackTrace
    Show-FatalError -ErrorRecord $_
    exit 1
}
finally {
    if ($script:RunDetailsPath) { try { Write-RunDetail "Ended UTC: $((Get-Date).ToUniversalTime().ToString('o'))" } catch { } }
}
