#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackageRoot = $PSScriptRoot
$BuildDir = Join-Path $PackageRoot 'build'
$DistDir = Join-Path $PackageRoot 'dist'
$LogDir = Join-Path $PackageRoot 'logs'
$VsConfig = Join-Path $PackageRoot 'BuildTools.vsconfig'
$Vs2019Config = Join-Path $PackageRoot 'BuildTools-VS2019.vsconfig'
$BuildRsp = Join-Path $PackageRoot 'build-msvc.rsp'
$LinkRsp = Join-Path $PackageRoot 'link-msvc.rsp'
$ExePath = Join-Path $DistDir 'TPMFactoryUpd-Direct-Win11-x64.exe'
$LauncherSource = Join-Path $PackageRoot 'Source\Launcher\TPM-Updater-Launcher.c'
$LauncherObject = Join-Path $BuildDir 'TPM-Updater-Launcher.obj'
$LauncherExe = Join-Path $DistDir 'TPM-Updater.exe'
$StateRoot = Join-Path $env:ProgramData 'IFX-TPM-Updater-V0.8'
$BootstrapCache = Join-Path $StateRoot 'BuildBootstrap'
$FallbackVsBootstrapper = Join-Path $BootstrapCache 'vs_BuildTools.exe'
$FallbackVsBootstrapperUrl = 'https://aka.ms/vs/17/release/vs_BuildTools.exe'
$PrivateBuildToolsPath = Join-Path $env:ProgramFiles 'Microsoft Visual Studio\IFX-TPM-BuildTools'
$ExpectedToolVersion = '02.03.4733.00'
$BuildId = 'IFX-TPM-UPDATER-V0.8-PORTABLE-20260907'
$PackageName = 'Complete Windows 11 Updater Package V0.8 PORTABLE'
$WingetPackageId = 'Microsoft.VisualStudio.BuildTools'

$DriverSource = Join-Path $PackageRoot 'Driver\TVicPort.sys'
$DriverDist = Join-Path $DistDir 'TVicPort.sys'
$ExpectedTvicSysSha256 = '9c9ab56c8bcf5ec958e7c2346f23a3027f69abdf8af923b591518eee64ad98ad'


function Write-Section {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Cyan
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor Cyan
}

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Host {
    if (-not (Test-Administrator)) {
        throw 'This build/provisioning stage must run as Administrator. Use TPM-Updater.cmd -Action Build.'
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'A 64-bit Windows installation is required.'
    }
    if (-not [Environment]::Is64BitProcess) {
        throw 'Use 64-bit Windows PowerShell.'
    }
    $buildNumber = [int](Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop)
    if ($buildNumber -lt 22000) {
        throw "Windows 11 is required. Detected build $buildNumber."
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Invoke-BoundedBuildProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][string]$StdOutPath,
        [Parameter(Mandatory)][string]$StdErrPath,
        [string]$WorkingDirectory = $PackageRoot
    )

    Ensure-Directory (Split-Path -Parent $StdOutPath)
    Ensure-Directory (Split-Path -Parent $StdErrPath)
    Remove-Item -LiteralPath $StdOutPath,$StdErrPath -Force -ErrorAction SilentlyContinue

    $p = Start-Process `
        -FilePath $FilePath `
        -ArgumentList $Arguments `
        -WorkingDirectory $WorkingDirectory `
        -PassThru `
        -NoNewWindow `
        -RedirectStandardOutput $StdOutPath `
        -RedirectStandardError $StdErrPath

    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try { & "$env:SystemRoot\System32\taskkill.exe" /PID $p.Id /T /F *> $null } catch { }
        try { [void]$p.WaitForExit(5000) } catch { }

        return [pscustomobject]@{
            TimedOut = $true
            ExitCode = $null
            Pid = $p.Id
        }
    }

    try { $p.WaitForExit() } catch { }

    return [pscustomobject]@{
        TimedOut = $false
        ExitCode = [int]$p.ExitCode
        Pid = $p.Id
    }
}

# ---------------------------------------------------------------------------
# WinGet bootstrap / repair
# ---------------------------------------------------------------------------

function Get-WinGetPath {
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) {
        return $cmd.Source
    }

    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $alias -PathType Leaf) {
        return $alias
    }

    try {
        $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop |
            Sort-Object Version -Descending | Select-Object -First 1
        if ($pkg -and $pkg.InstallLocation) {
            $direct = Join-Path ([string]$pkg.InstallLocation) 'winget.exe'
            if (Test-Path -LiteralPath $direct -PathType Leaf) {
                return $direct
            }
        }
    }
    catch { }

    return $null
}

function Test-WinGetUsable {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $output = & $Path --info 2>&1
        $rc = $LASTEXITCODE
        if ($rc -ne 0) { return $false }
        $text = ($output | Out-String)
        return ($text -match 'Windows Package Manager' -or $text -match '(?im)^v?\d+\.\d+')
    }
    catch {
        return $false
    }
}

function Try-RegisterExistingAppInstaller {
    Write-Host 'Attempting to register the built-in App Installer package for the current user...' -ForegroundColor Yellow
    try {
        $cmd = Get-Command Add-AppxPackage -ErrorAction Stop
        if ($cmd.Parameters.ContainsKey('RegisterByFamilyName') -and $cmd.Parameters.ContainsKey('MainPackage')) {
            Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
            return $true
        }

        $pkg = Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending | Select-Object -First 1
        if ($pkg -and $pkg.InstallLocation) {
            $manifest = Join-Path ([string]$pkg.InstallLocation) 'AppxManifest.xml'
            if (Test-Path -LiteralPath $manifest -PathType Leaf) {
                Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
                return $true
            }
        }
    }
    catch {
        Write-Host "App Installer registration attempt did not complete: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
    return $false
}

function Install-Or-RepairWinGetViaPowerShellModule {
    Write-Host 'Bootstrapping/repairing WinGet with Microsoft.WinGet.Client...' -ForegroundColor Yellow

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $repoWasPresent = $false
    $oldPolicy = $null
    try {
        $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if (-not $repo) {
            Register-PSRepository -Default -ErrorAction Stop
            $repo = Get-PSRepository -Name PSGallery -ErrorAction Stop
        }
        $repoWasPresent = $true
        $oldPolicy = [string]$repo.InstallationPolicy
        if ($oldPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
        }

        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nuget) {
            Install-PackageProvider -Name NuGet -Scope AllUsers -Force -Confirm:$false -ErrorAction Stop | Out-Null
        }

        Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope AllUsers -Force -AllowClobber -Confirm:$false -ErrorAction Stop | Out-Null
        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop

        $repair = Get-Command Repair-WinGetPackageManager -ErrorAction Stop
        $repairArgs = @{}
        if ($repair.Parameters.ContainsKey('AllUsers')) { $repairArgs['AllUsers'] = $true }
        if ($repair.Parameters.ContainsKey('Force')) { $repairArgs['Force'] = $true }
        if ($repair.Parameters.ContainsKey('Latest')) { $repairArgs['Latest'] = $true }

        Repair-WinGetPackageManager @repairArgs -ErrorAction Stop | Out-Null
    }
    finally {
        if ($repoWasPresent -and $oldPolicy -and $oldPolicy -ne 'Trusted') {
            try { Set-PSRepository -Name PSGallery -InstallationPolicy $oldPolicy -ErrorAction SilentlyContinue } catch { }
        }
    }
}

function Try-InstallLatestAppInstallerBundle {
    Ensure-Directory $BootstrapCache
    $bundle = Join-Path $BootstrapCache 'Microsoft.DesktopAppInstaller.msixbundle'
    Write-Host 'Downloading the latest stable Microsoft App Installer / WinGet bundle...' -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/getwinget' -OutFile $bundle -ErrorAction Stop
        # The bundle is retrieved from Microsoft's stable aka.ms endpoint.
        # Add-AppxPackage performs the Windows package-signature/trust validation.
        Add-AppxPackage -Path $bundle -ForceApplicationShutdown -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "Direct App Installer bundle attempt did not complete: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return $false
    }
}

function Ensure-WinGet {
    Write-Section 'WINDOWS PACKAGE MANAGER (WINGET) PREREQUISITE'

    $path = Get-WinGetPath
    if (Test-WinGetUsable -Path $path) {
        Write-Host "WinGet is already installed and usable:`n  $path" -ForegroundColor Green
        return $path
    }

    Write-Host 'WinGet is missing, unregistered, or not usable. V0.8 will repair/install it automatically.' -ForegroundColor Yellow

    [void](Try-RegisterExistingAppInstaller)
    $path = Get-WinGetPath
    if (Test-WinGetUsable -Path $path) {
        Write-Host "WinGet became usable after App Installer registration:`n  $path" -ForegroundColor Green
        return $path
    }

    try {
        [void](Install-Or-RepairWinGetViaPowerShellModule)
    }
    catch {
        Write-Host "Microsoft.WinGet.Client repair attempt did not complete: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    [void](Try-RegisterExistingAppInstaller)
    $path = Get-WinGetPath
    if (Test-WinGetUsable -Path $path) {
        Write-Host "WinGet installation/repair succeeded:`n  $path" -ForegroundColor Green
        return $path
    }

    [void](Try-InstallLatestAppInstallerBundle)
    [void](Try-RegisterExistingAppInstaller)
    $path = Get-WinGetPath
    if (Test-WinGetUsable -Path $path) {
        Write-Host "WinGet installation/repair succeeded:`n  $path" -ForegroundColor Green
        return $path
    }

    throw @'
WinGet installation/repair failed.
'@
}

function Ensure-WinGetCommunitySource {
    param([Parameter(Mandatory)][string]$WingetPath)

    Write-Host 'Verifying the WinGet community source and Visual Studio Build Tools package...' -ForegroundColor Yellow

    $showArgs = @(
        'show','-e','--id',$WingetPackageId,
        '--source','winget',
        '--accept-source-agreements',
        '--disable-interactivity'
    )

    & $WingetPath @showArgs *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'WinGet community source is usable.' -ForegroundColor Green
        return
    }

    Write-Host 'WinGet source/package probe failed. Resetting and updating WinGet sources automatically...' -ForegroundColor Yellow
    & $WingetPath source reset --force *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "'winget source reset --force' failed with exit code $LASTEXITCODE."
    }
    & $WingetPath source update *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "'winget source update' failed with exit code $LASTEXITCODE."
    }
    & $WingetPath @showArgs *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "WinGet is installed but cannot resolve package '$WingetPackageId' from the community source."
    }

    Write-Host 'WinGet community source repair succeeded.' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Visual Studio / Windows SDK detection and provisioning
# ---------------------------------------------------------------------------

function Get-VsWherePath {
    $path = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    return $null
}

function Get-VsInstances {
    $byPath = @{}
    $vswhere = Get-VsWherePath

    if ($vswhere) {
        try {
            $jsonText = (& $vswhere -products '*' -format json 2>$null) -join "`n"
            if ($jsonText) {
                $items = $jsonText | ConvertFrom-Json
                foreach ($item in @($items)) {
                    $path = [string]$item.installationPath
                    if (-not $path) { continue }
                    if (-not (Test-Path -LiteralPath (Join-Path $path 'Common7\Tools\VsDevCmd.bat') -PathType Leaf)) { continue }

                    $v = $null
                    try { $v = [version]([string]$item.installationVersion) } catch { $v = [version]'0.0' }
                    $byPath[$path.ToLowerInvariant()] = [pscustomobject]@{
                        Path = $path
                        Version = $v
                        Major = [int]$v.Major
                    }
                }
            }
        }
        catch {
            Write-Host "vswhere enumeration warning: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $patterns = @(
        [pscustomobject]@{ Pattern=(Join-Path $env:ProgramFiles 'Microsoft Visual Studio\18\*\Common7\Tools\VsDevCmd.bat'); Major=18 },
        [pscustomobject]@{ Pattern=(Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022\*\Common7\Tools\VsDevCmd.bat'); Major=17 },
        [pscustomobject]@{ Pattern=(Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2019\*\Common7\Tools\VsDevCmd.bat'); Major=16 }
    )

    foreach ($entry in $patterns) {
        foreach ($item in @(Get-ChildItem -Path $entry.Pattern -File -ErrorAction SilentlyContinue)) {
            $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $item.FullName))
            if (-not $root) { continue }
            $key = $root.ToLowerInvariant()
            if (-not $byPath.ContainsKey($key)) {
                $byPath[$key] = [pscustomobject]@{
                    Path = $root
                    Version = [version]("{0}.0" -f $entry.Major)
                    Major = [int]$entry.Major
                }
            }
        }
    }

    return @($byPath.Values | Sort-Object Version -Descending)
}

function New-PrerequisiteProbeFiles {
    Ensure-Directory $BuildDir
    $source = Join-Path $BuildDir 'build-prerequisite-probe.c'
    $exe = Join-Path $BuildDir 'build-prerequisite-probe.exe'
    $cmd = Join-Path $BuildDir 'build-prerequisite-probe.cmd'

    @'
#include <windows.h>
#include <bcrypt.h>

int main(void)
{
    BCRYPT_ALG_HANDLE h = 0;
    if (0) {
        (void)BCryptOpenAlgorithmProvider(&h, BCRYPT_SHA256_ALGORITHM, NULL, 0);
        if (h) (void)BCryptCloseAlgorithmProvider(h, 0);
    }
    return 0;
}
'@ | Set-Content -LiteralPath $source -Encoding ASCII

    return [pscustomobject]@{ Source=$source; Exe=$exe; Cmd=$cmd }
}

function Test-VsBuildCapability {
    param([Parameter(Mandatory)][string]$InstallationPath)

    $vsdev = Join-Path $InstallationPath 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $vsdev -PathType Leaf)) {
        return [pscustomobject]@{ Success=$false; Log='VsDevCmd.bat is missing.'; ExitCode=100 }
    }

    $probe = New-PrerequisiteProbeFiles
    $stdout = Join-Path $BuildDir 'build-prerequisite-probe.stdout.txt'
    $stderr = Join-Path $BuildDir 'build-prerequisite-probe.stderr.txt'
    Remove-Item -LiteralPath $probe.Exe,$stdout,$stderr -Force -ErrorAction SilentlyContinue

    @"
@echo off
call "$vsdev" -no_logo -arch=x64 -host_arch=x64 >nul
if errorlevel 1 exit /b 101
where cl.exe >nul 2>&1
if errorlevel 1 exit /b 102
where link.exe >nul 2>&1
if errorlevel 1 exit /b 103
cl.exe /nologo /TC /std:c11 /W3 /WX /D_WIN32_WINNT=0x0A00 "$($probe.Source)" /Fe:"$($probe.Exe)" /link bcrypt.lib advapi32.lib
exit /b %ERRORLEVEL%
"@ | Set-Content -LiteralPath $probe.Cmd -Encoding ASCII

    $run = Invoke-BoundedBuildProcess `
        -FilePath $env:ComSpec `
        -Arguments @('/d','/c',"`"$($probe.Cmd)`"") `
        -TimeoutSeconds 60 `
        -StdOutPath $stdout `
        -StdErrPath $stderr `
        -WorkingDirectory $PackageRoot

    $text = ''
    if (Test-Path -LiteralPath $stdout) { $text += (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) }
    if (Test-Path -LiteralPath $stderr) { $text += (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) }

    if ($run.TimedOut) {
        $text += "`r`nThe Visual Studio compiler/SDK capability probe exceeded 60 seconds."
        return [pscustomobject]@{ Success=$false; Log=$text; ExitCode=408; TimedOut=$true }
    }

    $ok = ($run.ExitCode -eq 0 -and (Test-Path -LiteralPath $probe.Exe -PathType Leaf))
    return [pscustomobject]@{ Success=$ok; Log=$text; ExitCode=$run.ExitCode; TimedOut=$false }
}

function Get-WorkingVsInstance {
    foreach ($instance in @(Get-VsInstances)) {
        if ($instance.Major -lt 16) { continue }
        Write-Host "Testing existing Visual Studio/Build Tools instance:`n  $($instance.Path)" -ForegroundColor DarkCyan
        $test = Test-VsBuildCapability -InstallationPath $instance.Path
        if ($test.Success) {
            Write-Host 'Existing MSVC x64 + Windows SDK environment is complete.' -ForegroundColor Green
            return $instance
        }
        if ($test.PSObject.Properties.Name -contains 'TimedOut' -and $test.TimedOut) {
            Write-Host 'The build-capability probe exceeded 60 seconds and its process tree was terminated.' -ForegroundColor Yellow
        }
        Write-Host 'Instance is present but is missing or cannot use one or more required build components.' -ForegroundColor Yellow
    }
    return $null
}

function Get-PreferredExistingVsInstance {
    $items = @(Get-VsInstances | Where-Object { $_.Major -ge 16 })
    if ($items.Count -gt 0) { return $items[0] }
    return $null
}

function Get-VisualStudioInstallerPath {
    $path = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    return $null
}

function Invoke-VisualStudioInstaller {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation
    )

    Write-Host "$Operation..." -ForegroundColor Yellow
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -Wait
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010 -and $p.ExitCode -ne 1641) {
        throw "$Operation failed with installer exit code $($p.ExitCode)."
    }
    if ($p.ExitCode -eq 3010 -or $p.ExitCode -eq 1641) {
        Write-Host 'Visual Studio Installer reports that a Windows restart is required.' -ForegroundColor Yellow
        return $true
    }
    return $false
}

function Get-FallbackMicrosoftBuildToolsBootstrapper {
    Ensure-Directory $BootstrapCache

    $needDownload = -not (Test-Path -LiteralPath $FallbackVsBootstrapper -PathType Leaf)
    if (-not $needDownload) {
        $sig = Get-AuthenticodeSignature -LiteralPath $FallbackVsBootstrapper
        if ($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch 'Microsoft') {
            Remove-Item -LiteralPath $FallbackVsBootstrapper -Force -ErrorAction SilentlyContinue
            $needDownload = $true
        }
    }

    if ($needDownload) {
        Write-Host 'Downloading the Microsoft-signed Visual Studio Build Tools bootstrapper to repair the shared VS Installer...' -ForegroundColor Yellow
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $FallbackVsBootstrapperUrl -OutFile $FallbackVsBootstrapper -ErrorAction Stop
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $FallbackVsBootstrapper
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw 'Fallback Visual Studio bootstrapper is not validly Microsoft-signed. Refusing to execute it.'
    }
    return $FallbackVsBootstrapper
}

function Install-BuildToolsWithWinGet {
    param([Parameter(Mandatory)][string]$WingetPath)

    Ensure-WinGetCommunitySource -WingetPath $WingetPath

    if (-not (Test-Path -LiteralPath $VsConfig -PathType Leaf)) {
        throw "Missing build configuration: $VsConfig"
    }

    $override = "--wait --passive --norestart --nocache --installPath `"$PrivateBuildToolsPath`" --config `"$VsConfig`""
    $wingetArgs = @(
        'install','-e','--id',$WingetPackageId,
        '--source','winget',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity',
        '--override',$override
    )

    Write-Host 'Installing Microsoft Visual Studio Build Tools through WinGet...' -ForegroundColor Yellow
    $wingetOutput = @(& $WingetPath @wingetArgs 2>&1)
    $rc = $LASTEXITCODE
    foreach ($line in $wingetOutput) {
        Write-Host ([string]$line)
    }

    # WinGet itself normally returns 0 when the underlying installer succeeds.
    # If a restart is required, the post-install real compile/link probe below
    # decides whether we can continue safely or must stop for reboot.
    if ($rc -ne 0) {
        throw "WinGet Build Tools installation failed with exit code $rc."
    }
}

function Install-Or-RepairBuildPrerequisites {
    param([Parameter(Mandatory)][string]$WingetPath)

    if (-not (Test-Path -LiteralPath $VsConfig -PathType Leaf)) {
        throw "Missing build configuration: $VsConfig"
    }

    $existing = Get-PreferredExistingVsInstance
    $rebootRequired = $false

    if ($existing) {
        Write-Host ''
        Write-Host 'An existing Visual Studio/Build Tools installation was found.' -ForegroundColor Cyan
        Write-Host 'Adding/repairing the required compiler/SDK components in the existing Visual Studio instance.' -ForegroundColor Cyan
        Write-Host "Instance: $($existing.Path)"

        $installer = Get-VisualStudioInstallerPath
        if (-not $installer) {
            Write-Host 'The Visual Studio product exists but the shared Visual Studio Installer is missing.' -ForegroundColor Yellow
            Write-Host 'Repairing the shared Visual Studio installer.' -ForegroundColor Yellow
            $bootstrap = Get-FallbackMicrosoftBuildToolsBootstrapper
            [void](Invoke-VisualStudioInstaller -FilePath $bootstrap -Arguments @('--update','--quiet','--wait','--norestart') -Operation 'Restoring/updating the Microsoft Visual Studio Installer')
            $installer = Get-VisualStudioInstallerPath
            if (-not $installer) {
                throw 'Automatic Visual Studio Installer restoration did not produce setup.exe.'
            }
        }

        $configForExisting = $VsConfig
        if ($existing.Major -eq 16) { $configForExisting = $Vs2019Config }
        if (-not (Test-Path -LiteralPath $configForExisting -PathType Leaf)) {
            throw "Missing build configuration: $configForExisting"
        }

        $args = @(
            'modify',
            '--installPath', ('"' + $existing.Path + '"'),
            '--config', ('"' + $configForExisting + '"'),
            '--passive',
            '--norestart'
        )
        $rebootRequired = Invoke-VisualStudioInstaller -FilePath $installer -Arguments $args -Operation 'Adding/repairing the required MSVC x64 and Windows SDK components'
    }
    else {
        Write-Host ''
        Write-Host 'Visual Studio/Build Tools is not installed.' -ForegroundColor Cyan
        Write-Host 'Installing the required Microsoft Build Tools through WinGet.' -ForegroundColor Cyan
        Install-BuildToolsWithWinGet -WingetPath $WingetPath
    }

    return $rebootRequired
}

function Ensure-BuildEnvironment {
    param([Parameter(Mandatory)][string]$WingetPath)

    Write-Section 'BUILD PREREQUISITE DETECTION'

    $working = Get-WorkingVsInstance
    if ($working) { return $working.Path }

    $rebootRequired = Install-Or-RepairBuildPrerequisites -WingetPath $WingetPath

    Write-Host ''
    Write-Host 'Re-testing the actual compiler + SDK capability after provisioning...' -ForegroundColor Cyan
    $working = Get-WorkingVsInstance
    if ($working) { return $working.Path }

    if ($rebootRequired) {
        throw @'
The required components were installed, but Windows reports that a restart is required and
the compiler/SDK probe is not usable yet. Restart Windows and run TPM-Updater.cmd -Action Build
again.
'@
    }

    $probeLog = Join-Path $BuildDir 'build-prerequisite-probe.stdout.txt'
    $probeErr = Join-Path $BuildDir 'build-prerequisite-probe.stderr.txt'
    throw @"
Automatic build prerequisite provisioning completed, but the real compile/link probe still
failed. 

Probe logs:
  $probeLog
  $probeErr
"@
}

function Assert-BundledDriver {
    if (-not (Test-Path -LiteralPath $DriverSource -PathType Leaf)) {
        throw "Bundled known-good TVicPort.sys is missing: $DriverSource"
    }

    $hash = (Get-FileHash -LiteralPath $DriverSource -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $ExpectedTvicSysSha256) {
        throw "Bundled TVicPort.sys SHA-256 mismatch. Expected $ExpectedTvicSysSha256, found $hash."
    }

    return $hash
}

function Publish-PortableRuntime {
    $copies = @(
        [pscustomobject]@{ Source='TPM-Updater.cmd'; Destination='TPM-Updater.cmd' },
        [pscustomobject]@{ Source='TPM-Updater.ps1'; Destination='TPM-Updater.ps1' },
        [pscustomobject]@{ Source='UpdaterCommon.ps1'; Destination='UpdaterCommon.ps1' },
        [pscustomobject]@{ Source='00-PowerShell-Syntax-Check.ps1'; Destination='00-PowerShell-Syntax-Check.ps1' },
        [pscustomobject]@{ Source='VERIFY-PORTABLE.cmd'; Destination='VERIFY-PORTABLE.cmd' },
        [pscustomobject]@{ Source='VERIFY-PORTABLE.ps1'; Destination='VERIFY-PORTABLE.ps1' },
        [pscustomobject]@{ Source='PORTABLE-DIST-README.txt'; Destination='README.txt' },
        [pscustomobject]@{ Source='VERSION.txt'; Destination='VERSION.txt' },
        [pscustomobject]@{ Source='VALIDATION.md'; Destination='VALIDATION.md' },
        [pscustomobject]@{ Source='CHANGELOG-V0.8.md'; Destination='CHANGELOG-V0.8.md' },
        [pscustomobject]@{ Source='Policy\README.txt'; Destination='POLICY-README.txt' },
        [pscustomobject]@{ Source='Infineon-Source-License.txt'; Destination='Infineon-Source-License.txt' },
        [pscustomobject]@{ Source='Firmware\Infineon-5.67-Release-Readme.txt'; Destination='Infineon-5.67-Release-Readme.txt' },
        [pscustomobject]@{ Source='Firmware\License_FW_Images.pdf'; Destination='License_FW_Images.pdf' }
    )

    $firmwareImages = @(
        Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'Firmware') -Filter '*.BIN' -File |
            Sort-Object Name
    )
    if ($firmwareImages.Count -ne 12) {
        throw "Expected exactly 12 pinned firmware images, found $($firmwareImages.Count)."
    }
    $copies += @(
        $firmwareImages | ForEach-Object {
            [pscustomobject]@{
                Source = Join-Path 'Firmware' $_.Name
                Destination = $_.Name
            }
        }
    )

    foreach ($copy in $copies) {
        $source = Join-Path $PackageRoot $copy.Source
        $destination = Join-Path $DistDir $copy.Destination
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Portable-runtime source file is missing: $source"
        }
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    @(
        $PackageName
        "Package build ID: $BuildId"
        'Layout: flat portable runtime; paths are relative to this folder'
    ) | Set-Content -LiteralPath (Join-Path $DistDir 'PORTABLE-RUNTIME.txt') -Encoding ASCII
}

function Write-PortableRuntimeManifest {
    $manifest = Join-Path $DistDir 'SHA256SUMS.txt'
    Remove-Item -LiteralPath $manifest -Force -ErrorAction SilentlyContinue
    $lines = @(
        Get-ChildItem -LiteralPath $DistDir -File |
            Sort-Object Name |
            ForEach-Object {
                $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                "$hash *$($_.Name)"
            }
    )
    if ($lines.Count -lt 10) { throw 'Portable-runtime manifest would be unexpectedly small.' }
    $lines | Set-Content -LiteralPath $manifest -Encoding ASCII
}

function Assert-PortableRuntimeComplete {
    $subdirectories = @(Get-ChildItem -LiteralPath $DistDir -Directory -ErrorAction Stop)
    if ($subdirectories.Count -ne 0) {
        throw "Portable dist must be flat but contains subdirectories: $($subdirectories.Name -join ', ')"
    }

    $required = @(
        'TPM-Updater.exe',
        'TPMFactoryUpd-Direct-Win11-x64.exe',
        'TVicPort.sys'
    ) + @(
        Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'Firmware') -Filter '*.BIN' -File |
            Sort-Object Name |
            ForEach-Object { $_.Name }
    ) + @(
        'TPM-Updater.cmd',
        'TPM-Updater.ps1',
        'UpdaterCommon.ps1',
        '00-PowerShell-Syntax-Check.ps1',
        'VERIFY-PORTABLE.cmd',
        'VERIFY-PORTABLE.ps1',
        'PORTABLE-RUNTIME.txt',
        'BUILD-INFO.txt',
        'SHA256SUMS.txt'
    )
    foreach ($name in $required) {
        $path = Join-Path $DistDir $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Portable dist is incomplete; missing $name"
        }
    }

    & (Join-Path $DistDir 'VERIFY-PORTABLE.ps1')
}

function Invoke-RealBuild {
    param([Parameter(Mandatory)][string]$InstallationPath)

    Write-Section 'BUILD TPMFACTORYUPD DIRECT WINDOWS 11 X64'

    $vsdev = Join-Path $InstallationPath 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $BuildRsp -PathType Leaf)) {
        throw "Missing compiler response file: $BuildRsp"
    }
    if (-not (Test-Path -LiteralPath $LinkRsp -PathType Leaf)) {
        throw "Missing linker response file: $LinkRsp"
    }
    if (-not (Test-Path -LiteralPath $LauncherSource -PathType Leaf)) {
        throw "Missing console-application launcher source: $LauncherSource"
    }

    Remove-Item -LiteralPath $BuildDir,$DistDir -Recurse -Force -ErrorAction SilentlyContinue
    Ensure-Directory $BuildDir
    Ensure-Directory $DistDir
    Ensure-Directory $LogDir

    $buildCmd = Join-Path $BuildDir 'compile-updater.cmd'
    $stdout = Join-Path $LogDir ('build-{0}.stdout.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $stderr = $stdout + '.stderr'

    @"
@echo off
cd /d "$PackageRoot"
call "$vsdev" -no_logo -arch=x64 -host_arch=x64 >nul
if errorlevel 1 exit /b 101
where cl.exe >nul 2>&1
if errorlevel 1 exit /b 102
where link.exe >nul 2>&1
if errorlevel 1 exit /b 103
cl.exe @build-msvc.rsp
set "CLRC=%ERRORLEVEL%"
if not "%CLRC%"=="0" exit /b 104

link.exe @link-msvc.rsp
set "LINKRC=%ERRORLEVEL%"
if not "%LINKRC%"=="0" exit /b 106

if not exist "dist\TPMFactoryUpd-Direct-Win11-x64.exe" exit /b 105

cl.exe /nologo /c /O2 /W4 /MT /DUNICODE /D_UNICODE /Fo"build\TPM-Updater-Launcher.obj" "Source\Launcher\TPM-Updater-Launcher.c"
set "LAUNCHCLRC=%ERRORLEVEL%"
if not "%LAUNCHCLRC%"=="0" exit /b 107

link.exe /nologo /OUT:"dist\TPM-Updater.exe" /SUBSYSTEM:CONSOLE /MANIFEST:EMBED /MANIFESTUAC:"level='requireAdministrator' uiAccess='false'" "build\TPM-Updater-Launcher.obj" kernel32.lib
set "LAUNCHLINKRC=%ERRORLEVEL%"
if not "%LAUNCHLINKRC%"=="0" exit /b 108

if not exist "dist\TPM-Updater.exe" exit /b 109

mt.exe -nologo -inputresource:"dist\TPM-Updater.exe";#1 -out:"build\TPM-Updater.embedded.manifest"
if errorlevel 1 exit /b 110
findstr.exe /c:"requireAdministrator" "build\TPM-Updater.embedded.manifest" >nul
if errorlevel 1 exit /b 111
exit /b 0
"@ | Set-Content -LiteralPath $buildCmd -Encoding ASCII

    Write-Host "Building with:`n  $InstallationPath" -ForegroundColor Cyan
    $buildRun = Invoke-BoundedBuildProcess `
        -FilePath $env:ComSpec `
        -Arguments @('/d','/c',"`"$buildCmd`"") `
        -TimeoutSeconds 300 `
        -StdOutPath $stdout `
        -StdErrPath $stderr `
        -WorkingDirectory $PackageRoot

    if ($buildRun.TimedOut) {
        Write-Host ''
        if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout }
        if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr }
        throw "TPMFactoryUpd Windows build exceeded 300 seconds and was terminated. "
    }

    $compilerText = ''
    if (Test-Path -LiteralPath $stdout) { $compilerText += (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) }
    if (Test-Path -LiteralPath $stderr) { $compilerText += "`r`n" + (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) }
    $compilerErrors = @($compilerText -split "`r?`n" | Where-Object { $_ -match '(?i)\b(?:fatal\s+)?error\s+C\d{4}\b' -or $_ -match '(?i)\b(?:fatal\s+)?error\s+LNK\d{4}\b' -or $_ -match '(?i)\bLNK\d{4}\b' })
    if ($compilerErrors.Count -gt 0) {
        Write-Host ''
        Write-Host 'MSVC reported compiler/linker errors:' -ForegroundColor Red
        $compilerErrors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        throw "MSVC emitted $($compilerErrors.Count) compiler/linker error diagnostic(s). Full build logs: $stdout and $stderr"
    }

    $exeExists = Test-Path -LiteralPath $ExePath -PathType Leaf
    if ($buildRun.ExitCode -ne 0 -or -not $exeExists) {
        Write-Host ''
        if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout }
        if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr }

        if ($buildRun.ExitCode -eq 0 -and -not $exeExists) {
            throw "TPMFactoryUpd Windows build did not create the expected executable even though cmd.exe returned exit code 0. "
        }

        $meaning = switch ([int]$buildRun.ExitCode) {
            101 { 'VsDevCmd initialization failed' }
            102 { 'cl.exe was not found after VsDevCmd' }
            103 { 'link.exe was not found after VsDevCmd' }
            104 { 'cl.exe returned a compilation failure' }
            105 { 'build stages returned success but the expected executable was not created' }
            106 { 'link.exe returned a linker failure' }
            107 { 'the TPM-Updater.exe launcher compilation failed' }
            108 { 'the TPM-Updater.exe launcher link failed' }
            109 { 'the launcher stages succeeded but TPM-Updater.exe was not created' }
            110 { 'the embedded launcher manifest could not be extracted' }
            111 { 'the launcher manifest does not require administrator elevation' }
            default { 'compiler/linker wrapper failure' }
        }
        throw "TPMFactoryUpd Windows build failed with exit code $($buildRun.ExitCode) ($meaning). "
    }

    Write-Host 'TPMFactoryUpd and the elevated TPM-Updater.exe console application compiled and linked successfully.' -ForegroundColor Green

    $driverHash = Assert-BundledDriver
    Copy-Item -LiteralPath $DriverSource -Destination $DriverDist -Force
    $copiedDriverHash = (Get-FileHash -LiteralPath $DriverDist -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($copiedDriverHash -ne $ExpectedTvicSysSha256) {
        throw "Copied TVicPort.sys failed SHA-256 verification."
    }
    Write-Host "Exact known-good TVicPort.sys copied beside the updater." -ForegroundColor Green

    $smoke = Join-Path $DistDir 'build-smoke.txt'
    $smokeErr = Join-Path $DistDir 'build-smoke.stderr.txt'
    $smokeRun = Invoke-BoundedBuildProcess `
        -FilePath $ExePath `
        -Arguments @('-help') `
        -TimeoutSeconds 15 `
        -StdOutPath $smoke `
        -StdErrPath $smokeErr `
        -WorkingDirectory $PackageRoot

    if ($smokeRun.TimedOut) {
        throw 'Built executable exceeded 15 seconds during its -help startup test and was terminated.'
    }

    $text = ''
    if (Test-Path -LiteralPath $smoke) { $text += (Get-Content -LiteralPath $smoke -Raw -ErrorAction SilentlyContinue) }
    if (Test-Path -LiteralPath $smokeErr) { $text += (Get-Content -LiteralPath $smokeErr -Raw -ErrorAction SilentlyContinue) }

    if ($smokeRun.ExitCode -ne 0) {
        throw "Built executable failed its -help startup test with exit code $($smokeRun.ExitCode)."
    }
    if ($text -notmatch [regex]::Escape($ExpectedToolVersion)) {
        throw "Built executable did not identify itself as TPMFactoryUpd $ExpectedToolVersion."
    }

    $hash = (Get-FileHash -LiteralPath $ExePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $launcherHash = (Get-FileHash -LiteralPath $LauncherExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $info = @(
        $PackageName,
        "Package build ID: $BuildId",
        "Build UTC: $((Get-Date).ToUniversalTime().ToString('o'))",
        "Visual Studio/Build Tools instance: $InstallationPath",
        "TPMFactoryUpd source version: $ExpectedToolVersion",
        'Executable: TPMFactoryUpd-Direct-Win11-x64.exe',
        "Executable SHA-256: $hash",
        'Launcher executable: TPM-Updater.exe',
        "Launcher SHA-256: $launcherHash",
        'Launcher execution level: requireAdministrator',
        'Launcher subsystem: Windows console application',
        'CRT setting: /MT (static MSVC runtime)',
        'Build target: 64-bit x64 direct-memory/TIS helper matching the proven legacy updater architecture',
        'Build model: CL /c compile stage followed by a separate LINK.EXE stage',
        'Windows libraries: bcrypt.lib, shell32.lib, advapi32.lib',
        'TVicPort.sys: TVicPort.sys',
        "TVicPort.sys SHA-256: $copiedDriverHash",
        'Driver interface: direct CreateService/CreateFile/DeviceIoControl; no DLL/installer/cpd64',
        'Bootstrap model: WinGet is automatically installed/repaired first; fresh Build Tools installs use WinGet'
    )
    $info | Set-Content -LiteralPath (Join-Path $DistDir 'BUILD-INFO.txt') -Encoding UTF8

    Remove-Item -LiteralPath $smoke,$smokeErr,(Join-Path $DistDir 'TPMFactoryUpd-Direct-Win11-x64.map') `
        -Force -ErrorAction SilentlyContinue
    Publish-PortableRuntime
    Write-PortableRuntimeManifest
    Assert-PortableRuntimeComplete

    Write-Host ''
    Write-Host "Build succeeded:`n  $ExePath" -ForegroundColor Green
    Write-Host "SHA-256:`n  $hash" -ForegroundColor Green
    Write-Host "Startup/version smoke test passed: $ExpectedToolVersion" -ForegroundColor Green
    Write-Host "Application launcher SHA-256:`n  $launcherHash" -ForegroundColor Green
    Write-Host "Portable runtime ready; copy or rename this folder:`n  $DistDir" -ForegroundColor Green
}


Assert-Host
Assert-BundledDriver | Out-Null
& (Join-Path $PackageRoot 'Tests\Authorization-Gates.Tests.ps1')
[string]$winget = [string](Ensure-WinGet)
[string]$vsPath = [string](Ensure-BuildEnvironment -WingetPath $winget)
Invoke-RealBuild -InstallationPath $vsPath
return
