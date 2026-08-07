#!/usr/bin/env python3

import json
import re
import sys
from pathlib import Path


def fail(message):
    raise ValueError(message)


def load_manifest(path, channel, host):
    raw = Path(path).read_bytes()
    data = json.loads(raw)
    canonical = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
    if raw != canonical:
        fail("manifest is not canonical JSON")
    if data.get("schema_version") != 1 or data.get("channel") != channel:
        fail("manifest schema or channel mismatch")
    if not isinstance(data.get("sequence"), int) or data["sequence"] < 1:
        fail("invalid channel sequence")

    core = data.get("core", {})
    packages = data.get("packages", {})
    host_data = core.get("architectures", {}).get(host)
    if not host_data:
        fail(f"host is not published by this channel: {host}")
    for section in (core, packages):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", section.get("repository", "")):
            fail("invalid repository identity")
        if not re.fullmatch(r"[A-Za-z0-9._-]+", section.get("release", "")):
            fail("invalid release tag")
    for asset in (host_data.get("database"), packages.get("database")):
        if not isinstance(asset, dict):
            fail("missing database asset")
        if not re.fullmatch(r"[A-Za-z0-9._-]+", asset.get("name", "")):
            fail("invalid asset name")
        if not re.fullmatch(r"[0-9a-f]{64}", asset.get("sha256", "")):
            fail("invalid asset hash")
    return data, host_data


def asset_url(section, asset):
    return "https://github.com/{}/releases/download/{}/{}".format(
        section["repository"], section["release"], asset["name"]
    )


def main():
    if len(sys.argv) not in (4, 5):
        fail("usage: channel-manifest.py MANIFEST CHANNEL HOST [FIELD]")
    data, host_data = load_manifest(sys.argv[1], sys.argv[2], sys.argv[3])
    if len(sys.argv) == 4:
        return 0
    fields = {
        "sequence": str(data["sequence"]),
        "core.database.name": host_data["database"]["name"],
        "core.database.sha256": host_data["database"]["sha256"],
        "core.database.url": asset_url(data["core"], host_data["database"]),
        "core.server": "https://github.com/{}/releases/download/{}".format(
            data["core"]["repository"], data["core"]["release"]
        ),
        "packages.database.name": data["packages"]["database"]["name"],
        "packages.database.sha256": data["packages"]["database"]["sha256"],
        "packages.database.url": asset_url(data["packages"], data["packages"]["database"]),
        "packages.server": "https://github.com/{}/releases/download/{}".format(
            data["packages"]["repository"], data["packages"]["release"]
        ),
    }
    if sys.argv[4] not in fields:
        fail("unknown field")
    print(fields[sys.argv[4]])
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"channel-manifest: {error}", file=sys.stderr)
        raise SystemExit(1)
