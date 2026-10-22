#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReferenceRuntime)

# Validate the real publication functions without compiling or running TPM code.
# Supply an extracted 0.86 portable release (or a successful 0.86 dist build).
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$PackageRoot=Split-Path -Parent $PSScriptRoot
$DistDir=Join-Path ([IO.Path]::GetTempPath()) ('ifx-publication-' + [Guid]::NewGuid().ToString('N'))
$BuildId='IFX-TPM-UPDATER-V0.86-PORTABLE-20261022'
$PackageName='Complete Windows 11 Updater Package V0.86 PORTABLE'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PackageRoot 'Build-Windows11-x64.ps1'),[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw 'Build script must parse before publication tests.'}
$wanted=@('Publish-PortableRuntime','Write-PortableRuntimeManifest','Assert-PortableRuntimeComplete')
foreach($statement in $ast.EndBlock.Statements){
    if($statement -is [Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $statement.Name){
        Invoke-Expression $statement.Extent.Text
    }
}
New-Item -ItemType Directory -Path $DistDir | Out-Null
try {
    foreach($name in @('TPM-Updater.exe','TPMFactoryUpd-Direct-Win11-x64.exe','TVicPort.sys','BUILD-INFO.txt')){
        Copy-Item -LiteralPath (Join-Path $ReferenceRuntime $name) -Destination (Join-Path $DistDir $name) -ErrorAction Stop
    }
    Publish-PortableRuntime
    Write-PortableRuntimeManifest
    Assert-PortableRuntimeComplete
    foreach($name in @('TPM-Updater.ps1','UpdaterCommon.ps1','REGRESSION-TESTS.ps1','CHANGELOG-V0.86.md')){
        $original=(Get-FileHash -LiteralPath (Join-Path $PackageRoot $name) -Algorithm SHA256).Hash
        $published=(Get-FileHash -LiteralPath (Join-Path $DistDir $name) -Algorithm SHA256).Hash
        if($original -ne $published){throw "Published file differs from source: $name"}
    }
    Write-Host 'Portable publication, current scripts, metadata and generated manifest checks passed.' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $DistDir -Recurse -Force -ErrorAction SilentlyContinue
}
