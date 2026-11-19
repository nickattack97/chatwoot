#!/usr/bin/env bash
# Proves the image still builds and the compose file still parses. Nothing is published or deployed: the image gets a
# throwaway name and is removed afterwards (the layer cache stays, so the real release build is faster).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

# Compose will not parse the file unless every env_file exists. The templates hold placeholders only, no secrets.
created=()
for f in deploy/env/*.env.example; do
  real="${f%.example}"
  if [ ! -f "$real" ]; then cp "$f" "$real"; created+=("$real"); fi
done
export HELPENGINE_IMAGE_PREFIX="helpengine-ci" HELPENGINE_VERSION="${CI_COMMIT_SHORT_SHA:-local}-check"
trap '[ ${#created[@]} -eq 0 ] || rm -f "${created[@]}"; docker image rm "$(image_ref "$HELPENGINE_VERSION")" >/dev/null 2>&1 || true' EXIT

COMPOSE_PROFILES=bundled-db docker compose -f "$COMPOSE_FILE_NAME" --profile tools config --quiet
echo "Compose file parses."
"$(dirname "${BASH_SOURCE[0]}")/build-release.sh"
echo "The image builds. Nothing was published."
