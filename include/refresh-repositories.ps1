param(
    # Not a fixed list: a release series is a channel, so 2026.09 has to be
    # sayable. Still checked, because the name goes into a URL and a path.
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$Channel = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# No default. Refresh is what moves somebody between series, and the name
# this used to assume -- stable -- is not a series: it 404s. vdpm refuses
# without one, and so does this, for whoever runs it by hand. A parameter
# default skips ValidatePattern, which is why the check is here.
if (-not $Channel) {
    throw 'refresh requires a series; run `vdpm channels` to see them'
}

function Require-RegularFile([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "${Description}: ${Path}"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "${Description} is a reparse point: ${Path}"
    }
}

function Invoke-ChannelTool([string[]]$Arguments, [switch]$Capture) {
    if ($Capture) {
        $output = @(& $script:ChannelTool @Arguments)
        if ($LASTEXITCODE -ne 0) {
            throw "vdpm-channel exited with status ${LASTEXITCODE}"
        }
        return (($output -join "`n").Trim())
    }
    & $script:ChannelTool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "vdpm-channel exited with status ${LASTEXITCODE}"
    }
}

function Download-File([string]$Uri, [string]$Destination) {
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
}

function Copy-Database([string]$Uri, [string]$Name, [string]$Destination) {
    if ($env:VITASDK_CHANNEL_ASSET_DIRECTORY) {
        $source = Join-Path $env:VITASDK_CHANNEL_ASSET_DIRECTORY $Name
        Require-RegularFile $source "channel database is not available"
        Copy-Item -LiteralPath $source -Destination $Destination
    }
    else {
        Download-File $Uri $Destination
    }
}

function Install-File([string]$Source, [string]$Destination) {
    $temporary = "${Destination}.vdpm-$PID"
    try {
        Copy-Item -LiteralPath $Source -Destination $temporary -Force
        Move-Item -LiteralPath $temporary -Destination $Destination -Force
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

$sdkRoot = $env:VITASDK
if ([string]::IsNullOrWhiteSpace($sdkRoot) -or
    -not [IO.Path]::IsPathRooted($sdkRoot)) {
    throw "VITASDK must be an absolute, non-root path"
}
$sdkRoot = [IO.Path]::GetFullPath($sdkRoot).TrimEnd('\', '/')
$pathRoot = [IO.Path]::GetPathRoot($sdkRoot).TrimEnd('\', '/')
if ($sdkRoot -eq $pathRoot) {
    throw "VITASDK must be an absolute, non-root path"
}

$hostTriplet = "x86_64-w64-mingw32"
$publicKey = $env:VITASDK_CHANNEL_PUBLIC_KEY
if ([string]::IsNullOrWhiteSpace($publicKey)) {
    $publicKey = Join-Path $sdkRoot "share/vdpm/channel-public-key.pem"
}
$script:ChannelTool = $env:VDPM_CHANNEL_TOOL
if ([string]::IsNullOrWhiteSpace($script:ChannelTool)) {
    $script:ChannelTool = Join-Path $sdkRoot "share/vdpm/msys/usr/bin/vdpm-channel.exe"
}
Require-RegularFile $publicKey "channel public key is not installed"
Require-RegularFile $script:ChannelTool "channel helper is not installed"

$databaseRoot = Join-Path $sdkRoot "var/lib/pacman"
if (Test-Path -LiteralPath (Join-Path $databaseRoot "db.lck")) {
    throw "pacman database is locked; repository refresh refused"
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("vdpm-refresh-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
    $manifest = Join-Path $temporaryRoot "channel.json"
    $signature = Join-Path $temporaryRoot "channel.json.sig"
    if ($env:VITASDK_CHANNEL_MANIFEST) {
        Require-RegularFile $env:VITASDK_CHANNEL_MANIFEST "channel manifest is not available"
        Require-RegularFile ($env:VITASDK_CHANNEL_MANIFEST + ".sig") "channel signature is not available"
        Copy-Item -LiteralPath $env:VITASDK_CHANNEL_MANIFEST -Destination $manifest
        Copy-Item -LiteralPath ($env:VITASDK_CHANNEL_MANIFEST + ".sig") -Destination $signature
    }
    else {
        $baseUrl = $env:VITASDK_CHANNEL_BASE_URL
        if ([string]::IsNullOrWhiteSpace($baseUrl)) {
            $baseUrl = "https://vitasdk.org/channels"
        }
        $baseUrl = $baseUrl.TrimEnd('/')
        Download-File "${baseUrl}/${Channel}.json" $manifest
        Download-File "${baseUrl}/${Channel}.json.sig" $signature
    }

    # Authenticate bytes before parsing any manifest-controlled value.
    Invoke-ChannelTool @("verify", $manifest, $signature, $publicKey)
    Invoke-ChannelTool @("validate", $manifest, $Channel, $hostTriplet)
    function Manifest-Field([string]$Name) {
        Invoke-ChannelTool @("field", $manifest, $Channel, $hostTriplet, $Name) -Capture
    }

    $coreName = Manifest-Field "core.database.name"
    $vitaName = Manifest-Field "packages.database.name"
    $coreDatabase = Join-Path $temporaryRoot $coreName
    $vitaDatabase = Join-Path $temporaryRoot $vitaName
    Copy-Database (Manifest-Field "core.database.url") $coreName $coreDatabase
    Copy-Database (Manifest-Field "packages.database.url") $vitaName $vitaDatabase
    if ((Invoke-ChannelTool @("sha256", $coreDatabase) -Capture) -ne
        (Manifest-Field "core.database.sha256")) {
        throw "core repository database SHA-256 mismatch"
    }
    if ((Invoke-ChannelTool @("sha256", $vitaDatabase) -Capture) -ne
        (Manifest-Field "packages.database.sha256")) {
        throw "package repository database SHA-256 mismatch"
    }

    $configuration = Join-Path $temporaryRoot "pacman.conf"
    $lines = @(
        "[options]",
        "Architecture = $hostTriplet vita",
        "# vdpm verifies signed channel metadata and the selected database hash before use.",
        "SigLevel = Never",
        "[$hostTriplet]",
        "Server = $(Manifest-Field 'core.server')",
        "[vita]",
        "Server = $(Manifest-Field 'packages.server')"
    )
    [IO.File]::WriteAllText($configuration, ($lines -join "`n") + "`n",
        (New-Object Text.UTF8Encoding($false)))

    $syncRoot = Join-Path $databaseRoot "sync"
    $stateRoot = Join-Path $sdkRoot "var/lib/vdpm"
    $configurationRoot = Join-Path $sdkRoot "etc"
    @($syncRoot, $stateRoot, $configurationRoot) | ForEach-Object {
        New-Item -ItemType Directory -Force -Path $_ | Out-Null
    }
    Install-File $coreDatabase (Join-Path $syncRoot "${hostTriplet}.db")
    Install-File $vitaDatabase (Join-Path $syncRoot "vita.db")
    # Staged, not selected: the transaction that moves the toolchain runs
    # after this, and until it succeeds the installation is still on the
    # series whose compiler it actually has.
    Install-File $manifest (Join-Path $stateRoot "channel.json.staged")
    Install-File $configuration (Join-Path $configurationRoot "pacman.conf")
    Write-Host "refreshed $Channel channel sequence $(Manifest-Field 'sequence')"
}
finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
