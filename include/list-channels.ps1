# Which release series exist, and what state each of them is in.
#
# The Windows half of `vdpm channels`. Without an index a release is
# undiscoverable: you would have to be told its name before you could ask for
# it, and a series that has ended has no way of telling the people on it.
#
# The index is signed with the same key as the manifests, because it decides
# where people are told they may move to.

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$sdkRoot = $env:VITASDK
if (-not $sdkRoot) {
    throw "VITASDK is not set"
}

$channelTool = $env:VDPM_CHANNEL_TOOL
if (-not $channelTool) {
    # Where the Windows bootstrap installs it, which is not bin/:
    # refresh-repositories.ps1 has always looked here.
    $channelTool = Join-Path $sdkRoot "share/vdpm/msys/usr/bin/vdpm-channel.exe"
}
if (-not (Test-Path -LiteralPath $channelTool -PathType Leaf)) {
    throw "missing ${channelTool}"
}

$publicKey = $env:VITASDK_CHANNEL_PUBLIC_KEY
if (-not $publicKey) {
    $publicKey = Join-Path $sdkRoot "share/vdpm/channel-public-key.pem"
}

$base = $env:VITASDK_CHANNEL_BASE_URL
if (-not $base) {
    $base = "https://vitasdk.org/channels"
}

$temporary = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $temporary -Force | Out-Null
try {
    $index = Join-Path $temporary "index.json"
    $signature = Join-Path $temporary "index.json.sig"
    Invoke-WebRequest -UseBasicParsing -Uri "${base}/index.json" -OutFile $index
    Invoke-WebRequest -UseBasicParsing -Uri "${base}/index.json.sig" -OutFile $signature

    # Authenticated before it is read, like everything else this client trusts.
    & $channelTool verify $index $signature $publicKey
    if ($LASTEXITCODE -ne 0) {
        throw "the release index is not signed by the key this SDK trusts"
    }

    $current = ""
    $manifest = Join-Path $sdkRoot "var/lib/vdpm/channel.json"
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        $described = @(& $channelTool describe $manifest)
        foreach ($line in $described) {
            $parts = $line -split "`t", 2
            if ($parts.Length -eq 2 -and $parts[0] -eq "channel") {
                $current = $parts[1]
            }
        }
    }

    # Kept for `vdpm status`, so it can say whether this series is still
    # maintained without going to the network.
    $stateDirectory = Join-Path $sdkRoot "var/lib/vdpm"
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    Copy-Item -LiteralPath $index -Destination (Join-Path $stateDirectory "index.json") -Force

    $rows = @()
    foreach ($line in @(& $channelTool series $index)) {
        $parts = $line -split "`t", 4
        if ($parts.Length -lt 2) { continue }
        $rows += ,@{
            Name = $parts[0]
            Status = $parts[1]
            Summary = $(if ($parts.Length -ge 3) { $parts[2] } else { "" })
            World = $(if ($parts.Length -ge 4) { $parts[3] } else { "" })
        }
    }
    # The world column appears only once there is more than one, so the
    # listing everybody already reads does not grow a column saying the only
    # answer.
    $manyWorlds = (@($rows | ForEach-Object { $_.World } | Sort-Object -Unique)).Count -gt 1
    if ($manyWorlds) {
        "{0,-14} {1,-14} {2,-14} {3}" -f "RELEASE", "STATUS", "WORLD", "SUMMARY"
    } else {
        "{0,-14} {1,-14} {2}" -f "RELEASE", "STATUS", "SUMMARY"
    }
    foreach ($row in $rows) {
        $marker = " "
        if ($row.Name -eq $current) { $marker = "*" }
        if ($manyWorlds) {
            "{0}{1,-13} {2,-14} {3,-14} {4}" -f `
                $marker, $row.Name, $row.Status, $row.World, $row.Summary
        } else {
            "{0}{1,-13} {2,-14} {3}" -f $marker, $row.Name, $row.Status, $row.Summary
        }
    }
    if ($current) {
        ""
        "* is the release this installation follows."
    }
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
