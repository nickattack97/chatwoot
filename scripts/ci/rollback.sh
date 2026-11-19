#!/usr/bin/env bash
# Puts an environment back on a published release: pulls that version and restarts rails and sidekiq on it.
# Nothing is built, pushed or migrated. Needs DEPLOY_DIR, HELPENGINE_IMAGE_PREFIX and ROLLBACK_VERSION.
#   ROLLBACK_VERSION=1.2.0          x.y.z, or x.y.z-rc.N on UAT
#   ALLOW_SCHEMA_CHANGE=true        only if you know the older code works with the newer schema (see schema-guard.sh)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib.sh"

: "${DEPLOY_DIR:?DEPLOY_DIR is not set}"
compose() { docker compose -f "$DEPLOY_DIR/$COMPOSE_FILE_NAME" --project-directory "$DEPLOY_DIR" "$@"; }
target="${ROLLBACK_VERSION:-}"
# The value comes from a form field: only a plain version reaches a shell, a registry path or a log.
if ! [[ "$target" =~ $STABLE_RE || "$target" =~ $RC_RE ]]; then
  echo "REFUSED: ROLLBACK_VERSION must look like 1.2.0 or 1.2.0-rc.3 (digits, dots and -rc.N only)." >&2
  exit 1
fi
if [ "${ROLLBACK_ENV:-}" = "production" ] && ! [[ "$target" =~ $STABLE_RE ]]; then
  echo "REFUSED: production only runs stable releases (x.y.z), not $target." >&2
  exit 1
fi

cid="$(compose ps -q rails)"
current=""
if [ -n "$cid" ]; then image="$(docker inspect -f '{{.Config.Image}}' "$cid")"; current="${image##*:}"; fi
if [ "$current" = "$target" ]; then echo "REFUSED: $target is already running." >&2; exit 1; fi
echo "Running ${current:-an unknown version}; switching to $target."

HELPENGINE_VERSION="$target" "$here/registry.sh" exists

echo "Comparing the database migrations of $current and $target"
if ! "$here/schema-guard.sh" "$target" "$current"; then
  if [ "${ALLOW_SCHEMA_CHANGE:-}" = "true" ]; then
    echo "WARNING: continuing because ALLOW_SCHEMA_CHANGE=true. No migration is run or undone; watch the app closely." >&2
  else
    echo "REFUSED: the database would not match the code. Set ALLOW_SCHEMA_CHANGE=true only if you know the schema matches $target." >&2
    exit 1
  fi
fi

export HELPENGINE_VERSION="$target"
compose pull --quiet rails
compose up -d --no-build rails sidekiq
compose ps
"$here/verify-deploy.sh"
echo "Now on $target."
