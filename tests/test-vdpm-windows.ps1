param(
    [string]$WorkDirectory = (Join-Path $env:TEMP "vitasdk-vdpm-windows")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$pacmanUrl = "https://repo.msys2.org/msys/x86_64/pacman-6.1.0-25-x86_64.pkg.tar.zst"
$pacmanSha256 = "cb375279a44b37f646dbe834b440c233fddbacb97d6173e5c7d91362717c970f"
$runtimeUrl = "https://repo.msys2.org/msys/x86_64/msys2-runtime-3.6.10-1-x86_64.pkg.tar.zst"
$runtimeSha256 = "0b68543d295aa52e6c16ede2d7d6113eff9bf8fa4876f140eb624b0cf33e0253"

function Write-UnixText([string]$Path, [string[]]$Lines) {
    [IO.File]::WriteAllText($Path, ($Lines -join "`n") + "`n")
}

function Assert-Sha256([string]$Path, [string]$Expected) {
    $actual = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
    if ($actual -ne $Expected) {
        throw "SHA-256 mismatch for ${Path}: expected ${Expected}, got ${actual}"
    }
}

function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "${Program} exited with status ${LASTEXITCODE}"
    }
}

if (Test-Path $WorkDirectory) {
    Remove-Item -Recurse -Force $WorkDirectory
}

$repositoryRoot = Split-Path $PSScriptRoot
$downloads = Join-Path $WorkDirectory "downloads"
$extract = Join-Path $WorkDirectory "extract"
$build = Join-Path $WorkDirectory "build"
$sdkRoot = Join-Path $WorkDirectory "sdk"
$sdkBin = Join-Path $sdkRoot "bin"
$pacmanBin = Join-Path $sdkRoot "usr/bin"
$dbPath = Join-Path $sdkRoot "var/lib/pacman"
$syncPath = Join-Path $dbPath "sync"
$cachePath = Join-Path $sdkRoot "var/cache/pacman/pkg"
$configPath = Join-Path $sdkRoot "etc/pacman.conf"
$packageRoot = Join-Path $WorkDirectory "package"
$packageName = "vitasdk-msys-probe"
$packageVersion = "1.0-1"
$packageFileName = "${packageName}-${packageVersion}-x86_64.pkg.tar.xz"
$packagePath = Join-Path $WorkDirectory $packageFileName
$databaseRoot = Join-Path $WorkDirectory "database"
$databaseEntry = Join-Path $databaseRoot "${packageName}-${packageVersion}"

@(
    $downloads,
    $extract,
    $sdkBin,
    $pacmanBin,
    $syncPath,
    $cachePath,
    (Split-Path $configPath),
    (Join-Path $packageRoot "arm-vita-eabi/include"),
    $databaseEntry
) | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

$pacmanArchive = Join-Path $downloads "pacman.pkg.tar.zst"
$runtimeArchive = Join-Path $downloads "runtime.pkg.tar.zst"
Invoke-WebRequest -Uri $pacmanUrl -OutFile $pacmanArchive
Invoke-WebRequest -Uri $runtimeUrl -OutFile $runtimeArchive
Assert-Sha256 $pacmanArchive $pacmanSha256
Assert-Sha256 $runtimeArchive $runtimeSha256

Invoke-Checked "tar.exe" @(
    "-xf", $pacmanArchive, "-C", $extract, "usr/bin/pacman.exe"
)
Invoke-Checked "tar.exe" @(
    "-xf", $runtimeArchive, "-C", $extract, "usr/bin/msys-2.0.dll"
)
Copy-Item (Join-Path $extract "usr/bin/pacman.exe") $pacmanBin
Copy-Item (Join-Path $extract "usr/bin/msys-2.0.dll") $pacmanBin

Invoke-Checked "cmake.exe" @(
    "-S", (Join-Path $repositoryRoot "src"),
    "-B", $build,
    "-DBUILD_VDPM_CHANNEL=OFF",
    "-DBUILD_VDPM_FRONTEND=ON",
    "-A", "x64"
)
Invoke-Checked "cmake.exe" @("--build", $build, "--config", "Release")
Copy-Item (Join-Path $build "Release/vdpm.exe") $sdkBin

Write-UnixText $configPath @(
    "[options]",
    "Architecture = x86_64",
    "SigLevel = Never",
    "CheckSpace",
    "[probe]",
    "Server = file:///unused"
)
Write-UnixText (Join-Path $packageRoot ".PKGINFO") @(
    "pkgname = ${packageName}",
    "pkgbase = ${packageName}",
    "pkgver = ${packageVersion}",
    "pkgdesc = VitaSDK native vdpm Windows probe",
    "builddate = 0",
    "packager = VitaSDK CI",
    "size = 6",
    "arch = x86_64",
    "license = MIT"
)
Write-UnixText (Join-Path $packageRoot "arm-vita-eabi/include/msys-probe.h") @(
    "probe"
)
Invoke-Checked "tar.exe" @(
    "-cJf", $packagePath,
    "-C", $packageRoot,
    ".PKGINFO", "arm-vita-eabi/include/msys-probe.h"
)

$packageSize = (Get-Item $packagePath).Length
$packageHash = (Get-FileHash -Algorithm SHA256 -Path $packagePath).Hash.ToLowerInvariant()
Write-UnixText (Join-Path $databaseEntry "desc") @(
    "%FILENAME%", $packageFileName, "",
    "%NAME%", $packageName, "",
    "%BASE%", $packageName, "",
    "%VERSION%", $packageVersion, "",
    "%DESC%", "VitaSDK native vdpm Windows probe", "",
    "%CSIZE%", "${packageSize}", "",
    "%ISIZE%", "6", "",
    "%SHA256SUM%", $packageHash, "",
    "%ARCH%", "x86_64", "",
    "%BUILDDATE%", "0", "",
    "%PACKAGER%", "VitaSDK CI"
)
Invoke-Checked "tar.exe" @(
    "-czf", (Join-Path $syncPath "probe.db"),
    "-C", $databaseRoot,
    "${packageName}-${packageVersion}/desc"
)
Copy-Item $packagePath $cachePath

$vdpm = Join-Path $sdkBin "vdpm.exe"
$savedPath = $env:PATH
$savedSdk = $env:VITASDK
$savedNonInteractive = $env:VDPM_NONINTERACTIVE
$env:PATH = "${env:SystemRoot}\System32;${env:SystemRoot}"
$env:VITASDK = $sdkRoot
$env:VDPM_NONINTERACTIVE = "1"
try {
    # The bare package form is the historical `vdpm PACKAGE...` interface.
    Invoke-Checked $vdpm @($packageName)
    Invoke-Checked $vdpm @("list", $packageName)

    $installedFile = Join-Path $sdkRoot "arm-vita-eabi/include/msys-probe.h"
    if (-not (Test-Path $installedFile)) {
        throw "vdpm did not install the package payload"
    }

    # `-u` is the historical removal interface.
    Invoke-Checked $vdpm @("-u", $packageName)
    if (Test-Path $installedFile) {
        throw "vdpm left the package payload after removal"
    }
}
finally {
    $env:PATH = $savedPath
    $env:VITASDK = $savedSdk
    $env:VDPM_NONINTERACTIVE = $savedNonInteractive
}

Write-Host "native vdpm -> minimal MSYS pacman Windows test passed"
