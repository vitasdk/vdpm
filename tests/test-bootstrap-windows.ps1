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

& (Join-Path $repository 'bootstrap-vitasdk.ps1') -InstallDirectory $installDirectory
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

if ($failures -ne 0) { exit 1 }
Write-Host 'the Windows bootstrap installs a managed SDK'
