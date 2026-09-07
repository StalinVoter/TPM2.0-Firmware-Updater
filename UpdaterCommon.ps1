#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PackageVersion = 'Complete Windows 11 Updater Package V0.8 PORTABLE'
$script:BuildId = 'IFX-TPM-UPDATER-V0.8-PORTABLE-20260907'
$script:ToolVersion = '02.03.4733.00'
$script:PackageRoot = $PSScriptRoot
$script:PortableExeCandidate = Join-Path $script:PackageRoot 'TPMFactoryUpd-Direct-Win11-x64.exe'
$script:PortableMarkerCandidate = Join-Path $script:PackageRoot 'PORTABLE-RUNTIME.txt'
$script:PortableBuildInfoCandidate = Join-Path $script:PackageRoot 'BUILD-INFO.txt'
$script:IsPortableRuntime = (
    (Test-Path -LiteralPath $script:PortableMarkerCandidate -PathType Leaf) -or
    (Test-Path -LiteralPath $script:PortableExeCandidate -PathType Leaf) -or
    (Test-Path -LiteralPath $script:PortableBuildInfoCandidate -PathType Leaf)
)
if ($script:IsPortableRuntime) {
    # A built dist folder is deliberately flat and location/name independent.
    $script:ExePath = $script:PortableExeCandidate
    $script:DriverPath = Join-Path $script:PackageRoot 'TVicPort.sys'
    $script:BundledDriverPath = $script:DriverPath
    $script:FirmwareDir = $script:PackageRoot
    $script:BuildInfoPath = Join-Path $script:PackageRoot 'BUILD-INFO.txt'
    $script:PortableManifestPath = Join-Path $script:PackageRoot 'SHA256SUMS.txt'
} else {
    # Source-package layout, used for the one-time build and local execution.
    $script:ExePath = Join-Path $script:PackageRoot 'dist\TPMFactoryUpd-Direct-Win11-x64.exe'
    $script:DriverPath = Join-Path $script:PackageRoot 'dist\TVicPort.sys'
    $script:BundledDriverPath = Join-Path $script:PackageRoot 'Driver\TVicPort.sys'
    $script:FirmwareDir = Join-Path $script:PackageRoot 'Firmware'
    $script:BuildInfoPath = Join-Path $script:PackageRoot 'dist\BUILD-INFO.txt'
    $script:PortableManifestPath = $null
}
$script:LogDir = Join-Path $script:PackageRoot 'logs'
$script:StateDir = Join-Path $env:ProgramData 'IFX-TPM-Updater-V0.8'
$script:PlanPath = Join-Path $script:StateDir 'LastPlan.json'
$script:SuccessPath = Join-Path $script:StateDir 'LastSuccessfulFlash.json'
$script:WorkflowPath = Join-Path $script:StateDir 'Workflow.json'
$script:ExpectedTvicSysSha256 = '9c9ab56c8bcf5ec958e7c2346f23a3027f69abdf8af923b591518eee64ad98ad'
$script:TvicServiceName = 'TVICPORT'

# SHA-256( zeroDigest || TPM_CC_PolicyCommandCode || TPM2_CC_FieldUpgradeStartVendor )
# using TPM wire byte order.  This is Infineon's default tpm20-platformpolicy
# path when no -policyfile/-policyhandle is supplied.
$script:DefaultPlatformPolicySha256 = '652351cb9fe7d86eb244a95e5ad4ddb79c1138c0bfe15b1664f69f5e74c94539'
$script:BiosTpmSettingBlockedMessage = @(
    'TPM firmware updating is blocked while TPM 2.0 / Security Device Support is enabled in BIOS/UEFI.'
    ''
    'Restart into BIOS/UEFI, disable TPM 2.0 / Security Device Support, boot back into Windows, and run this updater again.'
) -join [Environment]::NewLine

$script:Routes = @{
    '5.0.1089.2' = [ordered]@{
        SourceVersion = '5.0.1089.2'
        TargetVersion = '5.62.3126.2'
        FirmwareFile = 'TPM20_5.0.1089.2_to_TPM20_5.62.3126.2.BIN'
        FirmwareSha256 = 'c5a51a6a3b866ead2a9266f89b150b2f60eccb113487582592a293698ba26015'
        Hop = 1
    }
    '5.51.2098.0' = [ordered]@{
        SourceVersion = '5.51.2098.0'
        TargetVersion = '5.63.3144.0'
        FirmwareFile = 'TPM20_5.51.2098.0_to_TPM20_5.63.3144.0.BIN'
        FirmwareSha256 = '49001f5f6f72ea526ad935efb86d2e5dbc9563ca14cd2c00ce7a0e724700b811'
        Hop = 1
    }
    '5.51.2098.2' = [ordered]@{
        SourceVersion = '5.51.2098.2'
        TargetVersion = '5.62.3126.2'
        FirmwareFile = 'TPM20_5.51.2098.2_to_TPM20_5.62.3126.2.BIN'
        FirmwareSha256 = '711966e03348984d1be51f8e4fe363354de12024752e25685e2660185e8c01d3'
        Hop = 1
    }
    '5.60.2677.0' = [ordered]@{
        SourceVersion = '5.60.2677.0'
        TargetVersion = '5.63.3144.0'
        FirmwareFile = 'TPM20_5.60.2677.0_to_TPM20_5.63.3144.0.BIN'
        FirmwareSha256 = '053ebbdfb280493cf7fc6a6b83bc9e7828a49c218024e4bad07f0a1f64e83c93'
        Hop = 1
    }
    '5.61.2785.0' = [ordered]@{
        SourceVersion = '5.61.2785.0'
        TargetVersion = '5.63.3144.0'
        FirmwareFile = 'TPM20_5.61.2785.0_to_TPM20_5.63.3144.0.BIN'
        FirmwareSha256 = 'a6873ad6fdbd5f624ae87e8dc0e495bbfb596d643f8d2baed7f05f90f8332346'
        Hop = 1
    }
    '5.61.2789.0' = [ordered]@{
        SourceVersion = '5.61.2789.0'
        TargetVersion = '5.63.3144.0'
        FirmwareFile = 'TPM20_5.61.2789.0_to_TPM20_5.63.3144.0.BIN'
        FirmwareSha256 = '5639101462acdde000f77fd3d0d6c1e30115e09eb8ea280267dcd3b3f02ddf50'
        Hop = 1
    }
    '5.62.3126.0' = [ordered]@{
        SourceVersion = '5.62.3126.0'
        TargetVersion = '5.63.3144.0'
        FirmwareFile = 'TPM20_5.62.3126.0_to_TPM20_5.63.3144.0.BIN'
        FirmwareSha256 = '1bf7bb31c7fb01c749194bfb82dd17c767ab69f7cf499bee7dab5e4060b23928'
        Hop = 1
    }
    '5.62.3126.2' = [ordered]@{
        SourceVersion = '5.62.3126.2'
        TargetVersion = '5.67.19690.2'
        FirmwareFile = 'TPM20_5.62.3126.2_to_TPM20_5.67.19690.2.BIN'
        FirmwareSha256 = 'e26b363af055141136723b41c6546b8c7eb18cc685ffc4aa89a38552409420e8'
        Hop = 2
    }
    '5.63.3144.0' = [ordered]@{
        SourceVersion = '5.63.3144.0'
        TargetVersion = '5.67.19690.2'
        FirmwareFile = 'TPM20_5.63.3144.0_to_TPM20_5.67.19690.2.BIN'
        FirmwareSha256 = '543bee0e0076f94eb0c7a8ef43f57d6079c583cc2d6e422ea1a7ced31e8a7627'
        Hop = 2
    }
    '5.63.3353.0' = [ordered]@{
        SourceVersion = '5.63.3353.0'
        TargetVersion = '5.67.19690.2'
        FirmwareFile = 'TPM20_5.63.3353.0_to_TPM20_5.67.19690.2.BIN'
        FirmwareSha256 = '8dab1c5374d60ae3448e7148d768f41fae6182d1f65cfe3e62448fb770df22e5'
        Hop = 2
    }
    '5.63.3353.2' = [ordered]@{
        SourceVersion = '5.63.3353.2'
        TargetVersion = '5.67.19690.2'
        FirmwareFile = 'TPM20_5.63.3353.2_to_TPM20_5.67.19690.2.BIN'
        FirmwareSha256 = '50720cb5c868184073aecedf67d0c9ca7fa8b6186c6bfb193b8fde7e879dd831'
        Hop = 2
    }
    '5.66.19374.2' = [ordered]@{
        SourceVersion = '5.66.19374.2'
        TargetVersion = '5.67.19690.2'
        FirmwareFile = 'TPM20_5.66.19374.2_to_TPM20_5.67.19690.2.BIN'
        FirmwareSha256 = '44a39593eaaa9a2734f5b6e87e8c1267c3a641f0298e95e83c3485a5277320e0'
        Hop = 2
    }
}

function Write-Title {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('-' * $Text.Length) -ForegroundColor DarkCyan
}

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-FlashConfirmation {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return $false }
    return ($Text.Trim() -ieq 'FLASH')
}

function Assert-Administrator {
    if (-not (Test-Administrator)) { throw 'Administrator rights are required.' }
    if (-not [Environment]::Is64BitOperatingSystem) { throw '64-bit Windows is required.' }
}

function Ensure-Directories {
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null
}

function New-LogPath {
    param([Parameter(Mandatory)][string]$Prefix)
    Ensure-Directories
    return (Join-Path $script:LogDir ("{0}-{1}.log" -f $Prefix,(Get-Date -Format 'yyyyMMdd-HHmmss')))
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-PortableRuntimeIntegrity {
    if (-not $script:IsPortableRuntime) { return }
    if (-not (Test-Path -LiteralPath $script:PortableManifestPath -PathType Leaf)) {
        throw "Portable runtime manifest is missing: $script:PortableManifestPath"
    }

    $seen = @{}
    $entryCount = 0
    foreach ($rawLine in (Get-Content -LiteralPath $script:PortableManifestPath -ErrorAction Stop)) {
        $line = $rawLine.Trim()
        if ($line.Length -eq 0) { continue }
        if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*([^\\/]+)$') {
            throw "Malformed portable-runtime manifest line: $line"
        }

        $expected = $Matches[1].ToLowerInvariant()
        $relative = $Matches[2]
        if ($relative -eq '.' -or $relative -eq '..' -or $seen.ContainsKey($relative.ToLowerInvariant())) {
            throw "Invalid or duplicate portable-runtime manifest filename: $relative"
        }
        $path = Join-Path $script:PackageRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Portable runtime file is missing: $relative"
        }
        $actual = Get-Sha256 $path
        if ($actual -ne $expected) {
            throw "Portable runtime hash mismatch: $relative"
        }
        $seen[$relative.ToLowerInvariant()] = $true
        $entryCount++
    }

    $required = @(
        'TPM-Updater.exe',
        'TPMFactoryUpd-Direct-Win11-x64.exe',
        'TVicPort.sys'
    ) + @(
        $script:Routes.Values |
            ForEach-Object { [string]$_.FirmwareFile } |
            Sort-Object -Unique
    ) + @(
        'TPM-Updater.cmd',
        'TPM-Updater.ps1',
        'UpdaterCommon.ps1',
        '00-PowerShell-Syntax-Check.ps1',
        'VERIFY-PORTABLE.cmd',
        'VERIFY-PORTABLE.ps1',
        'PORTABLE-RUNTIME.txt',
        'BUILD-INFO.txt'
    )
    foreach ($relative in $required) {
        if (-not $seen.ContainsKey($relative.ToLowerInvariant())) {
            throw "Required portable runtime file is not protected by the manifest: $relative"
        }
    }
    if ($entryCount -lt $required.Count) { throw 'Portable runtime manifest is incomplete.' }
}

function Quote-NativePath {
    param([Parameter(Mandatory)][string]$Path)
    return ('"{0}"' -f $Path.Replace('"','\"'))
}

function Assert-BitLockerProtectionOff {
    $raw = (& "$env:SystemRoot\System32\manage-bde.exe" -status 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "manage-bde failed with exit code $LASTEXITCODE." }
    if ($raw -match '(?im)^\s*Protection Status:\s*Protection On\s*$') {
        throw 'BitLocker protection is ON. Suspend or disable it before updating TPM firmware.'
    }
    if ($raw -notmatch '(?im)^\s*Protection Status:\s*Protection Off\s*$') {
        throw 'Could not verify that BitLocker protection is OFF.'
    }
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Operation,
        [string]$WorkingDirectory = $script:PackageRoot
    )

    Ensure-Directories
    $stdoutPath = "$LogPath.stdout.tmp"
    $stderrPath = "$LogPath.stderr.tmp"
    Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue

    $started = Get-Date
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments `
        -WorkingDirectory $WorkingDirectory -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

    $timedOut = -not $p.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try { & "$env:SystemRoot\System32\taskkill.exe" /PID $p.Id /T /F *> $null } catch { }
        try { [void]$p.WaitForExit(5000) } catch { }
        $exitCode = $null
    } else {
        $p.WaitForExit()
        $exitCode = [int]$p.ExitCode
    }

    $ended = Get-Date
    $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content $stdoutPath -Raw -ErrorAction SilentlyContinue } else { '' }
    $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content $stderrPath -Raw -ErrorAction SilentlyContinue } else { '' }

    @(
        "Operation: $Operation"
        "Started UTC: $($started.ToUniversalTime().ToString('o'))"
        "Ended UTC: $($ended.ToUniversalTime().ToString('o'))"
        "Elapsed seconds: $([math]::Round(($ended-$started).TotalSeconds,3))"
        "Timed out: $timedOut"
        "Exit code: $(if($null -eq $exitCode){'<none>'}else{$exitCode})"
        "Executable: $FilePath"
        "Arguments: $($Arguments -join ' ')"
        ''
        '----- STDOUT -----'
        $stdout
        ''
        '----- STDERR -----'
        $stderr
    ) | Set-Content -LiteralPath $LogPath -Encoding UTF8

    Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue

    [pscustomobject]@{
        TimedOut = $timedOut
        ExitCode = $exitCode
        StdOut = $stdout
        StdErr = $stderr
        LogPath = $LogPath
    }
}

function Invoke-BoundedWindowsPowerShellJson {
    param(
        [Parameter(Mandatory)][string]$ScriptText,
        [Parameter(Mandatory)][string]$LogPrefix,
        [ValidateRange(5,60)][int]$TimeoutSeconds = 15
    )

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptText))
    $log = New-LogPath $LogPrefix
    $run = Invoke-BoundedProcess `
        -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Arguments @('-NoLogo','-NoProfile','-EncodedCommand',$encoded) `
        -TimeoutSeconds $TimeoutSeconds -LogPath $log -Operation $LogPrefix

    if ($run.TimedOut -or $run.ExitCode -ne 0) {
        return [pscustomobject]@{
            QuerySucceeded = $false
            TimedOut = [bool]$run.TimedOut
            Error = if ($run.TimedOut) { 'The Windows TPM query timed out.' } else { "The Windows TPM query exited with code $($run.ExitCode)." }
            LogPath = $log
        }
    }

    try {
        $jsonLine = @($run.StdOut -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[-1]
        $result = $jsonLine | ConvertFrom-Json -ErrorAction Stop
        $result | Add-Member -NotePropertyName LogPath -NotePropertyValue $log -Force
        $result | Add-Member -NotePropertyName TimedOut -NotePropertyValue $false -Force
        return $result
    }
    catch {
        return [pscustomobject]@{
            QuerySucceeded = $false
            TimedOut = $false
            Error = 'Windows returned an unreadable TPM-status response.'
            LogPath = $log
        }
    }
}

function Get-WindowsTpmStatus {
    $probe = @'
$ErrorActionPreference = 'Stop'
try {
    $tpm = Get-Tpm -ErrorAction Stop
    [pscustomobject]@{
        QuerySucceeded = $true
        TpmPresent = [bool]$tpm.TpmPresent
        TpmReady = [bool]$tpm.TpmReady
        TpmEnabled = [bool]$tpm.TpmEnabled
        TpmActivated = [bool]$tpm.TpmActivated
        ManagedAuthLevel = [string]$tpm.ManagedAuthLevel
        AutoProvisioning = [string]$tpm.AutoProvisioning
    } | ConvertTo-Json -Compress
}
catch {
    [pscustomobject]@{
        QuerySucceeded = $false
        Error = $_.Exception.Message
    } | ConvertTo-Json -Compress
}
'@
    return (Invoke-BoundedWindowsPowerShellJson -ScriptText $probe -LogPrefix 'windows-tpm-status' -TimeoutSeconds 15)
}

function Get-TpmEndorsementKeyFingerprint {
    $probe = @'
$ErrorActionPreference = 'Stop'
try {
    $ek = Get-TpmEndorsementKeyInfo -HashAlgorithm Sha256 -ErrorAction Stop
    [pscustomobject]@{
        QuerySucceeded = $true
        IsPresent = [bool]$ek.IsPresent
        PublicKeyHash = [string]$ek.PublicKeyHash
    } | ConvertTo-Json -Compress
}
catch {
    [pscustomobject]@{
        QuerySucceeded = $false
        Error = $_.Exception.Message
    } | ConvertTo-Json -Compress
}
'@
    $result = Invoke-BoundedWindowsPowerShellJson -ScriptText $probe -LogPrefix 'tpm-endorsement-key' -TimeoutSeconds 20
    if ([bool]$result.QuerySucceeded -and [bool]$result.IsPresent -and
        [string]$result.PublicKeyHash -match '^[0-9A-Fa-f]{64}$') {
        return ([string]$result.PublicKeyHash).ToLowerInvariant()
    }
    return $null
}

function Get-ComputerFingerprint {
    $machineGuid = [string](Get-ItemPropertyValue `
        -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' `
        -Name MachineGuid -ErrorAction Stop)
    $bytes = [Text.Encoding]::UTF8.GetBytes("IFX-TPM-Updater|$machineGuid")
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-CurrentBootIdentifier {
    try {
        $value = Get-ItemPropertyValue `
            -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Windows' `
            -Name ShutdownTime -ErrorAction Stop
        if ($value -is [byte[]] -and $value.Length -eq 8) {
            return ([BitConverter]::ToString($value) -replace '-','').ToLowerInvariant()
        }
    }
    catch { }

    # A fallback for systems where ShutdownTime is unavailable. It is used
    # only to decide whether a mandatory post-flash reboot has occurred.
    return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')
}

function Get-TrustedComputingStatus {
    param(
        [Parameter(Mandatory)]$DirectState,
        [Parameter(Mandatory)]$WindowsStatus
    )

    if ([bool]$WindowsStatus.QuerySucceeded) {
        if ([bool]$WindowsStatus.TpmPresent -and [bool]$WindowsStatus.TpmEnabled) {
            return 'Enabled'
        }
        if (-not [bool]$WindowsStatus.TpmPresent -or -not [bool]$WindowsStatus.TpmEnabled) {
            return 'Disabled'
        }
    }

    # The target systems proved that BIOS Security Device Support establishes
    # a non-empty platformAuth, while disabling it leaves direct physical TIS
    # access available with an empty platformAuth. Use this only as a logged
    # fallback when the bounded Windows TPM query itself is unavailable.
    if ([string]$DirectState.PlatformAuth -eq 'Empty Buffer') { return 'Disabled' }
    if ([string]$DirectState.PlatformAuth -eq 'Not Empty Buffer') { return 'Enabled' }
    return 'Unknown'
}

function Get-Workflow {
    if (-not (Test-Path -LiteralPath $script:WorkflowPath -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $script:WorkflowPath -Raw | ConvertFrom-Json -ErrorAction Stop) }
    catch { return $null }
}

function Save-Workflow {
    param([Parameter(Mandatory)]$Workflow)
    Ensure-Directories
    $temporary = "$script:WorkflowPath.tmp"
    $Workflow | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $script:WorkflowPath -Force
}

function Assert-DriverPayload {
    foreach ($path in (@($script:BundledDriverPath,$script:DriverPath) | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "TVicPort.sys is missing: $path"
        }
        $hash = Get-Sha256 $path
        if ($hash -ne $script:ExpectedTvicSysSha256) {
            throw "TVicPort.sys hash mismatch: $path"
        }
    }
}

function Convert-TvicImagePathToFileSystemPath {
    param([AllowNull()][string]$ImagePath)

    if ([string]::IsNullOrWhiteSpace($ImagePath)) { return $null }
    $resolved = $ImagePath.Trim().Trim('"')
    if ($resolved -match '^\\\?\?\\(.+)$') { return $Matches[1] }
    if ($resolved -match '^\\\\\?\\(.+)$') { return $Matches[1] }
    if ($resolved -match '^\\SystemRoot\\(.+)$') { return (Join-Path $env:SystemRoot $Matches[1]) }
    return [Environment]::ExpandEnvironmentVariables($resolved)
}

function Assert-ExistingTvicDriverIsKnownGood {
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\TVICPORT'
    if (-not (Test-Path -LiteralPath $key)) { return }

    $serviceType = [int](Get-ItemPropertyValue -LiteralPath $key -Name Type -ErrorAction Stop)
    if ($serviceType -ne 1) {
        throw "Existing TVICPORT service is not a kernel-driver service (Type=$serviceType)."
    }

    $imagePath = [string](Get-ItemPropertyValue -LiteralPath $key -Name ImagePath -ErrorAction SilentlyContinue)
    $resolved = Convert-TvicImagePathToFileSystemPath $imagePath
    $desired = (Resolve-Path -LiteralPath $script:DriverPath -ErrorAction Stop).Path
    $service = Get-Service -Name $script:TvicServiceName -ErrorAction Stop
    $isRunning = [string]$service.Status -eq 'Running'

    if ($resolved -and (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        if ((Get-Sha256 $resolved) -ne $script:ExpectedTvicSysSha256) {
            throw "Existing TVICPORT service uses an unexpected driver: $resolved"
        }
    }
    elseif ($isRunning) {
        throw "Running TVICPORT service points to a missing driver and its loaded image cannot be verified: $imagePath"
    }

    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($resolved, $desired)) {
        $desiredImagePath = '\??\' + $desired
        Set-ItemProperty -LiteralPath $key -Name ImagePath -Value $desiredImagePath -ErrorAction Stop

        $updated = [string](Get-ItemPropertyValue -LiteralPath $key -Name ImagePath -ErrorAction Stop)
        $updatedResolved = Convert-TvicImagePathToFileSystemPath $updated
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals($updatedResolved, $desired)) {
            throw "Failed to relocate TVICPORT to the current portable folder. Registry path: $updated"
        }
    }

    $startType = [int](Get-ItemPropertyValue -LiteralPath $key -Name Start -ErrorAction Stop)
    if ($startType -eq 4) {
        Set-ItemProperty -LiteralPath $key -Name Start -Value 3 -ErrorAction Stop
    }
}

function Assert-UpdaterExecutable {
    Assert-PortableRuntimeIntegrity
    if (-not (Test-Path -LiteralPath $script:ExePath -PathType Leaf)) {
        throw "Updater executable is not built: $script:ExePath"
    }
    if (-not (Test-Path -LiteralPath $script:BuildInfoPath -PathType Leaf)) {
        throw "Build identity file is missing: $script:BuildInfoPath. Rebuild this package."
    }
    $buildInfo = Get-Content -LiteralPath $script:BuildInfoPath -Raw
    if ($buildInfo -notmatch "(?m)^Package build ID:\s*$([regex]::Escape($script:BuildId))\s*$") {
        throw 'The executable was not built from this V0.8 package. Rebuild from the V0.8 source package.'
    }
    $recordedExeHash = [regex]::Match($buildInfo, '(?im)^Executable SHA-256:\s*([0-9A-F]{64})\s*$')
    if (-not $recordedExeHash.Success) { throw 'Build identity file does not contain the executable SHA-256.' }
    $exeHash = Get-Sha256 $script:ExePath
    if ($exeHash -ne $recordedExeHash.Groups[1].Value.ToLowerInvariant()) {
        throw 'Updater executable does not match its build identity SHA-256.'
    }
    Assert-DriverPayload
    return $exeHash
}

function Test-UpdaterExecutable {
    if (-not (Test-Path -LiteralPath $script:ExePath -PathType Leaf)) { return $false }
    if (-not (Test-Path -LiteralPath $script:DriverPath -PathType Leaf)) { return $false }
    if (-not (Test-Path -LiteralPath $script:BuildInfoPath -PathType Leaf)) { return $false }

    try {
        Assert-PortableRuntimeIntegrity
        $buildInfo = Get-Content -LiteralPath $script:BuildInfoPath -Raw
        if ($buildInfo -notmatch "(?m)^Package build ID:\s*$([regex]::Escape($script:BuildId))\s*$") { return $false }
        $recordedExeHash = [regex]::Match($buildInfo, '(?im)^Executable SHA-256:\s*([0-9A-F]{64})\s*$')
        if (-not $recordedExeHash.Success) { return $false }
        if ((Get-Sha256 $script:ExePath) -ne $recordedExeHash.Groups[1].Value.ToLowerInvariant()) { return $false }
        if ((Get-Sha256 $script:DriverPath) -ne $script:ExpectedTvicSysSha256) { return $false }
        $log = New-LogPath 'smoke-test'
        $run = Invoke-BoundedProcess -FilePath $script:ExePath -Arguments @('-help') `
            -TimeoutSeconds 8 -LogPath $log -Operation 'TPMFactoryUpd startup smoke test' `
            -WorkingDirectory (Split-Path -Parent $script:ExePath)
        return (-not $run.TimedOut -and $run.ExitCode -eq 0 -and $run.StdOut -match [regex]::Escape("Ver $script:ToolVersion"))
    } catch {
        return $false
    }
}

function Get-TvicServiceSnapshot {
    try {
        $svc = Get-CimInstance Win32_SystemDriver -Filter "Name='$script:TvicServiceName'" -ErrorAction Stop
        if ($svc) {
            return [pscustomobject]@{
                Existed = $true
                State = [string]$svc.State
                PathName = [string]$svc.PathName
            }
        }
    } catch { }

    return [pscustomobject]@{ Existed=$false; State=$null; PathName=$null }
}

function Cleanup-NewTvicServiceAfterKilledProbe {
    param([Parameter(Mandatory)]$Before)

    if ($Before.Existed) { return }
    try {
        $svc = Get-Service -Name $script:TvicServiceName -ErrorAction SilentlyContinue
        if ($svc) {
            & "$env:SystemRoot\System32\sc.exe" stop $script:TvicServiceName *> $null
            Start-Sleep -Milliseconds 500
            & "$env:SystemRoot\System32\sc.exe" delete $script:TvicServiceName *> $null
        }
    } catch { }
}

function Get-RouteForVersion {
    param([Parameter(Mandatory)][string]$Version)
    if ($Version -eq '5.67.19690.2') { return $null }
    if (-not $script:Routes.ContainsKey($Version)) {
        $supported = @($script:Routes.Keys | Sort-Object { [version]$_ }) -join ', '
        throw "Unsupported TPM firmware version '$Version'. Supported source versions are: $supported."
    }
    return [pscustomobject]$script:Routes[$Version]
}

function Get-FirmwareUpgradeChain {
    param([Parameter(Mandatory)][string]$Version)

    $chain = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $cursor = $Version
    while ($cursor -ne '5.67.19690.2') {
        if ($seen.ContainsKey($cursor)) {
            throw "Firmware-route cycle detected at '$cursor'."
        }
        $seen[$cursor] = $true
        $route = Get-RouteForVersion $cursor
        if ($null -eq $route) { break }
        $chain.Add($route)
        $cursor = [string]$route.TargetVersion
        if ($chain.Count -gt 8) {
            throw 'Firmware upgrade path exceeds the supported safety limit.'
        }
    }
    # Windows PowerShell 5.1 can throw "Argument types do not match" when
    # @() directly enumerates a generic List[object]. Convert it to a real
    # Object[] first; callers can then enumerate zero, one, or many routes.
    return $chain.ToArray()
}

function Assert-FirmwareForRoute {
    param([Parameter(Mandatory)]$Route)
    $path = Join-Path $script:FirmwareDir ([string]$Route.FirmwareFile)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Firmware image is missing: $path" }
    $hash = Get-Sha256 $path
    if ($hash -ne ([string]$Route.FirmwareSha256).ToLowerInvariant()) {
        throw "Firmware image hash mismatch: $path"
    }
    [pscustomobject]@{ Path=$path; Sha256=$hash }
}

function Invoke-DirectTpmFactoryInfo {
    param([Parameter(Mandatory)][string]$LogPath)

    [void](Assert-UpdaterExecutable)
    Assert-ExistingTvicDriverIsKnownGood
    $before = Get-TvicServiceSnapshot

    $internalLog = New-LogPath 'TPMFactoryUpd-info'
    $oldDebug = $env:IFX_TPM_DIRECT_DEBUG
    $env:IFX_TPM_DIRECT_DEBUG = '1'
    try {
        $run = Invoke-BoundedProcess -FilePath $script:ExePath `
            -Arguments @('-access-mode','1','-info','-log',(Quote-NativePath $internalLog)) `
            -TimeoutSeconds 20 -LogPath $LogPath `
            -Operation 'Direct physical TPM info' `
            -WorkingDirectory (Split-Path -Parent $script:ExePath)
    }
    finally {
        $env:IFX_TPM_DIRECT_DEBUG = $oldDebug
    }

    if ($run.TimedOut) {
        Cleanup-NewTvicServiceAfterKilledProbe -Before $before
        throw "Direct TPM query timed out after 20 seconds. No firmware write was started. Log: $LogPath"
    }
    if ($run.ExitCode -ne 0) {
        $message = [regex]::Match($run.StdOut, '(?ims)Message:\s*(.+?)(?:\r?\n\r?\n|$)')
        if ($message.Success) { throw ("TPM query failed: " + ($message.Groups[1].Value -replace '\s+',' ').Trim() + "`nLog: $LogPath") }
        throw "TPM query failed with exit code $($run.ExitCode). Log: $LogPath"
    }

    $combined = ($run.StdOut + "`r`n" + $run.StdErr).Trim()
    if ([string]::IsNullOrWhiteSpace($combined)) { throw "TPM query returned no output. Log: $LogPath" }
    return $combined
}

function Convert-DirectInfoToState {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$InfoLog
    )

    if ($Text -notmatch [regex]::Escape("Ver $script:ToolVersion")) {
        throw "Unexpected TPMFactoryUpd version. Log: $InfoLog"
    }

    $identity = [regex]::Match($Text, '(?im)^\[V0\.8 IDENTITY\]\s+infineon=(Yes|No)\s+unsupportedChip=(Yes|No)\s*$')
    $family = [regex]::Match($Text, '(?im)^\s*TPM family\s*:\s*([0-9.]+)\s*$')
    $fw = [regex]::Match($Text, '(?im)^\s*TPM firmware version\s*:\s*([0-9.]+)\s*$')
    $valid = [regex]::Match($Text, '(?im)^\s*TPM firmware valid\s*:\s*(Yes|No)\s*$')
    $operation = [regex]::Match($Text, '(?im)^\s*TPM operation mode\s*:\s*(.+?)\s*$')
    $auth = [regex]::Match($Text, '(?im)^\s*TPM platformAuth\s*:\s*(.+?)\s*$')
    $remaining = [regex]::Match($Text, '(?im)^\s*Remaining updates\s*:\s*([0-9]+)\s*$')

    if (-not $identity.Success -or $identity.Groups[1].Value -ne 'Yes' -or $identity.Groups[2].Value -ne 'No') {
        throw "The direct helper did not positively identify a supported Infineon TPM. Log: $InfoLog"
    }
    if (-not $family.Success -or $family.Groups[1].Value.Trim() -ne '2.0') {
        throw "A usable TPM 2.0 response was not returned. Log: $InfoLog"
    }
    if (-not $fw.Success) { throw "TPM firmware version was not returned. Log: $InfoLog" }
    if (-not $valid.Success) { throw "TPM firmware validity was not returned. Log: $InfoLog" }
    if (-not $operation.Success) { throw "TPM operation mode was not returned. Log: $InfoLog" }
    if (-not $auth.Success) { throw "TPM platformAuth state was not returned. Log: $InfoLog" }
    if (-not $remaining.Success) { throw "TPM remaining-update count was not returned. Log: $InfoLog" }

    $policy = [regex]::Match(
        $Text,
        '(?im)^\[V0\.8 POLICY\]\s+platformPolicy\s+handle=0x4000000C\s+alg=0x([0-9A-F]{4})\s+digest=([0-9A-F]+)\s*$'
    )
    $policyNone = $Text -match '(?im)^\[V0\.8 POLICY\]\s+platformPolicy=none\s*$'
    $policyUnsupported = [regex]::Match($Text, '(?im)^\[V0\.8 POLICY\]\s+platformPolicy=unsupported-capability\s+tpmRc=0x([0-9A-F]{8})\s*$')
    $policyUnavailable = [regex]::Match($Text, '(?im)^\[V0\.8 POLICY\]\s+platformPolicy=unavailable(?:\s+.*?tpmRc=0x([0-9A-F]{8}))?.*$')

    [pscustomobject]@{
        Manufacturer = 'IFX'
        UnsupportedChip = 'No'
        Family = '2.0'
        Version = $fw.Groups[1].Value.Trim()
        FirmwareValid = $valid.Groups[1].Value.Trim()
        OperationMode = $operation.Groups[1].Value.Trim()
        PlatformAuth = $auth.Groups[1].Value.Trim()
        RemainingUpdates = [int]$remaining.Groups[1].Value
        PlatformPolicyAlg = if($policy.Success){('0x' + $policy.Groups[1].Value.ToUpperInvariant())}else{$null}
        PlatformPolicyDigest = if($policy.Success){$policy.Groups[2].Value.ToLowerInvariant()}else{$null}
        PlatformPolicyStatus = if($policy.Success){'Reported'}elseif($policyNone){'None'}elseif($policyUnsupported.Success){'Unsupported capability'}elseif($policyUnavailable.Success){'Unavailable'}else{'Not reported'}
        PlatformPolicyTpmRc = if($policyUnsupported.Success){('0x' + $policyUnsupported.Groups[1].Value.ToUpperInvariant())}elseif($policyUnavailable.Success -and $policyUnavailable.Groups[1].Success){('0x' + $policyUnavailable.Groups[1].Value.ToUpperInvariant())}else{$null}
        InfoLog = $InfoLog
    }
}

function Assert-StateReadyForUpdate {
    param([Parameter(Mandatory)]$State)

    if ($State.Manufacturer -ne 'IFX' -or $State.Family -ne '2.0' -or $State.UnsupportedChip -ne 'No') {
        throw 'The detected device is not a supported Infineon TPM 2.0 target.'
    }
    if ($State.FirmwareValid -ne 'Yes') { throw 'TPM does not report valid firmware.' }
    if ($State.OperationMode -ne 'Operational') {
        throw "TPM operation mode is '$($State.OperationMode)', not Operational. Fully reboot Windows, then retry."
    }
    if ([int]$State.RemainingUpdates -le 0) { throw 'TPM reports no remaining firmware updates.' }
    if ($State.PlatformAuth -eq 'Platform hierarchy disabled') {
        throw 'The TPM platform hierarchy is disabled by firmware. Enable the TPM/platform hierarchy in BIOS/UEFI, then retry. Do not disable the TPM.'
    }
    if ($State.PlatformAuth -ne 'Empty Buffer' -and $State.PlatformAuth -ne 'Not Empty Buffer') {
        throw "Unrecognized TPM platformAuth state '$($State.PlatformAuth)'. Refusing to guess an authorization mode."
    }
}

function Convert-HexToByteArray {
    param([Parameter(Mandatory)][string]$Hex)

    if ($Hex.Length % 2 -ne 0 -or $Hex -notmatch '^[0-9A-Fa-f]+$') {
        throw "Invalid hexadecimal byte string: $Hex"
    }
    [byte[]]$bytes = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    }
    return ,$bytes
}

function Assert-PolicyFileMatchesPlatformPolicy {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][string]$LiveDigest
    )

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Policy file is not a regular file: $resolved" }

    $digests = @{}
    $inSection = $false
    foreach ($rawLine in (Get-Content -LiteralPath $resolved -ErrorAction Stop)) {
        $line = $rawLine.Trim()
        if ($line -match '^\[([^]]+)\]$') {
            if ($inSection) { break }
            $inSection = ($Matches[1] -eq 'POLICYOR_TPMFWUPDATE')
            continue
        }
        if (-not $inSection -or $line.Length -eq 0 -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
        if ($line -notmatch '^PolicyDigest([1-8])\s*=\s*([0-9A-Fa-f]{64})$') {
            throw "Invalid line in [POLICYOR_TPMFWUPDATE]: $line"
        }
        $index = [int]$Matches[1]
        $digest = $Matches[2].ToLowerInvariant()
        if ($digests.ContainsKey($index)) { throw "Duplicate PolicyDigest$index in policy file." }
        if ($digests.Values -contains $digest) { throw "Duplicate policy digest value at PolicyDigest$index." }
        $digests[$index] = $digest
    }

    if (-not $inSection -and $digests.Count -eq 0) {
        throw 'Policy file does not contain [POLICYOR_TPMFWUPDATE].'
    }
    if ($digests.Count -lt 2 -or $digests.Count -gt 8) {
        throw 'Policy file must contain between 2 and 8 policy digests.'
    }
    for ($i = 1; $i -le $digests.Count; $i++) {
        if (-not $digests.ContainsKey($i)) { throw "Policy file is missing PolicyDigest$i." }
    }
    if (-not ($digests.Values -contains $script:DefaultPlatformPolicySha256)) {
        throw 'Policy file does not include Infineon''s FieldUpgrade PolicyCommandCode digest.'
    }

    $stream = New-Object System.IO.MemoryStream
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        [byte[]]$zeros = New-Object byte[] 32
        [byte[]]$policyOrCommand = @(0x00,0x00,0x01,0x71)
        $stream.Write($zeros, 0, $zeros.Length)
        $stream.Write($policyOrCommand, 0, $policyOrCommand.Length)
        for ($i = 1; $i -le $digests.Count; $i++) {
            [byte[]]$digestBytes = Convert-HexToByteArray $digests[$i]
            $stream.Write($digestBytes, 0, $digestBytes.Length)
        }
        $calculated = ([BitConverter]::ToString($sha.ComputeHash($stream.ToArray())) -replace '-','').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }

    if ($LiveDigest -and $calculated -ne $LiveDigest.ToLowerInvariant()) {
        throw "Policy file is incompatible with the live TPM platform policy. Calculated PolicyOR digest $calculated; TPM reports $LiveDigest."
    }

    return [pscustomobject]@{
        Path = $resolved
        Sha256 = Get-Sha256 $resolved
        PolicyOrDigest = $calculated
        DigestCount = $digests.Count
    }
}

function Get-IfxTpmState {
    $log = New-LogPath 'direct-info'
    $text = Invoke-DirectTpmFactoryInfo -LogPath $log
    return (Convert-DirectInfoToState -Text $text -InfoLog $log)
}

function Resolve-AuthorizationMode {
    param(
        [Parameter(Mandatory)]$State,
        [string]$PolicyFile
    )

    Assert-StateReadyForUpdate $State

    if ($State.PlatformAuth -eq 'Empty Buffer') {
        if ($PolicyFile) { throw '-PolicyFile is not applicable because the live TPM platformAuth is empty.' }
        return [pscustomobject]@{
            Mode = 'tpm20-emptyplatformauth'
            PolicyFile = $null
            PolicyFileSha256 = $null
            Description = 'empty platformAuth'
            PolicyCompatibility = 'Verified'
            PolicyOrDigest = $null
            PolicyDigestCount = 0
        }
    }

    if ($State.PlatformPolicyStatus -eq 'Unsupported capability' -and $State.PlatformPolicyTpmRc -eq '0x000001C4') {
        throw $script:BiosTpmSettingBlockedMessage
    }

    if ($State.PlatformPolicyStatus -ne 'Reported') {
        throw "TPM platformAuth is non-empty, but its platform policy was not reported ($($State.PlatformPolicyStatus)). Refusing to flash."
    }
    if ($State.PlatformPolicyAlg -ne '0x000B' -or $State.PlatformPolicyDigest -notmatch '^[0-9a-f]{64}$') {
        throw "Unsupported live platform policy: algorithm $($State.PlatformPolicyAlg), digest $($State.PlatformPolicyDigest)."
    }

    if ($PolicyFile) {
        $checked = Assert-PolicyFileMatchesPlatformPolicy -Path $PolicyFile -LiveDigest $State.PlatformPolicyDigest
        return [pscustomobject]@{
            Mode = 'tpm20-platformpolicy'
            PolicyFile = $checked.Path
            PolicyFileSha256 = $checked.Sha256
            Description = 'BIOS-enabled TPM with verified PolicyOR file'
            PolicyCompatibility = 'PolicyOR digest exactly matches live platform policy'
            PolicyOrDigest = $checked.PolicyOrDigest
            PolicyDigestCount = $checked.DigestCount
        }
    }

    if ($State.PlatformPolicyDigest -ne $script:DefaultPlatformPolicySha256) {
        throw 'The BIOS-enabled TPM uses an OEM PolicyOR platform policy. Supply its matching Infineon -PolicyFile; no firmware write was attempted.'
    }

    return [pscustomobject]@{
        Mode = 'tpm20-platformpolicy'
        PolicyFile = $null
        PolicyFileSha256 = $null
        Description = 'BIOS-enabled TPM with default FieldUpgrade platform policy'
        PolicyCompatibility = 'Exact default FieldUpgrade policy match'
        PolicyOrDigest = $null
        PolicyDigestCount = 0
    }
}

function New-Plan {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Route,
        [Parameter(Mandatory)]$Firmware,
        [Parameter(Mandatory)][string]$ExeSha256,
        [Parameter(Mandatory)]$Authorization
    )

    [ordered]@{
        SchemaVersion = 100
        Package = $script:PackageVersion
        ComputerName = $env:COMPUTERNAME
        SourceVersion = [string]$Route.SourceVersion
        TargetVersion = [string]$Route.TargetVersion
        Hop = [int]$Route.Hop
        FirmwareFile = [string]$Route.FirmwareFile
        FirmwareSha256 = [string]$Firmware.Sha256
        TpmFactoryUpdVersion = $script:ToolVersion
        TpmFactoryUpdSha256 = $ExeSha256
        TVicPortSysSha256 = $script:ExpectedTvicSysSha256
        AuthorizationMode = [string]$Authorization.Mode
        PolicyFile = $Authorization.PolicyFile
        PolicyFileSha256 = $Authorization.PolicyFileSha256
        PolicyCompatibility = $Authorization.PolicyCompatibility
        PolicyOrDigest = $Authorization.PolicyOrDigest
        PolicyDigestCount = $Authorization.PolicyDigestCount
        PlatformAuth = [string]$State.PlatformAuth
        OperationMode = [string]$State.OperationMode
        RemainingUpdates = [int]$State.RemainingUpdates
        PlatformPolicyAlg = $State.PlatformPolicyAlg
        PlatformPolicyDigest = $State.PlatformPolicyDigest
        PlatformPolicyStatus = $State.PlatformPolicyStatus
        PlatformPolicyTpmRc = $State.PlatformPolicyTpmRc
        PreflightUtc = (Get-Date).ToUniversalTime().ToString('o')
        FlashCompleted = $false
        Verified = $false
    }
}

function Save-Plan {
    param([Parameter(Mandatory)]$Plan)
    Ensure-Directories
    $Plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:PlanPath -Encoding UTF8
}

function Save-SuccessStamp {
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$FlashLog
    )
    Ensure-Directories
    [ordered]@{
        ComputerName = $env:COMPUTERNAME
        SourceVersion = $Plan.SourceVersion
        TargetVersion = $Plan.TargetVersion
        AuthorizationMode = $Plan.AuthorizationMode
        FlashLog = $FlashLog
        CompletedUtc = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:SuccessPath -Encoding UTF8
}

function Get-Plan {
    if (-not (Test-Path -LiteralPath $script:PlanPath -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $script:PlanPath -Raw | ConvertFrom-Json) } catch { return $null }
}

function Test-PlanStillMatches {
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Route,
        [Parameter(Mandatory)]$Firmware,
        [Parameter(Mandatory)][string]$ExeSha256,
        [Parameter(Mandatory)]$Authorization
    )

    if ([string]$Plan.ComputerName -ne $env:COMPUTERNAME) { return $false }
    if ([string]$Plan.SourceVersion -ne [string]$State.Version) { return $false }
    if ([string]$Plan.TargetVersion -ne [string]$Route.TargetVersion) { return $false }
    if ([string]$Plan.FirmwareSha256 -ne [string]$Firmware.Sha256) { return $false }
    if ([string]$Plan.TpmFactoryUpdSha256 -ne $ExeSha256) { return $false }
    if ([string]$State.Manufacturer -ne 'IFX' -or [string]$State.Family -ne '2.0') { return $false }
    if ([string]$State.FirmwareValid -ne 'Yes' -or [string]$State.OperationMode -ne 'Operational') { return $false }
    if ([int]$State.RemainingUpdates -le 0) { return $false }
    if ([string]$Plan.PlatformAuth -ne [string]$State.PlatformAuth) { return $false }
    if ([string]$Plan.PlatformPolicyStatus -ne [string]$State.PlatformPolicyStatus) { return $false }
    if ([string]$Plan.PlatformPolicyAlg -ne [string]$State.PlatformPolicyAlg) { return $false }
    if ([string]$Plan.PlatformPolicyDigest -ne [string]$State.PlatformPolicyDigest) { return $false }
    if ([string]$Plan.PlatformPolicyTpmRc -ne [string]$State.PlatformPolicyTpmRc) { return $false }
    if ([string]$Plan.AuthorizationMode -ne [string]$Authorization.Mode) { return $false }
    if ([string]$Plan.PolicyFileSha256 -ne [string]$Authorization.PolicyFileSha256) { return $false }
    if ([string]$Plan.PolicyOrDigest -ne [string]$Authorization.PolicyOrDigest) { return $false }
    return $true
}

function Get-FlashFailureSummary {
    param(
        [string]$StdOut,
        [string]$InternalLog,
        [int]$ExitCode
    )

    $hasAuthUnavailableInnerCode = $InternalLog -match '(?i)TSS_TPM2_FieldUpgradeStartVendor returned an unexpected value\.\(0xE028012F\)'
    $hasAuthUnavailableWireResponse = $InternalLog -match '(?ims)Sending TPM Command:\s*TPM2_FieldUpgradeStartVendor.*?Received:\s*RxLen\s*=\s*10.*?0000:\s*80 01 00 00 00 0A 00 00\s+01 2F'
    if ($hasAuthUnavailableInnerCode -or $hasAuthUnavailableWireResponse) {
        return 'TPM_RC_AUTH_UNAVAILABLE (0x0000012F) - the platform hierarchy has no usable authPolicy for this policy session, so TPM2_FieldUpgradeStartVendor was rejected.'
    }

    $code = [regex]::Match($StdOut, '(?im)^\s*Error Code:\s*(0x[0-9A-F]+)\s*$')
    $message = [regex]::Match($StdOut, '(?ims)^\s*Message:\s*(.+?)(?:\r?\n\r?\n|$)')
    if ($code.Success -or $message.Success) {
        $c = if($code.Success){$code.Groups[1].Value}else{"exit $ExitCode"}
        $m = if($message.Success){($message.Groups[1].Value -replace '\s+',' ').Trim()}else{'TPMFactoryUpd reported an error.'}
        return "$c - $m"
    }

    $final = [regex]::Match($InternalLog, '(?im)^\s*Final code:\s*(0x[0-9A-F]+)\s*$')
    $finalMessage = [regex]::Match($InternalLog, '(?im)^\s*Final message:\s*(.+?)\s*$')
    if ($final.Success) {
        return (($final.Groups[1].Value + ' - ' + $finalMessage.Groups[1].Value).Trim(' ','-'))
    }

    return "TPMFactoryUpd exited with code $ExitCode."
}

function Test-FirmwareFlashSucceeded {
    param(
        [AllowNull()][AllowEmptyString()][string]$StdOut,
        [AllowNull()][AllowEmptyString()][string]$InternalLog,
        [int]$ExitCode,
        [Parameter(Mandatory)][string]$TargetVersion
    )

    # TPMFactoryUpd redraws its progress counter with bare carriage returns.
    # Normalize console line endings before applying line-anchored evidence
    # checks, or the final "Completion: 100 %" can be missed.
    $normalizedStdOut = ([string]$StdOut) -replace "`r`n", "`n" -replace "`r", "`n"
    $normalizedInternal = ([string]$InternalLog) -replace "`r`n", "`n" -replace "`r", "`n"

    $newValid = $normalizedStdOut -match '(?im)^[ \t]*New firmware valid for TPM[ \t]*:[ \t]*Yes[ \t]*$'
    $targetAfter = [regex]::Match($normalizedStdOut, '(?im)^[ \t]*TPM firmware version after update[ \t]*:[ \t]*([0-9.]+)[ \t]*$')
    $completion = $normalizedStdOut -match '(?im)^[ \t]*Completion:[ \t]*100[ \t]*%[ \t]*$'
    $success = $normalizedStdOut -match [regex]::Escape('TPM Firmware Update completed successfully.')
    $errorCode = $normalizedStdOut -match '(?im)^[ \t]*Error Code:[ \t]*0x'
    $internalError = $normalizedInternal -match '(?im)^[ \t]*Error detected:[ \t]*$'
    $nonzeroFinal = $normalizedInternal -match '(?im)^[ \t]*Final code:[ \t]*0x(?!0{8}[ \t]*$)[0-9A-F]{8}[ \t]*$'

    return [bool](
        $ExitCode -eq 0 -and
        $newValid -and
        $targetAfter.Success -and
        $targetAfter.Groups[1].Value.Trim() -eq $TargetVersion -and
        $completion -and
        $success -and
        -not $errorCode -and
        -not $internalError -and
        -not $nonzeroFinal
    )
}

function Get-LatestInfineonCompletionPercentage {
    param([AllowNull()][AllowEmptyString()][string]$Text)

    $matches = [regex]::Matches([string]$Text, '(?i)Completion:[ \t]*(\d{1,3})[ \t]*%')
    for ($i = $matches.Count - 1; $i -ge 0; $i--) {
        $value = [int]$matches[$i].Groups[1].Value
        if ($value -ge 0 -and $value -le 100) { return $value }
    }
    return $null
}

function Format-TpmFlashProgressBar {
    param(
        [ValidateRange(0,100)][int]$Percent,
        [ValidateRange(10,60)][int]$Width = 40
    )

    $filled = [int][Math]::Floor(($Percent * $Width) / 100.0)
    $bar = ('#' * $filled) + ('-' * ($Width - $filled))
    return ('TPM firmware update [{0}] {1,3}%' -f $bar,$Percent)
}

function Wait-FlashProcessWithProgress {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)][string]$StdOutPath,
        [switch]$Quiet
    )

    $lastPercent = -1

    while ($true) {
        $stdoutSnapshot = ''
        if (Test-Path -LiteralPath $StdOutPath) {
            try { $stdoutSnapshot = Get-Content -LiteralPath $StdOutPath -Raw -ErrorAction Stop }
            catch { $stdoutSnapshot = '' }
        }

        $reportedPercent = Get-LatestInfineonCompletionPercentage -Text $stdoutSnapshot
        if ($null -ne $reportedPercent -and [int]$reportedPercent -ne $lastPercent) {
            $lastPercent = [int]$reportedPercent
            if (-not $Quiet) {
                Write-Host ("`r" + (Format-TpmFlashProgressBar -Percent $lastPercent)) -NoNewline -ForegroundColor Cyan
            }
        }

        try { $Process.Refresh() } catch { }
        if ($Process.HasExited) { break }
        Start-Sleep -Milliseconds 50
    }

    # The process has exited. Give the redirection layer a bounded moment to
    # expose the final bytes, requiring two consecutive stable-length samples.
    # This is post-process capture draining, not a firmware-write timeout.
    $previousLength = -1L
    $stableSamples = 0
    for ($sample = 0; $sample -lt 20 -and $stableSamples -lt 2; $sample++) {
        $captureItem = Get-Item -LiteralPath $StdOutPath -ErrorAction SilentlyContinue
        $currentLength = if ($null -ne $captureItem) { [long]$captureItem.Length } else { 0L }
        if ($currentLength -eq $previousLength) { $stableSamples++ }
        else { $stableSamples = 0; $previousLength = $currentLength }
        if ($stableSamples -lt 2) { Start-Sleep -Milliseconds 25 }
    }

    # Read once more so a final 100-percent record written immediately before
    # exit cannot be missed by the polling interval.
    $finalStdOut = ''
    if (Test-Path -LiteralPath $StdOutPath) {
        try { $finalStdOut = Get-Content -LiteralPath $StdOutPath -Raw -ErrorAction Stop }
        catch { $finalStdOut = '' }
    }
    $finalPercent = Get-LatestInfineonCompletionPercentage -Text $finalStdOut
    if ($null -ne $finalPercent -and [int]$finalPercent -ne $lastPercent) {
        $lastPercent = [int]$finalPercent
        if (-not $Quiet) {
            Write-Host ("`r" + (Format-TpmFlashProgressBar -Percent $lastPercent)) -NoNewline -ForegroundColor Cyan
        }
    }

    if (-not $Quiet -and $lastPercent -ge 0) { Write-Host '' }

    return [pscustomobject]@{
        ExitCode = [int]$Process.ExitCode
        LastReportedPercent = $lastPercent
    }
}

function Invoke-FirmwareFlash {
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$Route,
        [Parameter(Mandatory)]$Firmware,
        [Parameter(Mandatory)]$Authorization
    )

    $flashLog = New-LogPath ("flash-{0}-to-{1}" -f $Route.SourceVersion,$Route.TargetVersion)
    $stdoutLog = "$flashLog.stdout"
    $stderrLog = "$flashLog.stderr"
    $internalLog = New-LogPath 'TPMFactoryUpd-flash'
    Remove-Item -LiteralPath $stdoutLog,$stderrLog -Force -ErrorAction SilentlyContinue

    $args = @(
        '-access-mode','1',
        '-update',$Authorization.Mode,
        '-firmware',(Quote-NativePath $Firmware.Path),
        '-log',(Quote-NativePath $internalLog)
    )
    if ($Authorization.PolicyFile) {
        $args += @('-policyfile',(Quote-NativePath $Authorization.PolicyFile))
    }

    $existing = @(Get-Process -Name 'TPMFactoryUpd-Direct-Win11-x64' -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        throw "Another TPMFactoryUpd process is already running (PID $((($existing | Select-Object -ExpandProperty Id) -join ', ')))."
    }

    $oldDebug = $env:IFX_TPM_DIRECT_DEBUG
    $env:IFX_TPM_DIRECT_DEBUG = '1'
    try {
        $p = Start-Process -FilePath $script:ExePath -ArgumentList $args `
            -WorkingDirectory (Split-Path -Parent $script:ExePath) `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog

        # No timeout or forced termination after the firmware-write command
        # starts. Infineon's CR-redrawn Completion values are read from the
        # growing capture file and rendered as a live progress bar. Process
        # termination is detected through HasExited instead of a blocking
        # WaitForExit call.
        $processResult = Wait-FlashProcessWithProgress -Process $p -StdOutPath $stdoutLog
        $exitCode = [int]$processResult.ExitCode
    }
    finally {
        $env:IFX_TPM_DIRECT_DEBUG = $oldDebug
    }

    $stdout = if(Test-Path $stdoutLog){Get-Content $stdoutLog -Raw -ErrorAction SilentlyContinue}else{''}
    $stderr = if(Test-Path $stderrLog){Get-Content $stderrLog -Raw -ErrorAction SilentlyContinue}else{''}
    $internal = if(Test-Path $internalLog){Get-Content $internalLog -Raw -ErrorAction SilentlyContinue}else{''}

    @(
        "Exit code: $exitCode"
        ''
        '===== STDOUT ====='
        $stdout
        ''
        '===== STDERR / DIRECT TRANSPORT ====='
        $stderr
        ''
        '===== INFINEON INTERNAL LOG FILE ====='
        $internalLog
    ) | Set-Content -LiteralPath $flashLog -Encoding UTF8

    # Accept success on stable, update-specific evidence.  Do not depend on the
    # source-firmware label that changed from "Firmware valid" to
    # "TPM firmware valid" between updater generations.
    $accepted = Test-FirmwareFlashSucceeded -StdOut $stdout -InternalLog $internal `
        -ExitCode $exitCode -TargetVersion ([string]$Route.TargetVersion)

    if (-not $accepted) {
        $summary = Get-FlashFailureSummary -StdOut $stdout -InternalLog $internal -ExitCode $exitCode
        # Infineon's "Updating the TPM firmware" banner is printed before
        # FieldUpgradeStartVendor authorization is evaluated.  Actual payload
        # transfer is evidenced by the later legacy TPM_FieldUpgrade commands.
        $payloadTransferStarted = $internal -match '(?im)^\[[^]]+\]\s+Sending TPM Command:\s*TPM_FieldUpgrade\s*$'
        if ($summary -match '^TPM_RC_AUTH_UNAVAILABLE \(0x0000012F\)' -and -not $payloadTransferStarted) {
            throw "$summary`nThe update-start command was rejected at its authorization gate; no TPM_FieldUpgrade payload-transfer command followed.`nLog: $flashLog"
        }
        if ($Authorization.Mode -eq 'tpm20-platformpolicy' -and -not $payloadTransferStarted) {
            throw "$summary`nPlatform-policy authorization failed before any TPM_FieldUpgrade payload-transfer command.`nLog: $flashLog"
        }
        throw "$summary`nLog: $flashLog"
    }

    # Record success immediately.  Failure to update bookkeeping must not turn
    # a confirmed successful TPM update into a reported flash failure.
    try { Save-SuccessStamp -Plan $Plan -FlashLog $flashLog } catch { }
    try {
        $Plan.FlashCompleted = $true
        $Plan.FlashCompletedUtc = (Get-Date).ToUniversalTime().ToString('o')
        $Plan.FlashLog = $flashLog
        Save-Plan $Plan
    } catch { }

    return $flashLog
}
