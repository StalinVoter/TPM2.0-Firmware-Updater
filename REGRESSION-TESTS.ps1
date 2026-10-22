#requires -Version 5.1
# Tests actual wrapper functions with simulated Windows/TPM/restart responses.
# Does not launch the updater, access a TPM, flash firmware, or reboot.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$originalProgramData = $env:ProgramData
$originalSystemDrive = $env:SystemDrive
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('IFX-085-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$env:ProgramData = $testRoot
$env:SystemDrive = 'C:'
$script:Checks = 0
$script:Cases = 0

function Check {
    param([bool]$Condition,[string]$Message)
    $script:Checks++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}
function Case {
    param([string]$Name,[scriptblock]$Body)
    & $Body
    $script:Cases++
    Write-Host "PASS: $Name"
}
function Expect-Blocked {
    param([scriptblock]$Body,[string]$Pattern)
    $message = $null
    try { & $Body | Out-Null } catch { $message = $_.Exception.Message }
    Check ($null -ne $message) 'The unsafe or unknown state must be blocked.'
    if ($Pattern) { Check ($message -match $Pattern) "Expected error matching $Pattern; got $message" }
    return $message
}

try {
    . (Join-Path $PSScriptRoot 'UpdaterCommon.ps1')
    $tokens = $null; $parseErrors = $null
    $mainAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'TPM-Updater.ps1'),[ref]$tokens,[ref]$parseErrors)
    Check (@($parseErrors).Count -eq 0) 'Main script parses.'
    # Load definitions only. Never evaluate the application entry point.
    $definitions = @{}
    foreach ($statement in $mainAst.EndBlock.Statements) {
        if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) {
            $definitions[$statement.Name] = $statement.Extent.Text
            Invoke-Expression $statement.Extent.Text
        }
    }
    $script:RunDetailsPath = Join-Path $testRoot 'run.txt'
    $script:LogDir = Join-Path $testRoot 'logs'
    $script:MockBoot = 'current-boot'
    $script:MockEk = $null
    $script:MockEnabled = $false
    $script:MockConfirm = $true
    $script:MockDirect = [pscustomobject]@{
        Manufacturer='IFX'; UnsupportedChip='No'; Family='2.0'; Version='5.0.1089.2'
        FirmwareValid='Yes'; OperationMode='Operational'; PlatformAuth='Empty Buffer'
        RemainingUpdates=64; InfoLog=''
    }
    function Get-ComputerFingerprint { return 'test-computer' }
    function Get-CurrentBootIdentifier { return $script:MockBoot }
    function Get-IfxTpmState { return ($script:MockDirect | ConvertTo-Json | ConvertFrom-Json) }
    function Get-WindowsTpmStatus {
        return [pscustomobject]@{QuerySucceeded=$true; TpmPresent=$script:MockEnabled; TpmEnabled=$script:MockEnabled; LogPath=''}
    }
    function Get-TpmEndorsementKeyFingerprint { return $script:MockEk }
    function Confirm-Action { param($Lines); return $script:MockConfirm }
    function Invoke-FirmwareFlash { throw 'TEST TRIPWIRE: firmware flashing must never run in these tests.' }
    function Start-Process { throw 'TEST TRIPWIRE: no native process or reboot may run in these tests.' }

    function Reset-Session {
        param([string]$Version='5.0.1089.2',[bool]$Enabled=$false)
        foreach ($directory in @($script:StateDir,(Split-Path $script:LegacyWorkflowPath -Parent))) {
            if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
        }
        $script:MockDirect.Version = $Version
        $script:MockDirect.PlatformAuth = if($Enabled){'Not Empty Buffer'}else{'Empty Buffer'}
        $script:MockEnabled = $Enabled
        $script:MockEk = $null
        $script:MockBoot = 'current-boot'
        $script:MockConfirm = $true
        $script:LoadedWorkflowPath = $null
    }
    function Write-Legacy {
        param($Workflow)
        New-Item -ItemType Directory -Path (Split-Path $script:LegacyWorkflowPath -Parent) -Force | Out-Null
        $Workflow.PackageBuildId = 'IFX-TPM-UPDATER-V0.831-PORTABLE-20260908'
        $Workflow | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:LegacyWorkflowPath -Encoding UTF8
    }
    function Old-Workflow {
        $old = New-WorkflowForState -DirectState $script:MockDirect -ComputerFingerprint 'test-computer' -EndorsementKeyHash 'previous-tpm-ek'
        $old.CompletedTargets = @('5.62.3126.2','5.67.19690.2')
        $old.RebootedAfterTargets = @('5.62.3126.2')
        $old.PendingRebootTarget = '5.67.19690.2'
        $old.PendingRebootBootId = 'previous-boot'
        $old.UefiDisableRequestedUtc = '2026-09-16T11:00:00Z'
        $old.UefiEnableRequestedUtc = '2026-09-16T12:00:00Z'
        return $old
    }
    function Action-For { param($Context)
        return Get-UiAction -Workflow $Context.Workflow -DirectState $Context.DirectState -TrustedComputingStatus $Context.TrustedComputingStatus -BootIdentifier $Context.BootIdentifier -NeedsNewWorkflow:$Context.NeedsNewWorkflow
    }

    Case 'Reported replacement TPM: offer a fresh session; declining preserves the old record' {
        Reset-Session
        Write-Legacy (Old-Workflow)
        $script:OriginalRecordHash = Get-Sha256 $script:LegacyWorkflowPath
        $script:ReportedContext = Get-InitialContext
        $context = $script:ReportedContext
        Check $context.NeedsNewWorkflow 'Replacement must be recognized despite same computer and unavailable EK.'
        Check ((Action-For $context).Type -eq 'StartNewWorkflow') 'Offer the new-session action.'
        Check (@($context.Workflow.CompletedTargets).Count -eq 0) 'No stale completion checkmarks.'
        Check ($null -eq $context.Workflow.PendingRebootTarget) 'No stale reboot marker.'
        Check (-not (Test-Path $script:WorkflowPath)) 'Merely displaying the offer must not save a replacement.'
        $script:MockConfirm = $false
        Check (-not (Invoke-NewWorkflowAction $context)) 'Declining makes no changes.'
        Check ((Get-Sha256 $script:LegacyWorkflowPath) -eq $script:OriginalRecordHash) 'Legacy record preserved byte-for-byte.'
        Check (-not (Test-Path (Join-Path $script:StateDir 'Archives'))) 'Declining creates no archive.'
    }
    Case 'Accepting a new session archives original bytes and selects the first live firmware hop' {
        $script:MockConfirm = $true
        Check (Invoke-NewWorkflowAction $script:ReportedContext) 'New session accepted.'
        $archives = @(Get-ChildItem (Join-Path $script:StateDir 'Archives') -File)
        Check ($archives.Count -eq 1) 'One archive created.'
        Check ((Get-Sha256 $archives[0].FullName) -eq $script:OriginalRecordHash) 'Archive contains the original bytes.'
        $fresh = Get-Workflow
        Check (@($fresh.CompletedTargets).Count -eq 0) 'Fresh completed targets empty.'
        Check (@($fresh.RebootedAfterTargets).Count -eq 0) 'Fresh reboot history empty.'
        Check ($null -eq $fresh.PendingRebootTarget -and $null -eq $fresh.PendingRebootBootId) 'Pending markers cleared.'
        Check ([string]::IsNullOrEmpty($fresh.TpmEndorsementKeyHash)) 'Old module EK not copied when current EK unavailable.'
        Check ($null -eq $fresh.UefiDisableRequestedUtc -and $null -eq $fresh.UefiEnableRequestedUtc) 'Old UEFI markers not copied.'
        $context = Get-InitialContext
        Check (-not $context.NeedsNewWorkflow) 'Current record takes precedence over legacy.'
        $action = Action-For $context
        Check ($action.Type -eq 'Flash' -and $action.Route.TargetVersion -eq '5.62.3126.2') 'Correct first hop from 5.0.1089.2.'
    }
    Case 'Older live firmware also restarts a completed session with no pending marker' {
        Reset-Session
        $old = Old-Workflow; $old.PendingRebootTarget=$null; $old.PendingRebootBootId=$null
        Write-Legacy $old
        Check (Get-InitialContext).NeedsNewWorkflow 'Completed progress alone must not attach to replacement TPM.'
    }
    Case 'Known different TPM identity requires a fresh session even at the same firmware' {
        Reset-Session -Enabled $true
        $old = New-WorkflowForState $script:MockDirect 'test-computer' 'old-ek'
        Write-Legacy $old; $script:MockEk='new-ek'
        $context = Get-InitialContext
        Check $context.NeedsNewWorkflow 'Known EK mismatch starts a new session.'
        Check ($context.Workflow.TpmEndorsementKeyHash -eq 'new-ek') 'Fresh candidate uses current EK.'
    }
    Case 'Consistent legacy session migrates and retains the UEFI-disable action' {
        Reset-Session -Enabled $true
        $script:MockEk='same-ek'
        Write-Legacy (New-WorkflowForState $script:MockDirect 'test-computer' 'same-ek')
        $context = Get-InitialContext
        Check (-not $context.NeedsNewWorkflow) 'Consistent session resumes.'
        Check ($context.Workflow.PackageBuildId -eq $script:BuildId) 'Explicit legacy migration to current build.'
        Check ((Action-For $context).Type -eq 'EnterUefiDisable') 'Normal BIOS preparation retained.'
    }
    Case 'Same-boot intermediate flash still requires reboot before the next flash' {
        Reset-Session
        $old = New-WorkflowForState $script:MockDirect 'test-computer' $null
        $old.CompletedTargets=@('5.62.3126.2'); $old.PendingRebootTarget='5.62.3126.2'; $old.PendingRebootBootId=$script:MockBoot
        Write-Legacy $old; $script:MockDirect.Version='5.62.3126.2'
        $context=Get-InitialContext
        Check (-not $context.NeedsNewWorkflow) 'Genuine pending reboot is preserved across version migration.'
        Check ((Action-For $context).Type -eq 'Reboot') 'No second flash in the same boot.'
    }
    Case 'After intermediate reboot, verified target selects the second hop' {
        $script:MockBoot='next-boot'; $context=Get-InitialContext
        Check ($null -eq $context.Workflow.PendingRebootTarget) 'Reboot marker cleared after changed boot.'
        Check (@($context.Workflow.RebootedAfterTargets) -contains '5.62.3126.2') 'Reboot completion recorded.'
        $action=Action-For $context
        Check ($action.Type -eq 'Flash' -and $action.Route.TargetVersion -eq '5.67.19690.2') 'Correct second hop.'
    }
    Case 'Native success with firmware not yet exposed retains the same-boot reboot requirement' {
        Reset-Session
        $old=New-WorkflowForState $script:MockDirect 'test-computer' $null
        $old.CompletedTargets=@('5.62.3126.2'); $old.PendingRebootTarget='5.62.3126.2'; $old.PendingRebootBootId=$script:MockBoot
        Write-Legacy $old
        $context=Get-InitialContext
        Check (-not $context.NeedsNewWorkflow) 'Do not interpret a just-finished flash as replacement.'
        Check ((Action-For $context).Type -eq 'Reboot') 'Require reboot; never offer reflashing source firmware.'
    }
    Case 'Final flash retains UEFI re-enable; next boot with enabled TPM completes normally' {
        Reset-Session
        $old=Old-Workflow; $old.PendingRebootBootId=$script:MockBoot
        Write-Legacy $old; $script:MockDirect.Version='5.67.19690.2'
        $context=Get-InitialContext
        Check ((Action-For $context).Type -eq 'EnterUefiEnable') 'Final reboot/UEFI step retained.'
        $script:MockBoot='next-boot'; $script:MockEnabled=$true
        $context=Get-InitialContext
        Check ((Action-For $context).Type -eq 'Complete') 'Final version and enabled TPM complete.'
    }
    Case 'Malformed saved JSON offers recovery without overwriting evidence' {
        Reset-Session
        New-Item -ItemType Directory -Path (Split-Path $script:LegacyWorkflowPath -Parent) -Force | Out-Null
        '{invalid JSON' | Set-Content $script:LegacyWorkflowPath
        $hash=Get-Sha256 $script:LegacyWorkflowPath
        Check (Get-InitialContext).NeedsNewWorkflow 'Unreadable record offers a fresh session.'
        Check ((Get-Sha256 $script:LegacyWorkflowPath) -eq $hash) 'Unreadable original preserved.'
    }
    Case 'Saved route tampering cannot select a different firmware file' {
        Reset-Session
        $old=New-WorkflowForState $script:MockDirect 'test-computer' $null
        $old.Path[0].FirmwareFile='substituted.BIN'; Write-Legacy $old
        $context=Get-InitialContext
        Check $context.NeedsNewWorkflow 'Invalid route rejected.'
        Check ($context.Workflow.Path[0].FirmwareFile -eq $script:Routes['5.0.1089.2'].FirmwareFile) 'Candidate uses pinned route.'
    }
    Case 'Unsupported live firmware remains blocked without replacing old progress' {
        Reset-Session; Write-Legacy (Old-Workflow)
        $hash=Get-Sha256 $script:LegacyWorkflowPath; $script:MockDirect.Version='9.9.9.9'
        [void](Expect-Blocked { Get-InitialContext } 'Unsupported TPM firmware')
        Check ((Get-Sha256 $script:LegacyWorkflowPath) -eq $hash) 'Unsupported device cannot replace old workflow.'
    }
    Case 'Live recheck prevents changed device state from starting a fresh session' {
        Reset-Session; Write-Legacy (Old-Workflow); $context=Get-InitialContext
        $hash=Get-Sha256 $script:LegacyWorkflowPath; $script:MockDirect.Version='5.62.3126.2'
        [void](Expect-Blocked { Invoke-NewWorkflowAction $context } 'firmware changed')
        Check ((Get-Sha256 $script:LegacyWorkflowPath) -eq $hash) 'Recheck failure preserves old record.'
    }
    Case 'A later replacement also archives a current workflow before replacing it' {
        Reset-Session
        $old=Old-Workflow; Save-Workflow $old
        $hash=Get-Sha256 $script:WorkflowPath
        $context=Get-InitialContext
        Check $context.NeedsNewWorkflow 'Current-version record also recognizes older replacement firmware.'
        Check (Invoke-NewWorkflowAction $context) 'Replacement accepted.'
        $archives=@(Get-ChildItem (Join-Path $script:StateDir 'Archives') -File)
        Check ($archives.Count -eq 1 -and (Get-Sha256 $archives[0].FullName) -eq $hash) 'Original current record archived before replacement.'
        Check (@((Get-Workflow).CompletedTargets).Count -eq 0) 'Current active record is fresh.'
    }

    $script:MockVolumes=@([pscustomobject]@{DriveLetter='C:'})
    $script:MockResult=[pscustomobject]@{ReturnValue=[uint32]0; ProtectionStatus=[uint32]0}
    $script:MockProviderError=$null
    $script:CimQueries=@(); $script:CimMethods=@()
    function Get-CimInstance {
        param($Namespace,$ClassName,$Filter,$ErrorAction)
        $script:CimQueries+=@([pscustomobject]@{Namespace=$Namespace;ClassName=$ClassName;Filter=$Filter})
        if($script:MockProviderError){throw $script:MockProviderError}
        return $script:MockVolumes
    }
    function Invoke-CimMethod {
        param($InputObject,$MethodName,$ErrorAction)
        $script:CimMethods+=@([pscustomobject]@{Volume=$InputObject.DriveLetter;Method=$MethodName})
        return $script:MockResult
    }
    Case 'BitLocker OFF: only the Windows drive is queried, with numeric logging' {
        Assert-BitLockerProtectionOff
        Check ($script:CimQueries.Count -eq 1 -and $script:CimQueries[0].Filter -ceq "DriveLetter='C:'") 'Single drive-scoped query; protected D: is irrelevant.'
        Check ($script:CimQueries[0].Namespace -eq 'root/CIMV2/Security/MicrosoftVolumeEncryption' -and $script:CimQueries[0].ClassName -eq 'Win32_EncryptableVolume') 'Authoritative provider.'
        Check ($script:CimMethods.Count -eq 1 -and $script:CimMethods[0].Method -eq 'GetProtectionStatus') 'Numeric method invoked once.'
        $log=Get-Content $script:RunDetailsPath -Raw
        Check ($log -match 'Drive=C: ReturnValue=0 ProtectionStatus=0' -and $log -match 'Result=Allowed') 'Precise success logged.'
    }
    foreach ($status in @(1,2,3)) {
        Case "BitLocker status $status blocks maintenance" {
            $script:MockResult=[pscustomobject]@{ReturnValue=[uint32]0;ProtectionStatus=[uint32]$status}
            $message=Expect-Blocked {Assert-BitLockerProtectionOff} 'BitLocker'
            if($status -eq 1){Check ((Get-FriendlyErrorMessage $message) -match 'must be suspended') 'ON has actionable friendly error.'}
            else{Check ((Get-FriendlyErrorMessage $message) -match 'could not safely determine') 'Unknown states have verification error.'}
        }
    }
    Case 'Nonzero BitLocker method return blocks even if status is zero' {
        $script:MockResult=[pscustomobject]@{ReturnValue=[uint32]5;ProtectionStatus=[uint32]0}
        [void](Expect-Blocked {Assert-BitLockerProtectionOff} 'return code 5')
    }
    Case 'BitLocker ON prevents the real UEFI-disable and flash action functions from continuing' {
        Reset-Session
        $context=Get-InitialContext; $action=Action-For $context
        $script:MockResult=[pscustomobject]@{ReturnValue=[uint32]0;ProtectionStatus=[uint32]1}
        [void](Expect-Blocked {Invoke-ShutdownAction -Mode UefiDisable -Workflow $context.Workflow} 'protection is ON')
        [void](Expect-Blocked {Invoke-SelectedFirmwareUpdate -Context $context -Workflow $context.Workflow -UiAction $action} 'protection is ON')
        Check ($null -eq $context.Workflow.UefiDisableRequestedUtc) 'Blocked UEFI action did not save a request.'
        Check ($null -eq $context.Workflow.PendingRebootTarget) 'Blocked flash created no success marker.'
    }
    foreach ($property in @('ReturnValue','ProtectionStatus')) {
        foreach ($badValue in @($null,$false,'0',0.5,-1,[uint64]4294967296)) {
            Case "Invalid $property value [$badValue] blocks" {
                $script:MockResult=[pscustomobject]@{ReturnValue=[uint32]0;ProtectionStatus=[uint32]0}
                $script:MockResult.$property=$badValue
                [void](Expect-Blocked {Assert-BitLockerProtectionOff} 'missing|invalid numeric')
            }
        }
        Case "Missing $property blocks" {
            $script:MockResult=[pscustomobject]@{ReturnValue=[uint32]0;ProtectionStatus=[uint32]0}
            $script:MockResult.PSObject.Properties.Remove($property)
            [void](Expect-Blocked {Assert-BitLockerProtectionOff} 'missing')
        }
    }
    Case 'Unavailable CIM provider fails closed with meaningful log and friendly error' {
        $script:MockProviderError='Access denied by provider'
        $message=Expect-Blocked {Assert-BitLockerProtectionOff} 'Access denied by provider'
        Check ((Get-FriendlyErrorMessage $message) -match 'Windows system drive') 'Provider failure uses BitLocker friendly error.'
        Check ((Get-Content $script:RunDetailsPath -Raw) -match 'Access denied by provider; Result=Blocked') 'Underlying technical reason logged.'
        $script:MockProviderError=$null
    }
    foreach ($count in @(0,2)) {
        Case "Provider returns $count volumes: block" {
            $script:MockVolumes=@(); for($i=0;$i -lt $count;$i++){$script:MockVolumes+=@([pscustomobject]@{DriveLetter='C:'})}
            [void](Expect-Blocked {Assert-BitLockerProtectionOff} 'exactly one')
        }
    }
    Case 'Provider returns a different volume: block' {
        $script:MockVolumes=@([pscustomobject]@{DriveLetter='D:'})
        [void](Expect-Blocked {Assert-BitLockerProtectionOff} 'different volume')
        $script:MockVolumes=@([pscustomobject]@{DriveLetter='C:'})
    }
    Case 'Missing method result blocks' {
        $script:MockResult=$null
        [void](Expect-Blocked {Assert-BitLockerProtectionOff} 'no single method result')
    }
    foreach($drive in @('','C:\','bogus')) {
        Case "Invalid Windows system drive [$drive] blocks" {
            $env:SystemDrive=$drive
            [void](Expect-Blocked {Assert-BitLockerProtectionOff} 'system drive')
        }
    }
    Case 'Native 0.831 output protocol is still recognized by the current wrapper' {
        $text=@'
TPMFactoryUpd Ver 02.03.4733.00
[V0.831 IDENTITY] infineon=Yes unsupportedChip=No
TPM family: 2.0
TPM firmware version: 5.0.1089.2
TPM firmware valid: Yes
TPM operation mode: Operational
TPM platformAuth: Empty Buffer
Remaining updates: 64
[V0.831 POLICY] platformPolicy=none
'@
        $state=Convert-DirectInfoToState -Text $text -InfoLog 'simulated.txt'
        Check ($state.Version -eq '5.0.1089.2' -and $state.Manufacturer -eq 'IFX' -and $state.PlatformPolicyStatus -eq 'None') 'Unchanged native protocol parsed.'
    }
    Case 'Both original BitLocker safety-gate call sites remain in place' {
        $calls=@($mainAst.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Assert-BitLockerProtectionOff'},$true))
        Check ($calls.Count -eq 2) 'Exactly two existing safety gates.'
        Check ($definitions['Invoke-ShutdownAction'] -match "if \(\`$Mode -eq 'UefiDisable'\)\s*\{\s*Assert-BitLockerProtectionOff") 'Gate precedes UEFI-disable action.'
        Check ($definitions['Invoke-SelectedFirmwareUpdate'] -match 'Assert-BitLockerProtectionOff\s+\$live = Get-IfxTpmState') 'Gate precedes pre-flash probe and flash.'
    }
    # Restart tests replace Start-Process with a recorder, never a real process.
    $env:SystemDrive='C:'
    $script:MockResult=[pscustomobject]@{ReturnValue=[uint32]0;ProtectionStatus=[uint32]0}
    $script:RestartRequests=@()
    $script:CapturedConfirmation=@()
    $script:MockRestartExit=0
    function Confirm-Action {
        param($Lines)
        $script:CapturedConfirmation=@($Lines)
        return $script:MockConfirm
    }
    function Start-Process {
        param($FilePath,$ArgumentList,[switch]$PassThru,[switch]$Wait)
        Check ($script:CapturedConfirmation.Count -gt 0) 'Confirmation was displayed before requesting a restart.'
        $script:RestartRequests+=@([pscustomobject]@{File=$FilePath;Arguments=@($ArgumentList);Wait=[bool]$Wait;PassThru=[bool]$PassThru})
        return [pscustomobject]@{ExitCode=$script:MockRestartExit}
    }
    foreach($mode in @('UefiDisable','UefiEnable','Reboot')) {
        Case "$mode uses a confirmed ordinary restart, without firmware-setup or force flags" {
            Reset-Session; $context=Get-InitialContext
            $script:RestartRequests=@(); $script:CapturedConfirmation=@()
            Check (Invoke-ShutdownAction -Mode $mode -Workflow $context.Workflow) 'Accepted restart action returns success.'
            Check ($script:RestartRequests.Count -eq 1) 'Exactly one restart requested.'
            $request=$script:RestartRequests[0]
            Check (($request.Arguments -join ' ') -ceq '/r /t 0') 'Plain restart only; no /fw or /f.'
            Check ($request.File -match 'System32[\\/]shutdown\.exe$' -and $request.Wait -and $request.PassThru) 'Windows shutdown command uses checked process exit.'
            $warning=$script:CapturedConfirmation -join ' '
            Check ($warning -match 'Save all unsaved documents' -and $warning -match 'restart normally') 'Save-work warning and normal-restart explanation shown.'
            if($mode -ne 'Reboot') {
                Check ($warning -match 'Enter BIOS/UEFI manually' -and $warning -match 'Delete or F2') 'Manual setup-key instruction shown before restart.'
                $saved=Get-Workflow
                if($mode -eq 'UefiDisable') {
                    Check ($warning -cmatch 'Disable Trusted Computing' -and [bool]$saved.UefiDisableRequestedUtc) 'Correct disable instruction and requested-step timestamp.'
                } else {
                    Check ($warning -cmatch 'Enable Trusted Computing' -and [bool]$saved.UefiEnableRequestedUtc) 'Correct enable instruction and requested-step timestamp.'
                }
            }
        }
        Case "$mode cancellation neither restarts nor changes saved workflow" {
            Reset-Session; $context=Get-InitialContext
            $hash=Get-Sha256 $script:WorkflowPath
            $script:RestartRequests=@(); $script:MockConfirm=$false
            Check (-not (Invoke-ShutdownAction -Mode $mode -Workflow $context.Workflow)) 'Declined action returns false.'
            Check ($script:RestartRequests.Count -eq 0) 'No restart after cancellation.'
            Check ((Get-Sha256 $script:WorkflowPath) -eq $hash) 'No workflow changes after cancellation.'
        }
        Case "$mode restart failure is logged and never marks an update or reboot complete" {
            Reset-Session; $context=Get-InitialContext
            $script:RestartRequests=@(); $script:MockRestartExit=5
            $message=Expect-Blocked {Invoke-ShutdownAction -Mode $mode -Workflow $context.Workflow} 'requested reboot'
            Check ((Get-FriendlyErrorMessage $message) -match 'restart the computer manually') 'Failure describes ordinary restart and manual recovery.'
            Check ((Get-Content $script:RunDetailsPath -Raw) -match 'shutdown.exe exit code: 5') 'Native exit code logged.'
            $saved=Get-Workflow
            Check (@($saved.CompletedTargets).Count -eq 0 -and @($saved.RebootedAfterTargets).Count -eq 0) 'No fabricated completion checkmarks.'
            $script:MockRestartExit=0
        }
    }
    Case 'BitLocker ON still blocks the disable-TPM restart before any restart request' {
        Reset-Session; $context=Get-InitialContext; $script:RestartRequests=@()
        $script:MockResult=[pscustomobject]@{ReturnValue=[uint32]0;ProtectionStatus=[uint32]1}
        [void](Expect-Blocked {Invoke-ShutdownAction -Mode UefiDisable -Workflow $context.Workflow} 'protection is ON')
        Check ($script:RestartRequests.Count -eq 0) 'BitLocker gate still prevents the restart.'
        $script:MockResult=[pscustomobject]@{ReturnValue=[uint32]0;ProtectionStatus=[uint32]0}
    }
    Case 'Upgrading from 0.85 preserves an actual same-boot pending intermediate reboot' {
        Reset-Session
        $old=New-WorkflowForState $script:MockDirect 'test-computer' $null
        $old.PackageBuildId='IFX-TPM-UPDATER-V0.85-PORTABLE-20261004'
        $old.CompletedTargets=@('5.62.3126.2'); $old.PendingRebootTarget='5.62.3126.2'; $old.PendingRebootBootId=$script:MockBoot
        Save-Workflow $old; $script:MockDirect.Version='5.62.3126.2'
        $context=Get-InitialContext
        Check (-not $context.NeedsNewWorkflow) '0.85 session resumes instead of being discarded.'
        Check ((Action-For $context).Type -eq 'Reboot') 'Mandatory reboot remains required after upgrade.'
        Check ($context.Workflow.PackageBuildId -eq $script:BuildId) 'Saved workflow migrated to current build identity.'
    }
    Case 'Requested BIOS restart does not imply Trusted Computing was actually enabled' {
        Reset-Session -Version '5.67.19690.2'
        $context=Get-InitialContext
        Check ((Action-For $context).Type -eq 'EnterUefiEnable') 'Final firmware with disabled TPM still needs BIOS enable.'
        Check (Invoke-ShutdownAction -Mode UefiEnable -Workflow $context.Workflow) 'Normal restart requested.'
        $script:MockBoot='next-boot'; $context=Get-InitialContext
        Check ((Action-For $context).Type -eq 'EnterUefiEnable') 'Reboot alone never implies the BIOS setting changed.'
        $script:MockEnabled=$true; $context=Get-InitialContext
        Check ((Action-For $context).Type -eq 'Complete') 'Live enabled status confirms completion.'
    }
    Write-Host "PASS: $script:Cases regression cases; $script:Checks assertions. No hardware operations performed." -ForegroundColor Green
}
finally {
    $env:ProgramData=$originalProgramData
    $env:SystemDrive=$originalSystemDrive
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
