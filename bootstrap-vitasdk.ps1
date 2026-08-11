param(
    [string]$InstallDirectory = $(if ($env:VITASDK) { $env:VITASDK } else { "C:\vitasdk" }),
    [string]$Url = $env:VITASDK_BOOTSTRAP_URL,
    [string]$Sha256 = $env:VITASDK_BOOTSTRAP_SHA256,
    [string]$ArchivePath = $env:VITASDK_BOOTSTRAP_ARCHIVE,
    [string]$Channel = $(if ($env:VITASDK_CHANNEL) { $env:VITASDK_CHANNEL } else { "stable" })
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not [IO.Path]::IsPathFullyQualified($InstallDirectory)) {
    throw "VitaSDK install directory must be absolute"
}
if (Test-Path $InstallDirectory) {
    throw "VitaSDK install directory already exists: ${InstallDirectory}"
}

if ($ArchivePath -and -not $Sha256 -and (Test-Path "${ArchivePath}.sha256")) {
    $Sha256 = (Get-Content "${ArchivePath}.sha256" -Raw).Trim().Split()[0]
}

if (-not $ArchivePath -and (-not $Url -or -not $Sha256)) {
    $hostArchitecture = "x86_64-w64-mingw32"
    Write-Host "Detecting VitaSDK bootstrap archive for $hostArchitecture..."
    
    $manifestBase = if ($env:VITASDK_CHANNEL_BASE_URL) { $env:VITASDK_CHANNEL_BASE_URL } else { "https://vitasdk.github.io/channels" }
    $manifestUrl = "$manifestBase/$Channel.json"
    $manifestJson = $null
    try {
        $manifestJson = (Invoke-RestMethod -Uri $manifestUrl -Method Get -TimeoutSec 10)
    }
    catch {
        if ($Channel -eq "stable") {
            try {
                $manifestJson = (Invoke-RestMethod -Uri "$manifestBase/nightly.json" -Method Get -TimeoutSec 10)
            }
            catch {}
        }
    }
    
    if ($manifestJson -and $manifestJson.core -and $manifestJson.core.release) {
        $releaseTag = $manifestJson.core.release
        if (-not $Url) {
            $Url = "https://github.com/vitasdk/autobuilds/releases/download/$releaseTag/vitasdk-bootstrap-$hostArchitecture.tar.bz2"
        }
    }
    
    if (-not $Url) {
        try {
            $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/vitasdk/autobuilds/releases" -Method Get -TimeoutSec 10
            foreach ($rel in $releases) {
                foreach ($asset in $rel.assets) {
                    if ($asset.name -eq "vitasdk-bootstrap-$hostArchitecture.tar.bz2") {
                        $Url = $asset.browser_download_url
                        break
                    }
                }
                if ($Url) { break }
            }
        }
        catch {}
    }
    
    if (-not $Url) {
        throw "Could not automatically resolve VitaSDK bootstrap archive for $hostArchitecture. Please supply -Url and -Sha256."
    }
    
    if (-not $Sha256) {
        try {
            $sidecarContent = (Invoke-RestMethod -Uri "${Url}.sha256" -Method Get -TimeoutSec 10)
            if ($sidecarContent) {
                $Sha256 = ($sidecarContent -split '\s+')[0].Trim()
            }
        }
        catch {
            throw "Could not retrieve checksum from ${Url}.sha256. Please supply -Sha256 explicitly."
        }
    }
}

if ($Sha256) {
    $Sha256 = $Sha256.ToLowerInvariant()
}
if ($Sha256 -notmatch '^[0-9a-f]{64}$') {
    throw "VITASDK_BOOTSTRAP_SHA256 must contain the immutable archive hash"
}
if ($ArchivePath) {
    if (-not (Test-Path -PathType Leaf $ArchivePath)) {
        throw "local bootstrap archive is not a regular file: ${ArchivePath}"
    }
}
elseif (-not $Url) {
    throw "VITASDK_BOOTSTRAP_URL must select an immutable SDK archive"
}

$parent = Split-Path -Parent $InstallDirectory
if (-not $parent) { throw "VitaSDK install directory has no parent" }
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$temporaryDirectory = Join-Path $parent (".vitasdk-bootstrap-" + [guid]::NewGuid())
$downloadedArchive = Join-Path $temporaryDirectory "vitasdk.tar.bz2"
$stagingDirectory = Join-Path $temporaryDirectory "root"
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

try {
    if ($ArchivePath) {
        Copy-Item $ArchivePath $downloadedArchive
    }
    else {
        Invoke-WebRequest -Uri $Url -OutFile $downloadedArchive
    }
    $actual = (Get-FileHash -Algorithm SHA256 $downloadedArchive).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256) { throw "VitaSDK bootstrap archive hash mismatch" }

    $entries = @(& tar.exe -tjf $downloadedArchive)
    if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) {
        throw "VitaSDK bootstrap archive cannot be listed"
    }
    $topLevel = $null
    foreach ($entry in $entries) {
        if ($entry.StartsWith('/') -or "/${entry}/".Contains('/../')) {
            throw "unsafe path in VitaSDK bootstrap archive: ${entry}"
        }
        $component = ($entry -split '/')[0]
        if (-not $component -or $component -eq '.' -or $component -eq '..') {
            throw "invalid top-level archive path"
        }
        if ($null -eq $topLevel) { $topLevel = $component }
        elseif ($component -ne $topLevel) {
            throw "VitaSDK archive must contain one top-level directory"
        }
    }

    New-Item -ItemType Directory -Path $stagingDirectory | Out-Null
    & tar.exe -xjf $downloadedArchive -C $stagingDirectory --strip-components=1
    if ($LASTEXITCODE -ne 0) { throw "VitaSDK bootstrap archive extraction failed" }

    $stagingPrefix = [IO.Path]::GetFullPath($stagingDirectory) + [IO.Path]::DirectorySeparatorChar
    Get-ChildItem -Recurse -Force $stagingDirectory -Attributes ReparsePoint |
        ForEach-Object {
            $target = $_.Target
            if (-not $target -or [IO.Path]::IsPathFullyQualified($target)) {
                throw "VitaSDK bootstrap archive contains an unsafe link: $($_.FullName)"
            }
            $resolved = [IO.Path]::GetFullPath((Join-Path $_.DirectoryName $target))
            if (-not $resolved.StartsWith($stagingPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "VitaSDK bootstrap archive contains an escaping link: $($_.FullName)"
            }
        }

    $required = @(
        "bin/vdpm.exe",
        "bin/arm-vita-eabi-gcc.exe",
        "usr/bin/pacman.exe",
        "usr/bin/msys-2.0.dll",
        "etc/pacman.conf",
        "version_info.txt"
    )
    foreach ($relativePath in $required) {
        $path = Join-Path $stagingDirectory $relativePath
        if (-not (Test-Path -PathType Leaf $path)) {
            throw "VitaSDK bootstrap archive is missing ${relativePath}"
        }
    }
    & (Join-Path $stagingDirectory "bin/vdpm.exe") --help | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "vdpm bootstrap self-test failed" }
    & (Join-Path $stagingDirectory "usr/bin/pacman.exe") --version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Pacman bootstrap self-test failed" }

    Move-Item $stagingDirectory $InstallDirectory
    Write-Host "VitaSDK installed at ${InstallDirectory}"
    Write-Host "Set VITASDK=${InstallDirectory} and prepend `%VITASDK`%\bin to PATH."
}
finally {
    if (Test-Path $temporaryDirectory) {
        Remove-Item -Recurse -Force $temporaryDirectory
    }
}
