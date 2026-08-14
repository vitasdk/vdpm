#!/usr/bin/env bash
# Nightly advancing to the next nightly: re-selecting the series you are
# already on, which is the daily path for anyone living there and the case
# neither direction of the round trip exercises. The round trip proves a
# downgrade; this proves the upgrade, and that `upgrade` alone does not go
# looking for another snapshot -- which is the whole difference between the
# two verbs this project promises.
#
# Needs a directory holding two signed manifests naming two different core
# snapshots, plus the public key they were signed with:
#
#   <dir>/a/nightly.json{,.sig}   an earlier core
#   <dir>/b/nightly.json{,.sig}   a later one
#   <dir>/test-pub.pem
#
# Produce them with autobuilds/scripts/generate-channel-manifest.py against a
# throwaway key: signing test data with the production key would make the one
# secret in this system something that travels through fixtures.
#
#   GATE_CHANNEL_DIR=/path/to/dir tests/gate-nightly-advances.sh

set -uo pipefail

directory=$(cd "$(dirname "$0")/.." && pwd -P)
channels=${GATE_CHANNEL_DIR:?set GATE_CHANNEL_DIR to a directory with the two manifests}
channels=$(cd "$channels" && pwd -P)

docker run --rm --platform linux/amd64 \
	--mount "type=bind,source=$directory,target=/vdpm,readonly" \
	--mount "type=bind,source=$directory/bootstrap-vitasdk.sh,target=/bootstrap.sh,readonly" \
	--mount "type=bind,source=$channels,target=/channels,readonly" \
	--mount "type=bind,source=$directory/tests/gate-nightly-advances.body.sh,target=/n.sh,readonly" \
	ubuntu:24.04 bash /n.sh
