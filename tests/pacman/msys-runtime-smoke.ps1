param(
    [string]$WorkDirectory = (Join-Path $env:TEMP "vitasdk-msys-pacman-smoke"),
    [string]$FixtureDirectory = (Join-Path $env:TEMP "vitasdk-msys-pacman-fixtures-${PID}"),
    [string]$FixtureTar = "tar.exe",
    [string]$PacmanExecutable = "",
    [string]$RuntimeDll = "",
    [switch]$Extended
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$pacmanUrl = "https://repo.msys2.org/msys/x86_64/pacman-6.1.0-25-x86_64.pkg.tar.zst"
$pacmanSha256 = "cb375279a44b37f646dbe834b440c233fddbacb97d6173e5c7d91362717c970f"
$runtimeUrl = "https://repo.msys2.org/msys/x86_64/msys2-runtime-3.6.10-1-x86_64.pkg.tar.zst"
$runtimeSha256 = "0b68543d295aa52e6c16ede2d7d6113eff9bf8fa4876f140eb624b0cf33e0253"

function Get-MixedPath([string]$Path) {
    return $Path.Replace("\", "/")
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

function Invoke-ExpectedFailure([string]$Program, [string[]]$Arguments, [string]$Description) {
    & $Program @Arguments
    if ($LASTEXITCODE -eq 0) {
        throw "operation unexpectedly succeeded: ${Description}"
    }
    Write-Host "Expected failure passed: ${Description}"
}

function Write-PackageMetadata(
    [string]$Root,
    [string]$Name,
    [string]$Version,
    [string]$Description
) {
    [IO.File]::WriteAllText((Join-Path $Root ".PKGINFO"), (@(
        "pkgname = ${Name}",
        "pkgbase = ${Name}",
        "pkgver = ${Version}",
        "pkgdesc = ${Description}",
        "builddate = 0",
        "packager = VitaSDK CI",
        "size = 4096",
        "arch = x86_64",
        "license = MIT"
    ) -join "`n") + "`n")
}

function New-ProbePackage(
    [string]$Root,
    [string]$Output,
    [string]$Name,
    [string]$Version,
    [System.Collections.IDictionary]$Files
) {
    if (Test-Path $Root) {
        Remove-Item -Recurse -Force $Root
    }
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Write-PackageMetadata $Root $Name $Version "VitaSDK MSYS Windows filesystem probe"

    $archiveEntries = @(".PKGINFO")
    foreach ($entry in ($Files.GetEnumerator() | Sort-Object Key)) {
        $filePath = Join-Path $Root $entry.Key
        New-Item -ItemType Directory -Force -Path (Split-Path $filePath) | Out-Null
        [IO.File]::WriteAllText($filePath, $entry.Value)
        $archiveEntries += $entry.Key
    }

    Invoke-Checked "tar.exe" (@("-cJf", $Output, "-C", $Root) + $archiveEntries)
}

function New-CaseCollisionPackage([string]$Root, [string]$Output, [string]$TarProgram) {
    if (Test-Path $Root) {
        Remove-Item -Recurse -Force $Root
    }
    $upperRoot = Join-Path $Root "upper"
    $lowerRoot = Join-Path $Root "lower"
    New-Item -ItemType Directory -Force -Path $upperRoot, $lowerRoot | Out-Null
    Write-PackageMetadata $Root "vitasdk-msys-case-collision" "1.0-1" `
        "Case-insensitive path collision probe"
    [IO.File]::WriteAllText((Join-Path $upperRoot "Collision.h"), "upper`n")
    [IO.File]::WriteAllText((Join-Path $lowerRoot "collision.h"), "lower`n")

    # The source paths are distinct on Windows. Rewrite them only while adding
    # them to the archive so the payload contains two case-folding equivalents.
    Invoke-Checked $TarProgram @(
        "-cJf", $Output,
        "-s", "|^upper/|arm-vita-eabi/include/case-probe/|",
        "-s", "|^lower/|arm-vita-eabi/include/case-probe/|",
        "-C", $Root,
        ".PKGINFO",
        "upper/Collision.h",
        "lower/collision.h"
    )
}

if (Test-Path $WorkDirectory) {
    Remove-Item -Recurse -Force $WorkDirectory
}
if (Test-Path $FixtureDirectory) {
    Remove-Item -Recurse -Force $FixtureDirectory
}

$downloads = Join-Path $FixtureDirectory "downloads"
$extract = Join-Path $FixtureDirectory "extract"
$sdkRoot = Join-Path $WorkDirectory "sdk"
$pacmanBin = Join-Path $sdkRoot "usr/bin"
$dbPath = Join-Path $sdkRoot "var/lib/pacman"
$cachePath = Join-Path $sdkRoot "var/cache/pacman/pkg"
$logPath = Join-Path $sdkRoot "var/log/pacman.log"
$configPath = Join-Path $sdkRoot "etc/pacman.conf"
$packageRoot = Join-Path $FixtureDirectory "package-v1"
$packagePath = Join-Path $FixtureDirectory "vitasdk-msys-probe-1.0-1-any.pkg.tar.xz"
$packageV2Root = Join-Path $FixtureDirectory "package-v2"
$packageV2Path = Join-Path $FixtureDirectory "vitasdk-msys-probe-2.0-1-any.pkg.tar.xz"
$collisionRoot = Join-Path $FixtureDirectory "case-collision-package"
$collisionPath = Join-Path $FixtureDirectory "vitasdk-msys-case-collision-1.0-1-any.pkg.tar.xz"

@(
    $downloads,
    $extract,
    $FixtureDirectory,
    $pacmanBin,
    $dbPath,
    $cachePath,
    (Split-Path $logPath),
    (Split-Path $configPath)
) | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

if (($PacmanExecutable -eq "") -xor ($RuntimeDll -eq "")) {
    throw "PacmanExecutable and RuntimeDll must be supplied together"
}
if ($PacmanExecutable -ne "") {
    if (-not (Test-Path -PathType Leaf $PacmanExecutable)) {
        throw "built pacman executable is missing: ${PacmanExecutable}"
    }
    if (-not (Test-Path -PathType Leaf $RuntimeDll)) {
        throw "MSYS runtime DLL is missing: ${RuntimeDll}"
    }
    Copy-Item $PacmanExecutable (Join-Path $pacmanBin "pacman.exe")
    Copy-Item $RuntimeDll (Join-Path $pacmanBin "msys-2.0.dll")
}
else {
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
}

$runtimeFiles = @(Get-ChildItem -File $pacmanBin)
if ($runtimeFiles.Count -ne 2) {
    throw "minimal runtime contains unexpected files"
}

[IO.File]::WriteAllText($configPath, (@(
    "[options]",
    "Architecture = x86_64",
    "SigLevel = Never",
    "CheckSpace"
) -join "`n") + "`n")

$probeRelativePath = "arm-vita-eabi/include/msys-probe.h"
$utf8RelativePath = "arm-vita-eabi/include/prueba-ñ-日本語.h"
$replaceRelativePath = "arm-vita-eabi/include/replace-on-upgrade.h"
$removedRelativePath = "arm-vita-eabi/include/remove-on-upgrade.h"
$addedRelativePath = "arm-vita-eabi/include/added-on-upgrade.h"
$longSegments = 1..6 | ForEach-Object {
    "segment-${_}-" + [string]::new([char]120, 24)
}
$longRelativePath = "arm-vita-eabi/include/" + ($longSegments -join "/") + "/long-probe.h"

$packageFiles = [ordered]@{
    $probeRelativePath = "probe`n"
}
if ($Extended) {
    if ((Join-Path $sdkRoot $longRelativePath).Length -le 260) {
        throw "long-path fixture does not exceed the legacy Windows path limit"
    }
    $packageFiles[$utf8RelativePath] = "UTF-8 probe`n"
    $packageFiles[$longRelativePath] = "long path probe`n"
    $packageFiles[$replaceRelativePath] = "version 1`n"
    $packageFiles[$removedRelativePath] = "removed by upgrade`n"
}
New-ProbePackage $packageRoot $packagePath "vitasdk-msys-probe" "1.0-1" $packageFiles

$pacman = Join-Path $pacmanBin "pacman.exe"
$commonArguments = @(
    "--config", (Get-MixedPath $configPath),
    "--root", "$(Get-MixedPath $sdkRoot)/",
    "--dbpath", "$(Get-MixedPath $dbPath)/",
    "--cachedir", "$(Get-MixedPath $cachePath)/",
    "--logfile", (Get-MixedPath $logPath)
)

# Exclude Git for Windows and any preinstalled MSYS2 tree from DLL lookup.
$savedPath = $env:PATH
$env:PATH = "${env:SystemRoot}\System32;${env:SystemRoot}"
try {
    Invoke-Checked $pacman @("--version")
    Invoke-Checked $pacman @(
        $commonArguments + @(
            "--upgrade", "--noscriptlet", "--noconfirm", (Get-MixedPath $packagePath)
        )
    )
    Invoke-Checked $pacman @($commonArguments + @("--query", "vitasdk-msys-probe"))

    $installedFile = Join-Path $sdkRoot $probeRelativePath
    if (-not (Test-Path $installedFile)) {
        throw "package payload was not installed"
    }

    if ($Extended) {
        foreach ($relativePath in @(
            $utf8RelativePath,
            $longRelativePath,
            $replaceRelativePath,
            $removedRelativePath
        )) {
            if (-not (Test-Path (Join-Path $sdkRoot $relativePath))) {
                throw "extended package payload was not installed: ${relativePath}"
            }
        }

        $lockPath = Join-Path $dbPath "db.lck"
        [IO.File]::WriteAllText($lockPath, "locked by VitaSDK smoke test`n")
        try {
            Invoke-ExpectedFailure $pacman ($commonArguments + @(
                "--remove", "--noscriptlet", "--noconfirm", "vitasdk-msys-probe"
            )) "transaction while the SDK database is locked"
            if (-not (Test-Path $installedFile)) {
                throw "locked transaction modified the installed package"
            }
        }
        finally {
            Remove-Item -Force $lockPath
        }

        $packageV2Files = [ordered]@{
            $probeRelativePath = "probe version 2`n"
            $utf8RelativePath = "UTF-8 probe version 2`n"
            $longRelativePath = "long path probe version 2`n"
            $replaceRelativePath = "version 2`n"
            $addedRelativePath = "added by upgrade`n"
        }
        New-ProbePackage $packageV2Root $packageV2Path `
            "vitasdk-msys-probe" "2.0-1" $packageV2Files
        Invoke-Checked $pacman @(
            $commonArguments + @(
                "--upgrade", "--noscriptlet", "--noconfirm", (Get-MixedPath $packageV2Path)
            )
        )
        Invoke-Checked $pacman @($commonArguments + @("--query", "vitasdk-msys-probe"))

        if ([IO.File]::ReadAllText((Join-Path $sdkRoot $replaceRelativePath)) -ne "version 2`n") {
            throw "upgrade did not replace an existing file"
        }
        if (Test-Path (Join-Path $sdkRoot $removedRelativePath)) {
            throw "upgrade did not delete a file removed from the new package"
        }
        if (-not (Test-Path (Join-Path $sdkRoot $addedRelativePath))) {
            throw "upgrade did not install its new file"
        }

        New-CaseCollisionPackage $collisionRoot $collisionPath $FixtureTar
        Invoke-ExpectedFailure $pacman ($commonArguments + @(
            "--upgrade", "--noscriptlet", "--noconfirm", (Get-MixedPath $collisionPath)
        )) "package containing case-insensitive duplicate paths"
    }

    Invoke-Checked $pacman @(
        $commonArguments + @(
            "--remove", "--noscriptlet", "--noconfirm", "vitasdk-msys-probe"
        )
    )
    if (Test-Path $installedFile) {
        throw "package payload remains after removal"
    }
    if ($Extended) {
        foreach ($relativePath in @(
            $utf8RelativePath,
            $longRelativePath,
            $replaceRelativePath,
            $addedRelativePath
        )) {
            if (Test-Path (Join-Path $sdkRoot $relativePath)) {
                throw "extended payload remains after removal: ${relativePath}"
            }
        }
    }
}
finally {
    $env:PATH = $savedPath
}

if ($Extended) {
    Write-Host "MSYS pacman extended Windows filesystem smoke test passed"
}
else {
    Write-Host "MSYS pacman two-file runtime smoke test passed"
}
