param(
    [string]$InstallDirectory = $(if ($env:VITASDK) { $env:VITASDK } else { "C:\vitasdk" }),
    [string]$Url = $env:VITASDK_BOOTSTRAP_URL,
    [string]$Sha256 = $env:VITASDK_BOOTSTRAP_SHA256,
    [string]$ArchivePath = $env:VITASDK_BOOTSTRAP_ARCHIVE,
    [string]$Channel = $env:VITASDK_CHANNEL
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not [IO.Path]::IsPathFullyQualified($InstallDirectory)) {
    throw "VitaSDK install directory must be absolute"
}
if (Test-Path $InstallDirectory) {
    throw "VitaSDK install directory already exists: ${InstallDirectory}"
}

# The root of trust is this script. It names the seed to fetch and the digest
# of the channel key that seed must contain; the index, the manifest, the
# databases and the packages are all verified with that key afterwards.
$SeedRelease = 'v0.1.1'
$SeedVersion = '0.1.1'
$ChannelKeySha256 = 'c02df2e12216f6f633d94206634bbe8f244d74f610b29e922d7ea8bab2efb307'
$installFromPackages = $false

if ($ArchivePath -and -not $Sha256 -and (Test-Path "${ArchivePath}.sha256")) {
    $Sha256 = (Get-Content "${ArchivePath}.sha256" -Raw).Trim().Split()[0]
}

if (-not $ArchivePath -and (-not $Url -or -not $Sha256)) {
    $hostArchitecture = "x86_64-w64-mingw32"
    Write-Host "Detecting VitaSDK bootstrap archive for $hostArchitecture..."
    
    $manifestBase = if ($env:VITASDK_CHANNEL_BASE_URL) { $env:VITASDK_CHANNEL_BASE_URL } else { "https://vitasdk.org/channels" }

    # Nothing requested, or the `stable` alias: the index says which series is
    # supported today. `stable` is not a channel and never was one -- there is
    # no stable.json to fetch -- so it is resolved here and never stored, the
    # way `latest` names a Docker image without being one.
    if (-not $Channel -or $Channel -eq "stable") {
        try {
            $index = Invoke-RestMethod -Uri "$manifestBase/index.json" -Method Get -TimeoutSec 10
        }
        catch {
            throw "Could not read the release index at $manifestBase/index.json"
        }
        # Series are named YYYY.MM, so the newest one is the highest year and
        # then the highest month.
        $Channel = $index.channels.PSObject.Properties |
            Where-Object { $_.Value.status -eq "supported" } |
            Sort-Object { [int]($_.Name -split '\.')[0] }, { [int]($_.Name -split '\.')[1] } -Descending |
            Select-Object -First 1 -ExpandProperty Name
        if (-not $Channel) {
            throw "The release index at $manifestBase lists no supported series"
        }
        Write-Host "Installing the supported series $Channel"
    }

    # No fallback to anything else. Installing a series nobody asked for -- as
    # resolving `stable` to the nightly used to do -- hands somebody the
    # development channel while they believe they asked for the stable one.
    try {
        $manifestJson = Invoke-RestMethod -Uri "$manifestBase/$Channel.json" -Method Get -TimeoutSec 10
    }
    catch {
        throw "Could not read the $Channel manifest at $manifestBase/$Channel.json"
    }
    if (-not ($manifestJson.core -and $manifestJson.core.release)) {
        throw "The $Channel manifest names no core release"
    }
    if (-not $Url) {
        # The seed is the client and nothing else: it can verify a channel and
        # drive pacman, and the toolchain arrives as the package it is, so the
        # installation is one pacman knows about and can move later.
        $installFromPackages = $true
        $Url = "https://github.com/vitasdk/vdpm/releases/download/$SeedRelease/vdpm-$SeedVersion-$hostArchitecture.tar.bz2"
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

    $required = if ($installFromPackages) {
        @(
            "bin/vdpm.exe",
            "usr/bin/pacman.exe",
            "usr/bin/vdpm-channel.exe",
            "usr/bin/msys-2.0.dll",
            "share/vdpm/channel-public-key.pem"
        )
    } else {
        @(
            "bin/vdpm.exe",
            "bin/arm-vita-eabi-gcc.exe",
            "usr/bin/pacman.exe",
            "usr/bin/msys-2.0.dll",
            "etc/pacman.conf",
            "version_info.txt"
        )
    }
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

    if ($installFromPackages) {
        # The one thing this script decides on its own. Everything the seed
        # goes on to verify hangs off this key, so a seed carrying another one
        # is a seed that could accept another channel.
        $keyPath = Join-Path $stagingDirectory "share/vdpm/channel-public-key.pem"
        $keyDigest = (Get-FileHash -Algorithm SHA256 $keyPath).Hash.ToLowerInvariant()
        if ($keyDigest -ne $ChannelKeySha256) {
            throw "the client seed carries an unexpected channel key"
        }

        # Selecting the series writes the verified databases, and installing
        # the toolchain from them is what makes this an installation pacman
        # knows about: it can be upgraded, moved to another series, and asked
        # what it is.
        $env:VITASDK = $stagingDirectory
        & (Join-Path $stagingDirectory "bin/vdpm.exe") refresh $Channel
        if ($LASTEXITCODE -ne 0) { throw "could not select the $Channel series" }

        $pacman = Join-Path $stagingDirectory "usr/bin/pacman.exe"
        $configuration = Join-Path $stagingDirectory "etc/pacman.conf"
        New-Item -ItemType Directory -Force -Path `
            (Join-Path $stagingDirectory "var/cache/pacman/pkg"), `
            (Join-Path $stagingDirectory "var/log") | Out-Null
        # A core that still ships a default pacman.conf would put it back over
        # the one refresh just wrote, and with it the series this installation
        # is on. The selection belongs to the installation, not to the package.
        Copy-Item $configuration "${configuration}.selected"
        # The seed put the client on disk before pacman existed to record it,
        # so the package that owns those files takes them over here. Scoped to
        # the seed, and only ever in this empty staging directory.
        & $pacman --config $configuration --root $stagingDirectory `
            --dbpath (Join-Path $stagingDirectory "var/lib/pacman") `
            --cachedir (Join-Path $stagingDirectory "var/cache/pacman/pkg") `
            --logfile (Join-Path $stagingDirectory "var/log/pacman.log") `
            --noconfirm --noscriptlet --sync vitasdk-core `
            --overwrite '*/bin/vdpm*' --overwrite '*/usr/bin/*' `
            --overwrite '*/share/vdpm/*' --overwrite '*/etc/pacman.conf'
        if ($LASTEXITCODE -ne 0) { throw "could not install the toolchain" }
        Move-Item -Force "${configuration}.selected" $configuration
        $Channel = ''
    }

    Move-Item $stagingDirectory $InstallDirectory
    Write-Host "VitaSDK installed at ${InstallDirectory}"

    # The series has to be written into the SDK, not merely used to pick an
    # archive and then forgotten. Without this the new SDK has no repositories
    # at all and its series is decided by whatever is typed next, so a core
    # installed from one series can end up refreshed onto another with nothing
    # objecting.
    if ($Channel) {
        $env:VITASDK = $InstallDirectory
        & (Join-Path $InstallDirectory "bin/vdpm.exe") refresh $Channel
        if ($LASTEXITCODE -ne 0) {
            throw "The SDK is installed at ${InstallDirectory} but no series is selected. Run: vdpm refresh ${Channel}"
        }
    }

    Write-Host "Set VITASDK=${InstallDirectory} and prepend `%VITASDK`%\bin to PATH."
}
finally {
    if (Test-Path $temporaryDirectory) {
        Remove-Item -Recurse -Force $temporaryDirectory
    }
}
