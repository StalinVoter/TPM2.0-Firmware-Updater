#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'UpdaterCommon.ps1')

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ([string]$Actual -ne [string]$Expected) {
        throw "$Label failed. Expected '$Expected'; found '$Actual'."
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Label)
    $thrown = $false
    try { & $Action } catch { $thrown = $true }
    if (-not $thrown) { throw "$Label failed: an exception was required." }
}

function Get-ThrownMessage {
    param([scriptblock]$Action, [string]$Label)
    try { & $Action } catch { return $_.Exception.Message }
    throw "$Label failed: an exception was required."
}

function New-TestState {
    param(
        [string]$Auth = 'Empty Buffer',
        [string]$PolicyStatus = 'Unavailable',
        [string]$PolicyAlg = $null,
        [string]$PolicyDigest = $null,
        [string]$PolicyTpmRc = $null
    )
    return [pscustomobject]@{
        Manufacturer = 'IFX'
        UnsupportedChip = 'No'
        Family = '2.0'
        Version = '5.62.3126.2'
        FirmwareValid = 'Yes'
        OperationMode = 'Operational'
        PlatformAuth = $Auth
        RemainingUpdates = 63
        PlatformPolicyStatus = $PolicyStatus
        PlatformPolicyAlg = $PolicyAlg
        PlatformPolicyDigest = $PolicyDigest
        PlatformPolicyTpmRc = $PolicyTpmRc
    }
}

Assert-Equal (Convert-TvicImagePathToFileSystemPath '\??\F:\old\dist\TVicPort.sys') `
    'F:\old\dist\TVicPort.sys' 'NT driver-path conversion'
Assert-Equal (Convert-TvicImagePathToFileSystemPath '\\?\F:\old\dist\TVicPort.sys') `
    'F:\old\dist\TVicPort.sys' 'Win32 extended driver-path conversion'

Assert-Equal (Test-FlashConfirmation 'FLASH') $true 'uppercase FLASH confirmation'
Assert-Equal (Test-FlashConfirmation 'flash') $true 'lowercase flash confirmation'
Assert-Equal (Test-FlashConfirmation '  FlAsH  ') $true 'trimmed mixed-case FLASH confirmation'
Assert-Equal (Test-FlashConfirmation '') $false 'empty confirmation cancellation'
Assert-Equal (Test-FlashConfirmation 'yes') $false 'non-FLASH confirmation cancellation'

$expectedRoutes = [ordered]@{
    '5.0.1089.2'   = '5.62.3126.2'
    '5.51.2098.0'  = '5.63.3144.0'
    '5.51.2098.2'  = '5.62.3126.2'
    '5.60.2677.0'  = '5.63.3144.0'
    '5.61.2785.0'  = '5.63.3144.0'
    '5.61.2789.0'  = '5.63.3144.0'
    '5.62.3126.0'  = '5.63.3144.0'
    '5.62.3126.2'  = '5.67.19690.2'
    '5.63.3144.0'  = '5.67.19690.2'
    '5.63.3353.0'  = '5.67.19690.2'
    '5.63.3353.2'  = '5.67.19690.2'
    '5.66.19374.2' = '5.67.19690.2'
}
Assert-Equal $script:Routes.Count 12 'complete firmware-route count'
foreach ($entry in $expectedRoutes.GetEnumerator()) {
    $route = Get-RouteForVersion ([string]$entry.Key)
    Assert-Equal $route.SourceVersion ([string]$entry.Key) "route source $($entry.Key)"
    Assert-Equal $route.TargetVersion ([string]$entry.Value) "route target $($entry.Key)"
    Assert-Equal $route.FirmwareFile ("TPM20_{0}_to_TPM20_{1}.BIN" -f $entry.Key,$entry.Value) `
        "route filename $($entry.Key)"
    $firmware = Assert-FirmwareForRoute $route
    Assert-Equal $firmware.Sha256 $route.FirmwareSha256 "route hash $($entry.Key)"
}
Assert-Equal (Get-RouteForVersion '5.67.19690.2') $null 'final target has no update route'
Assert-Throws { Get-RouteForVersion '5.63.3144.1' } 'unsupported source rejection'

$twoHopChain = @(Get-FirmwareUpgradeChain -Version '5.0.1089.2')
Assert-Equal $twoHopChain.Count 2 'two-hop workflow route count'
Assert-Equal $twoHopChain[0].TargetVersion '5.62.3126.2' 'two-hop intermediate target'
Assert-Equal $twoHopChain[1].TargetVersion '5.67.19690.2' 'two-hop final target'
Assert-Equal (@(Get-FirmwareUpgradeChain -Version '5.63.3144.0').Count) 1 `
    'single-hop workflow route count'
Assert-Equal (@(Get-FirmwareUpgradeChain -Version '5.67.19690.2').Count) 0 `
    'completed workflow route count'

# Windows PowerShell 5.1 throws "Argument types do not match" when @() is
# applied directly to certain generic List[T] values. The route tests above
# execute the real function; these checks prevent that incompatible return
# form from being reintroduced into any V0.831 list-producing workflow path.
$packageRootForCompatibility = Split-Path -Parent $PSScriptRoot
$commonSourceForCompatibility = Get-Content -LiteralPath (Join-Path $packageRootForCompatibility 'UpdaterCommon.ps1') -Raw
$uiSourceForCompatibility = Get-Content -LiteralPath (Join-Path $packageRootForCompatibility 'TPM-Updater.ps1') -Raw
Assert-Equal $commonSourceForCompatibility.Contains('return @($chain)') $false `
    'PowerShell 5.1-safe route-array return'
Assert-Equal $uiSourceForCompatibility.Contains('return @($versions)') $false `
    'PowerShell 5.1-safe workflow-version return'
Assert-Equal $uiSourceForCompatibility.Contains('$Workflow.CompletedTargets = @($verifiedTargets)') $false `
    'PowerShell 5.1-safe completed-target assignment'
Assert-Equal $uiSourceForCompatibility.Contains('return @($rows)') $false `
    'PowerShell 5.1-safe checklist-row return'

$trustedDirect = New-TestState -Auth 'Not Empty Buffer'
$hiddenDirect = New-TestState -Auth 'Empty Buffer'
$windowsEnabled = [pscustomobject]@{ QuerySucceeded=$true; TpmPresent=$true; TpmEnabled=$true; TpmActivated=$true }
$windowsDisabled = [pscustomobject]@{ QuerySucceeded=$true; TpmPresent=$false; TpmEnabled=$false; TpmActivated=$false }
$windowsUnavailable = [pscustomobject]@{ QuerySucceeded=$false }
Assert-Equal (Get-TrustedComputingStatus -DirectState $trustedDirect -WindowsStatus $windowsEnabled) `
    'Enabled' 'Windows-exposed TPM state'
Assert-Equal (Get-TrustedComputingStatus -DirectState $hiddenDirect -WindowsStatus $windowsDisabled) `
    'Disabled' 'Windows-hidden direct TPM state'
Assert-Equal (Get-TrustedComputingStatus -DirectState $hiddenDirect -WindowsStatus $windowsUnavailable) `
    'Disabled' 'bounded Windows-query fallback state'

# Real TPMFactoryUpd progress output redraws one console line with bare CR
# characters. The result classifier must still see 100 percent while retaining
# every independent fail-closed success check.
$successfulFlashStdOut = (
    "       New firmware valid for TPM        :    Yes`r`n" +
    "       TPM firmware version after update :    5.62.3126.2`r`n" +
    "       Completion: 0 %`r       Completion: 99 %`r       Completion: 100 %`r`r`n" +
    "       TPM Firmware Update completed successfully.`r`n"
)
Assert-Equal (Test-FirmwareFlashSucceeded -StdOut $successfulFlashStdOut -InternalLog '' `
    -ExitCode 0 -TargetVersion '5.62.3126.2') $true 'CR-delimited successful-flash parser'
Assert-Equal (Test-FirmwareFlashSucceeded -StdOut $successfulFlashStdOut -InternalLog '' `
    -ExitCode 0 -TargetVersion '5.67.19690.2') $false 'successful-flash target-version gate'
Assert-Equal (Test-FirmwareFlashSucceeded `
    -StdOut ($successfulFlashStdOut + "Error Code: 0xDEADBEEF`r`n") -InternalLog '' `
    -ExitCode 0 -TargetVersion '5.62.3126.2') $false 'successful-flash stdout-error gate'
Assert-Equal (Test-FirmwareFlashSucceeded -StdOut $successfulFlashStdOut `
    -InternalLog "Error detected:`r`n" -ExitCode 0 -TargetVersion '5.62.3126.2') $false `
    'successful-flash internal-error gate'
Assert-Equal (Test-FirmwareFlashSucceeded -StdOut $successfulFlashStdOut -InternalLog '' `
    -ExitCode 1 -TargetVersion '5.62.3126.2') $false 'successful-flash exit-code gate'

$successfulSecondHopStdOut = (
    "       New firmware valid for TPM        :    Yes`r`n" +
    "       TPM firmware version after update :    5.67.19690.2`r`n" +
    "       Completion: 0 %`r       Completion: 99 %`r       Completion: 100 %`r`r`n" +
    "       TPM Firmware Update completed successfully.`r`n"
)
Assert-Equal (Test-FirmwareFlashSucceeded -StdOut $successfulSecondHopStdOut -InternalLog '' `
    -ExitCode 0 -TargetVersion '5.67.19690.2') $true `
    'CR-delimited successful second-hop parser'

Assert-Equal (Get-LatestInfineonCompletionPercentage -Text '') $null `
    'no invented progress before Infineon reports a percentage'
Assert-Equal (Get-LatestInfineonCompletionPercentage `
    -Text "Completion: 0 %`rCompletion: 41 %`rCompletion: 73 %`r") 73 `
    'latest CR-delimited Infineon progress value'
Assert-Equal (Get-LatestInfineonCompletionPercentage `
    -Text "Completion: 99 %`rCompletion: 100 %`r") 100 `
    'final Infineon progress value'
Assert-Equal (Format-TpmFlashProgressBar -Percent 0 -Width 10) `
    'TPM firmware update [----------]   0%' 'zero-percent progress bar'
Assert-Equal (Format-TpmFlashProgressBar -Percent 50 -Width 10) `
    'TPM firmware update [#####-----]  50%' 'half-complete progress bar'
Assert-Equal (Format-TpmFlashProgressBar -Percent 100 -Width 10) `
    'TPM firmware update [##########] 100%' 'complete progress bar'

# Exercise the nonblocking process-exit watcher against a real child process.
# The fixture emits the same bare-CR progress format as TPMFactoryUpd and exits
# immediately after 100 percent. The watcher must return with exit 0 and retain
# the final native percentage without calling WaitForExit.
$watchStdOut = Join-Path ([IO.Path]::GetTempPath()) ("ifx-v083-progress-{0}.stdout" -f [Guid]::NewGuid().ToString('N'))
$watchStdErr = "$watchStdOut.stderr"
try {
    $watchScript = '[Console]::Out.Write("Completion: 0 %`rCompletion: 50 %`rCompletion: 100 %`r"); exit 0'
    $watchEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($watchScript))
    $watchProcess = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList @('-NoLogo','-NoProfile','-EncodedCommand',$watchEncoded) `
        -PassThru -NoNewWindow -RedirectStandardOutput $watchStdOut -RedirectStandardError $watchStdErr
    $watchResult = Wait-FlashProcessWithProgress -Process $watchProcess -StdOutPath $watchStdOut -Quiet
    Assert-Equal $watchResult.ExitCode 0 'nonblocking process watcher exit code'
    Assert-Equal $watchResult.LastReportedPercent 100 'nonblocking process watcher final progress'
}
finally {
    Remove-Item -LiteralPath $watchStdOut,$watchStdErr -Force -ErrorAction SilentlyContinue
}

$flashFunctionText = (Get-Command Invoke-FirmwareFlash).ScriptBlock.ToString()
Assert-Equal ($flashFunctionText -match '\.WaitForExit\s*\(') $false `
    'firmware flash must not use blocking WaitForExit'
Assert-Equal ($flashFunctionText -match 'Wait-FlashProcessWithProgress') $true `
    'firmware flash must use live progress watcher'

$sample = @"
TPMFactoryUpd Ver 02.03.4733.00
       TPM family                        :    2.0
       TPM firmware version              :    5.62.3126.2
       TPM firmware valid                :    Yes
       TPM operation mode                :    Operational
       TPM platformAuth                  :    Not Empty Buffer
       Remaining updates                 :    63
[V0.831 IDENTITY] infineon=Yes unsupportedChip=No
[V0.831 POLICY] platformPolicy handle=0x4000000C alg=0x000B digest=652351CB9FE7D86EB244A95E5AD4DDB79C1138C0BFE15B1664F69F5E74C94539
"@
$parsed = Convert-DirectInfoToState -Text $sample -InfoLog '<synthetic>'
Assert-Equal $parsed.OperationMode 'Operational' 'live-info operation parser'
Assert-Equal $parsed.PlatformPolicyStatus 'Reported' 'live-info policy parser'

$converterText = (Get-Command Convert-DirectInfoToState).ScriptBlock.ToString()
Assert-Equal $converterText.Contains('V0\.831') $true `
    'direct-info parser must require the current escaped helper tag'
Assert-Equal $converterText.Contains('V9\.7') $false `
    'direct-info parser must not retain the stale V9.7 escaped helper tag'

$helperInfoSourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) `
    'Source\TPMFactoryUpd\CommandFlow_TpmInfo.c'
$helperInfoSource = Get-Content -LiteralPath $helperInfoSourcePath -Raw
Assert-Equal $helperInfoSource.Contains('[V0.831 IDENTITY]') $true `
    'helper source must emit the current identity tag'
Assert-Equal $helperInfoSource.Contains('[V0.831 POLICY]') $true `
    'helper source must emit the current policy tag'
Assert-Equal $helperInfoSource.Contains('[V9.7 ') $false `
    'helper source must not emit stale V9.7 tags'

$packageRoot = Split-Path -Parent $PSScriptRoot
$launcherSource = Get-Content -LiteralPath (Join-Path $packageRoot 'Source\Launcher\TPM-Updater-Launcher.c') -Raw
Assert-Equal $launcherSource.Contains('CreateProcessW') $true 'native console launcher process creation'
Assert-Equal $launcherSource.Contains('TPM-Updater.ps1') $true 'native console launcher runtime target'
$buildSource = Get-Content -LiteralPath (Join-Path $packageRoot 'Build-Windows11-x64.ps1') -Raw
Assert-Equal $buildSource.Contains('/MANIFESTUAC:"level=''requireAdministrator'' uiAccess=''false''"') $true `
    'native launcher embedded elevation manifest'
Assert-Equal $buildSource.Contains('TPM-Updater.embedded.manifest') $true `
    'post-link launcher manifest extraction'
Assert-Equal $buildSource.Contains('function Install-BuildToolsWithWinGet') $false `
    'fresh Build Tools provisioning must not route installer arguments through WinGet'
Assert-Equal $buildSource.Contains('[string]$winget = [string](Ensure-WinGet)') $false `
    'the build entry point must not require WinGet before Build Tools provisioning'
Assert-Equal $buildSource.Contains('$bootstrap = Get-MicrosoftBuildToolsBootstrapper') $true `
    'fresh Build Tools provisioning must use the verified Microsoft bootstrapper directly'
$installBranchPattern = '(?s)else\s*\{.*?Visual Studio/Build Tools is not installed.*?\$rebootRequired\s*=\s*Install-BuildTools\s*'
Assert-Equal ([regex]::IsMatch($buildSource, $installBranchPattern)) $true `
    'fresh Build Tools install must propagate the reboot-required result'
$interfaceSource = Get-Content -LiteralPath (Join-Path $packageRoot 'TPM-Updater.ps1') -Raw
Assert-Equal $interfaceSource.Contains('The computer will reboot and enter UEFI settings.') $true `
    'UEFI reboot notification'
Assert-Equal $interfaceSource.Contains("@('/r','/fw','/t','0')") $true `
    'Windows firmware-settings reboot action'
Assert-Equal $interfaceSource.Contains('Firmware update completed successfully.') $true `
    'deterministic completion banner'

$staleV93Sample = $sample -replace '\[V0\.831 ', '[V9.3 '
Assert-Throws { Convert-DirectInfoToState -Text $staleV93Sample -InfoLog '<synthetic-stale-v9.3>' } `
    'stale V9.3 helper-tag rejection'

$legacySample = @"
TPMFactoryUpd Ver 02.03.4733.00
       TPM family                        :    2.0
       TPM firmware version              :    5.0.1089.2
       TPM firmware valid                :    Yes
       TPM operation mode                :    Operational
       TPM platformAuth                  :    Not Empty Buffer
       Remaining updates                 :    64
[V0.831 IDENTITY] infineon=Yes unsupportedChip=No
[V0.831 POLICY] platformPolicy=unsupported-capability tpmRc=0x000001C4
"@
$legacyParsed = Convert-DirectInfoToState -Text $legacySample -InfoLog '<synthetic>'
Assert-Equal $legacyParsed.PlatformPolicyStatus 'Unsupported capability' 'legacy policy capability parser'
Assert-Equal $legacyParsed.PlatformPolicyTpmRc '0x000001C4' 'legacy policy TPM return-code parser'

$empty = Resolve-AuthorizationMode -State (New-TestState) -PolicyFile $null
Assert-Equal $empty.Mode 'tpm20-emptyplatformauth' 'empty-platformAuth routing'

$default = Resolve-AuthorizationMode -State (New-TestState `
    -Auth 'Not Empty Buffer' -PolicyStatus 'Reported' -PolicyAlg '0x000B' `
    -PolicyDigest $script:DefaultPlatformPolicySha256) -PolicyFile $null
Assert-Equal $default.Mode 'tpm20-platformpolicy' 'default-platform-policy routing'

$legacyGateMessage = Get-ThrownMessage { Resolve-AuthorizationMode -State (New-TestState `
    -Auth 'Not Empty Buffer' -PolicyStatus 'Unsupported capability' `
    -PolicyTpmRc '0x000001C4') -PolicyFile $null } 'legacy unqueryable-policy message'
$expectedLegacyGateMessage = @(
    'TPM firmware updating is blocked while TPM 2.0 / Security Device Support is enabled in BIOS/UEFI.'
    ''
    'Restart into BIOS/UEFI, disable TPM 2.0 / Security Device Support, boot back into Windows, and run this updater again.'
) -join [Environment]::NewLine
Assert-Equal $legacyGateMessage $expectedLegacyGateMessage 'concise BIOS instruction'
Assert-Equal ($legacyGateMessage -match '(?i)V9\.|platformAuth|authPolicy|TPM_CAP_|TPM_RC_|PolicyFile') `
    $false 'BIOS instruction must not expose internal or historical diagnostics'

Assert-Throws { Resolve-AuthorizationMode -State (New-TestState -Auth 'Platform hierarchy disabled') -PolicyFile $null } 'disabled hierarchy gate'
Assert-Throws { Resolve-AuthorizationMode -State (New-TestState -Auth 'Unknown') -PolicyFile $null } 'unknown authorization gate'
Assert-Throws { Resolve-AuthorizationMode -State (New-TestState `
    -Auth 'Not Empty Buffer' -PolicyStatus 'Reported' -PolicyAlg '0x000B' `
    -PolicyDigest ('22' * 32)) -PolicyFile $null } 'unproven policy gate'

$policyPath = Join-Path ([IO.Path]::GetTempPath()) ("ifx-v083-policy-test-{0}.cfg" -f [Guid]::NewGuid().ToString('N'))
try {
    @(
        '[POLICYOR_TPMFWUPDATE]'
        "PolicyDigest1=$script:DefaultPlatformPolicySha256"
        ('PolicyDigest2=' + ('11' * 32))
    ) | Set-Content -LiteralPath $policyPath -Encoding ASCII

    $policyState = New-TestState `
        -Auth 'Not Empty Buffer' -PolicyStatus 'Reported' -PolicyAlg '0x000B' `
        -PolicyDigest '47d0846615a81bed00ed8d17656b97566031cbb006d4b143341bf86a7ec40180'
    $oem = Resolve-AuthorizationMode -State $policyState -PolicyFile $policyPath
    Assert-Equal $oem.PolicyOrDigest $policyState.PlatformPolicyDigest 'PolicyOR digest calculation'

    $legacyPolicyState = New-TestState `
        -Auth 'Not Empty Buffer' -PolicyStatus 'Unsupported capability' `
        -PolicyTpmRc '0x000001C4'
    Assert-Throws { Resolve-AuthorizationMode -State $legacyPolicyState -PolicyFile $policyPath } `
        'legacy PolicyFile cannot bypass unavailable authPolicy'

    $policyState.PlatformPolicyDigest = ('33' * 32)
    Assert-Throws { Resolve-AuthorizationMode -State $policyState -PolicyFile $policyPath } 'PolicyOR mismatch gate'
}
finally {
    Remove-Item -LiteralPath $policyPath -Force -ErrorAction SilentlyContinue
}

$authUnavailableInternal = @"
Sending TPM Command: TPM2_FieldUpgradeStartVendor
DeviceManagement_Transmit: Received:  RxLen =   10
0000: 80 01 00 00 00 0A 00 00  01 2F
Message: TSS_TPM2_FieldUpgradeStartVendor returned an unexpected value.(0xE028012F)
"@
$authUnavailableSummary = Get-FlashFailureSummary -StdOut 'Error Code: 0xE029550A' `
    -InternalLog $authUnavailableInternal -ExitCode 0
Assert-Equal $authUnavailableSummary `
    'TPM_RC_AUTH_UNAVAILABLE (0x0000012F) - the platform hierarchy has no usable authPolicy for this policy session, so TPM2_FieldUpgradeStartVendor was rejected.' `
    'exact authorization-failure decoding'

Assert-Equal ($authUnavailableInternal -match '(?im)^\[[^]]+\]\s+Sending TPM Command:\s*TPM_FieldUpgrade\s*$') `
    $false 'payload-transfer evidence must not match FieldUpgradeStartVendor'
Assert-Equal ("[17:00:00.000] Sending TPM Command: TPM_FieldUpgrade" -match `
    '(?im)^\[[^]]+\]\s+Sending TPM Command:\s*TPM_FieldUpgrade\s*$') `
    $true 'payload-transfer evidence parser'

Write-Host 'V0.831 routing, authorization, TPM-state, console-app, UEFI-action, live-progress, process-exit, and flash-result tests passed.' -ForegroundColor Green
