# The Windows bootstrap, run for real.
#
# Every change to it so far has been written on a machine that cannot execute
# it, and validated by assuming the Unix path proved the idea. That assumption
# already produced one release whose Windows installer still unpacked a tree
# pacman knew nothing about, so this runs the thing.
#
# It installs against the published channels, which means it is also the only
# check that the seed named in the script exists and carries what it claims.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repository = Split-Path -Parent $PSScriptRoot
$installDirectory = Join-Path $env:RUNNER_TEMP 'vitasdk-bootstrap-windows'
if (Test-Path $installDirectory) { Remove-Item -Recurse -Force $installDirectory }

$failures = 0
function Check($what, $actual, $expected) {
    if ($actual -eq $expected) {
        Write-Host "ok: $what ($actual)"
    } else {
        Write-Host "FAIL: $what`n  expected: $expected`n  actual:   $actual"
        $script:failures++
    }
}

# MSYS programs expand the wildcards in their command line against the current
# directory, so the installer's overwrite patterns turn into whatever sits next
# to the user. Run it from a directory those patterns match, which is what the
# first run of this test found and what nothing else would notice.
$decoy = Join-Path $env:RUNNER_TEMP 'vitasdk-bootstrap-cwd'
if (Test-Path $decoy) { Remove-Item -Recurse -Force $decoy }
foreach ($path in 'here/bin', 'here/usr/bin', 'here/share/vdpm', 'here/etc') {
    New-Item -ItemType Directory -Force -Path (Join-Path $decoy $path) | Out-Null
}
foreach ($path in 'here/bin/vdpm.exe', 'here/usr/bin/pacman.exe',
        'here/share/vdpm/channel-public-key.pem', 'here/etc/pacman.conf') {
    Set-Content -Path (Join-Path $decoy $path) -Value 'decoy'
}

Push-Location $decoy
try {
    & (Join-Path $repository 'bootstrap-vitasdk.ps1') -InstallDirectory $installDirectory
} finally {
    Pop-Location
}
if ($LASTEXITCODE -ne 0) { throw 'the bootstrap did not install' }

$pacman = Join-Path $installDirectory 'usr/bin/pacman.exe'
$configuration = Join-Path $installDirectory 'etc/pacman.conf'
$database = Join-Path $installDirectory 'var/lib/pacman'

# An installation pacman knows about is the whole point: an unpacked tree
# cannot be upgraded, moved to another series, or asked what it is.
$installed = & $pacman --config $configuration --root $installDirectory `
    --dbpath $database --query vitasdk-core
Check 'the toolchain is registered' ($LASTEXITCODE -eq 0) $true
Check 'and it is a core' (($installed -split ' ')[0]) 'vitasdk-core'

Check 'the compiler is there' `
    (Test-Path (Join-Path $installDirectory 'bin/arm-vita-eabi-gcc.exe')) $true
Check 'the client is there' `
    (Test-Path (Join-Path $installDirectory 'bin/vdpm.exe')) $true

# The series has to be written into the SDK, not merely used to pick an
# archive and then forgotten.
$channel = Get-Content (Join-Path $installDirectory 'var/lib/vdpm/channel.json') -Raw |
    ConvertFrom-Json
Check 'a series is selected' ([bool]$channel.channel) $true

$env:VITASDK = $installDirectory
$status = & (Join-Path $installDirectory 'bin/vdpm.exe') status
Check 'status answers' ($LASTEXITCODE -eq 0) $true
Check 'and names the toolchain it has' `
    ([bool]($status | Select-String -Pattern '^Installed ')) $true

$status | ForEach-Object { Write-Host "    $_" }

if ($failures -ne 0) {
    # Where the files went is the question a failure here raises, and it is
    # not one worth another ten-minute round trip to answer.
    Write-Host "`n--- what is in the installation"
    Get-ChildItem $installDirectory | ForEach-Object { Write-Host "    $($_.Name)" }
    Write-Host "--- what pacman says it installed"
    & $pacman --config $configuration --root $installDirectory --dbpath $database `
        --query --list vitasdk-core 2>&1 |
        Select-Object -First 6 | ForEach-Object { Write-Host "    $_" }
    Write-Host "--- where the compiler actually is"
    Get-ChildItem -Recurse -Force -Filter 'arm-vita-eabi-gcc.exe' $env:RUNNER_TEMP `
        -ErrorAction SilentlyContinue |
        Select-Object -First 3 | ForEach-Object { Write-Host "    $($_.FullName)" }
    Write-Host "--- the tail of pacman's log"
    Get-Content (Join-Path $installDirectory 'var/log/pacman.log') -Tail 6 `
        -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
    exit 1
}
Write-Host 'the Windows bootstrap installs a managed SDK'
