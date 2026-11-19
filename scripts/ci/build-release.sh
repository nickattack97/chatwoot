#!/usr/bin/env bash
# Builds the release image from the checkout: <prefix>/helpengine:<HELPENGINE_VERSION>, labelled with the version, the commit
# and the upstream Chatwoot release it is based on. Run on an amd64 runner: the image compiles grpc for Alpine (musl), which
# does not survive emulation. Nothing is pushed here (registry.sh push does that, after checking the image).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

version="${HELPENGINE_VERSION:?HELPENGINE_VERSION is not set}"
image="$(image_ref "$version")"
echo "Runner architecture $(uname -m); building $image"

# Newer Docker attaches a provenance attestation, which turns the tag into an index the GitLab registry cannot show.
export BUILDX_NO_DEFAULT_ATTESTATIONS=1
DOCKER_BUILDKIT=1 docker build \
  -f docker/Dockerfile \
  --build-arg VERSION="$version" \
  --build-arg REVISION="${CI_COMMIT_SHA:-$(git rev-parse HEAD)}" \
  --build-arg CHATWOOT_VERSION="$(cat VERSION_CW)" \
  -t "$image" .
docker image inspect --format 'Built {{index .Config.Labels "org.opencontainers.image.version"}} ({{index .Config.Labels "org.opencontainers.image.revision"}}), Chatwoot {{index .Config.Labels "zw.co.cbz.chatwoot.version"}}' "$image"
