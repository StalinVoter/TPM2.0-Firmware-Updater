#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$manifest = Join-Path $root 'SHA256SUMS.txt'
$expectedBuildId = 'IFX-TPM-UPDATER-V0.831-PORTABLE-20260908'
$expectedDriver = '9c9ab56c8bcf5ec958e7c2346f23a3027f69abdf8af923b591518eee64ad98ad'
$expectedFirmwareHashes = [ordered]@{
    'TPM20_5.0.1089.2_to_TPM20_5.62.3126.2.BIN' = 'c5a51a6a3b866ead2a9266f89b150b2f60eccb113487582592a293698ba26015'
    'TPM20_5.51.2098.0_to_TPM20_5.63.3144.0.BIN' = '49001f5f6f72ea526ad935efb86d2e5dbc9563ca14cd2c00ce7a0e724700b811'
    'TPM20_5.51.2098.2_to_TPM20_5.62.3126.2.BIN' = '711966e03348984d1be51f8e4fe363354de12024752e25685e2660185e8c01d3'
    'TPM20_5.60.2677.0_to_TPM20_5.63.3144.0.BIN' = '053ebbdfb280493cf7fc6a6b83bc9e7828a49c218024e4bad07f0a1f64e83c93'
    'TPM20_5.61.2785.0_to_TPM20_5.63.3144.0.BIN' = 'a6873ad6fdbd5f624ae87e8dc0e495bbfb596d643f8d2baed7f05f90f8332346'
    'TPM20_5.61.2789.0_to_TPM20_5.63.3144.0.BIN' = '5639101462acdde000f77fd3d0d6c1e30115e09eb8ea280267dcd3b3f02ddf50'
    'TPM20_5.62.3126.0_to_TPM20_5.63.3144.0.BIN' = '1bf7bb31c7fb01c749194bfb82dd17c767ab69f7cf499bee7dab5e4060b23928'
    'TPM20_5.62.3126.2_to_TPM20_5.67.19690.2.BIN' = 'e26b363af055141136723b41c6546b8c7eb18cc685ffc4aa89a38552409420e8'
    'TPM20_5.63.3144.0_to_TPM20_5.67.19690.2.BIN' = '543bee0e0076f94eb0c7a8ef43f57d6079c583cc2d6e422ea1a7ced31e8a7627'
    'TPM20_5.63.3353.0_to_TPM20_5.67.19690.2.BIN' = '8dab1c5374d60ae3448e7148d768f41fae6182d1f65cfe3e62448fb770df22e5'
    'TPM20_5.63.3353.2_to_TPM20_5.67.19690.2.BIN' = '50720cb5c868184073aecedf67d0c9ca7fa8b6186c6bfb193b8fde7e879dd831'
    'TPM20_5.66.19374.2_to_TPM20_5.67.19690.2.BIN' = '44a39593eaaa9a2734f5b6e87e8c1267c3a641f0298e95e83c3485a5277320e0'
}

function Get-Hash {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "Missing portable-runtime manifest: $manifest"
}

$seen = @{}
foreach ($rawLine in (Get-Content -LiteralPath $manifest -ErrorAction Stop)) {
    $line = $rawLine.Trim()
    if ($line.Length -eq 0) { continue }
    if ($line -notmatch '^([0-9A-Fa-f]{64})\s+\*([^\\/]+)$') {
        throw "Malformed or non-flat manifest entry: $line"
    }
    $expected = $Matches[1].ToLowerInvariant()
    $name = $Matches[2]
    if ($name -eq '.' -or $name -eq '..' -or $seen.ContainsKey($name.ToLowerInvariant())) {
        throw "Invalid or duplicate manifest filename: $name"
    }
    $path = Join-Path $root $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing portable file: $name" }
    if ((Get-Hash $path) -ne $expected) { throw "SHA-256 mismatch: $name" }
    $seen[$name.ToLowerInvariant()] = $true
}

$required = @(
    'TPM-Updater.exe',
    'TPMFactoryUpd-Direct-Win11-x64.exe',
    'TVicPort.sys'
) + @($expectedFirmwareHashes.Keys) + @(
    'TPM-Updater.cmd',
    'TPM-Updater.ps1',
    'UpdaterCommon.ps1',
    '00-PowerShell-Syntax-Check.ps1',
    'VERIFY-PORTABLE.cmd',
    'VERIFY-PORTABLE.ps1',
    'PORTABLE-RUNTIME.txt',
    'BUILD-INFO.txt'
)
foreach ($name in $required) {
    if (-not $seen.ContainsKey($name.ToLowerInvariant())) {
        throw "Required file is not protected by SHA256SUMS.txt: $name"
    }
}

$markerText = Get-Content -LiteralPath (Join-Path $root 'PORTABLE-RUNTIME.txt') -Raw
if ($markerText -notmatch "(?m)^Package build ID:\s*$([regex]::Escape($expectedBuildId))\s*$") {
    throw 'PORTABLE-RUNTIME.txt does not identify this exact V0.831 build.'
}

$buildInfoPath = Join-Path $root 'BUILD-INFO.txt'
$buildInfo = Get-Content -LiteralPath $buildInfoPath -Raw
if ($buildInfo -notmatch "(?m)^Package build ID:\s*$([regex]::Escape($expectedBuildId))\s*$") {
    throw 'BUILD-INFO.txt does not identify this exact V0.831 portable build.'
}
$recordedExeHash = [regex]::Match($buildInfo, '(?im)^Executable SHA-256:\s*([0-9A-F]{64})\s*$')
if (-not $recordedExeHash.Success) { throw 'BUILD-INFO.txt lacks the executable SHA-256.' }
if ((Get-Hash (Join-Path $root 'TPMFactoryUpd-Direct-Win11-x64.exe')) -ne $recordedExeHash.Groups[1].Value.ToLowerInvariant()) {
    throw 'The executable does not match its BUILD-INFO.txt SHA-256.'
}
$recordedLauncherHash = [regex]::Match($buildInfo, '(?im)^Launcher SHA-256:\s*([0-9A-F]{64})\s*$')
if (-not $recordedLauncherHash.Success) { throw 'BUILD-INFO.txt lacks the launcher SHA-256.' }
if ((Get-Hash (Join-Path $root 'TPM-Updater.exe')) -ne $recordedLauncherHash.Groups[1].Value.ToLowerInvariant()) {
    throw 'TPM-Updater.exe does not match its BUILD-INFO.txt SHA-256.'
}
if ((Get-Hash (Join-Path $root 'TVicPort.sys')) -ne $expectedDriver) { throw 'TVicPort.sys is not the pinned driver.' }
foreach ($entry in $expectedFirmwareHashes.GetEnumerator()) {
    $path = Join-Path $root ([string]$entry.Key)
    if ((Get-Hash $path) -ne [string]$entry.Value) {
        throw "Firmware image is not the pinned image: $($entry.Key)"
    }
}

Write-Host 'V0.831 portable dist verification passed.' -ForegroundColor Green
Write-Host "This folder may be moved or renamed as one unit:`n  $root" -ForegroundColor Cyan
