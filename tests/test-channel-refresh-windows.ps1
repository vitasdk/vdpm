param(
    [Parameter(Mandatory = $true)]
    [string]$ProductRoot,
    [Parameter(Mandatory = $true)]
    [string]$OpenSslExecutable,
    [string]$WorkDirectory = (Join-Path $env:TEMP "vdpm-channel-refresh")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "${Program} exited with status ${LASTEXITCODE}"
    }
}

function Write-Utf8([string]$Path, [string]$Value) {
    [IO.File]::WriteAllText($Path, $Value, (New-Object Text.UTF8Encoding($false)))
}

if (Test-Path -LiteralPath $WorkDirectory) {
    Remove-Item -LiteralPath $WorkDirectory -Recurse -Force
}
$sdkRoot = Join-Path $WorkDirectory "VitaSDK ñ 日本語"
$fixtureRoot = Join-Path $WorkDirectory "channel fixture"
$assetRoot = Join-Path $fixtureRoot "assets"
New-Item -ItemType Directory -Force -Path $sdkRoot, $assetRoot | Out-Null
Copy-Item -Path (Join-Path $ProductRoot "*") -Destination $sdkRoot -Recurse

$hostTriplet = "x86_64-w64-mingw32"
$coreName = "${hostTriplet}.db"
$vitaName = "vita.db"
$coreDatabase = Join-Path $assetRoot $coreName
$vitaDatabase = Join-Path $assetRoot $vitaName
Write-Utf8 $coreDatabase "signed core database`n"
Write-Utf8 $vitaDatabase "signed package database`n"
$coreDigest = (Get-FileHash -Algorithm SHA256 $coreDatabase).Hash.ToLowerInvariant()
$vitaDigest = (Get-FileHash -Algorithm SHA256 $vitaDatabase).Hash.ToLowerInvariant()

$manifest = Join-Path $fixtureRoot "nightly.json"
$manifestBody = '{"channel":"nightly","core":{"architectures":{"' +
    $hostTriplet + '":{"database":{"name":"' + $coreName +
    '","sha256":"' + $coreDigest +
    '"}}},"release":"sdk-snapshot-1","repository":"vitasdk/autobuilds"},' +
    '"packages":{"database":{"name":"vita.db","sha256":"' + $vitaDigest +
    '"},"release":"packages-snapshot-1","repository":"vitasdk/packages"},' +
    '"schema_version":1,"sequence":7}' + "`n"
Write-Utf8 $manifest $manifestBody

$privateKey = Join-Path $fixtureRoot "private.pem"
$publicKey = Join-Path $fixtureRoot "public.pem"
Invoke-Checked $OpenSslExecutable @("genpkey", "-algorithm", "ED25519", "-out", $privateKey)
Invoke-Checked $OpenSslExecutable @("pkey", "-in", $privateKey, "-pubout", "-out", $publicKey)
Invoke-Checked $OpenSslExecutable @(
    "pkeyutl", "-sign", "-inkey", $privateKey, "-rawin",
    "-in", $manifest, "-out", ($manifest + ".sig")
)

$savedSdk = $env:VITASDK
$savedManifest = $env:VITASDK_CHANNEL_MANIFEST
$savedKey = $env:VITASDK_CHANNEL_PUBLIC_KEY
$savedAssets = $env:VITASDK_CHANNEL_ASSET_DIRECTORY
$savedPath = $env:PATH
try {
    $env:VITASDK = $sdkRoot
    $env:VITASDK_CHANNEL_MANIFEST = $manifest
    $env:VITASDK_CHANNEL_PUBLIC_KEY = $publicKey
    $env:VITASDK_CHANNEL_ASSET_DIRECTORY = $assetRoot
    $env:PATH = "${env:SystemRoot}\System32;${env:SystemRoot}"
    Invoke-Checked (Join-Path $sdkRoot "bin/vdpm.exe") @("refresh", "nightly")

    $installedCore = Join-Path $sdkRoot "var/lib/pacman/sync/${hostTriplet}.db"
    $installedVita = Join-Path $sdkRoot "var/lib/pacman/sync/vita.db"
    $configuration = Join-Path $sdkRoot "etc/pacman.conf"
    $installedManifest = Join-Path $sdkRoot "var/lib/vdpm/channel.json"
    if ((Get-FileHash -Algorithm SHA256 $installedCore).Hash.ToLowerInvariant() -ne $coreDigest) {
        throw "Windows refresh installed the wrong core database"
    }
    if ((Get-FileHash -Algorithm SHA256 $installedVita).Hash.ToLowerInvariant() -ne $vitaDigest) {
        throw "Windows refresh installed the wrong package database"
    }
    if ((Get-Content -LiteralPath $configuration -Raw) -notmatch
        [regex]::Escape("Architecture = $hostTriplet vita")) {
        throw "Windows refresh wrote the wrong Pacman architecture"
    }
    if ((Get-FileHash -Algorithm SHA256 $installedManifest).Hash -ne
        (Get-FileHash -Algorithm SHA256 $manifest).Hash) {
        throw "Windows refresh did not retain the authenticated manifest"
    }

    # Reading which release this is has to work against the bundle as it is
    # actually staged. This is the only test that sees that layout: the tool
    # lives in the MSYS root under share/vdpm here, next to pacman.exe, and the
    # frontend spent a release looking for it in bin/ with nothing able to
    # notice.
    $reported = & (Join-Path $sdkRoot "bin/vdpm.exe") status
    if ($LASTEXITCODE -ne 0) {
        throw "vdpm status failed against a staged Windows bundle"
    }
    $reportedText = $reported -join "`n"
    if ($reportedText -notmatch "nightly") {
        throw "vdpm status did not name the release"
    }
    if ($reportedText -notmatch "7") {
        throw "vdpm status did not name the sequence"
    }

    # A hash failure must be detected before any installed state is replaced.
    $beforeCore = (Get-FileHash -Algorithm SHA256 $installedCore).Hash
    Write-Utf8 $coreDatabase "tampered database`n"
    & (Join-Path $sdkRoot "bin/vdpm.exe") refresh nightly
    if ($LASTEXITCODE -eq 0) {
        throw "Windows refresh accepted a database with the wrong digest"
    }
    if ((Get-FileHash -Algorithm SHA256 $installedCore).Hash -ne $beforeCore) {
        throw "failed Windows refresh changed installed repository state"
    }
}
finally {
    $env:VITASDK = $savedSdk
    $env:VITASDK_CHANNEL_MANIFEST = $savedManifest
    $env:VITASDK_CHANNEL_PUBLIC_KEY = $savedKey
    $env:VITASDK_CHANNEL_ASSET_DIRECTORY = $savedAssets
    $env:PATH = $savedPath
}

Write-Host "native signed Windows channel refresh contract passed"
exit 0
