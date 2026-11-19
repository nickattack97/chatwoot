#!/usr/bin/env bash
# The deploy-side steps, run on the target host's runner. HELPENGINE_IMAGE_PREFIX and HELPENGINE_VERSION choose the image;
# DEPLOY_DIR is where docker-compose.production.yaml, .env and deploy/env/*.env live on that host.
#   sync      copy the compose file, the env checker and the env templates into DEPLOY_DIR (never the real env files)
#   prepare   check the env files, pull this version, hand the storage volume to uid 1000 (once), start Redis and the
#             bundled Postgres (if the bundled-db profile is on) and wait until they are healthy
#   migrate   run the one-off migrate container (db:chatwoot_prepare)
#   up        start rails and sidekiq on this version
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dir="${DEPLOY_DIR:?DEPLOY_DIR is not set}"
compose() { docker compose -f "$dir/$COMPOSE_FILE_NAME" --project-directory "$dir" "$@"; }

# Waits up to $2 seconds (default 90) for every service in $1 (space separated) to report healthy.
wait_healthy() {
  local services="$1" timeout="${2:-90}" deadline svc cid health pending
  deadline=$(( $(date +%s) + timeout ))
  while :; do
    pending=""
    for svc in $services; do
      cid="$(compose ps -q "$svc")"
      health="$( [ -n "$cid" ] && docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" || echo missing)"
      case "$health" in healthy|none) ;; unhealthy|missing) echo "FAILED: $svc is $health" >&2; return 1 ;; *) pending="$pending $svc" ;; esac
    done
    [ -z "$pending" ] && return 0
    if [ "$(date +%s)" -ge "$deadline" ]; then echo "FAILED: not healthy after ${timeout}s:$pending" >&2; return 1; fi
    sleep 3
  done
}

case "${1:-}" in
  sync)
    mkdir -p "$dir/deploy/env" "$dir/scripts"
    cp "$ROOT/$COMPOSE_FILE_NAME" "$dir/"
    cp "$ROOT/scripts/check-env.sh" "$dir/scripts/"
    cp "$ROOT"/deploy/env/*.env.example "$dir/deploy/env/"
    echo "Synced the compose file, scripts/check-env.sh and the env templates to $dir"
    ;;

  prepare)
    : "${HELPENGINE_VERSION:?HELPENGINE_VERSION is not set}"
    echo "Checking the env files on this host (names only, never values)"
    (cd "$dir" && scripts/check-env.sh all)
    compose config --quiet
    image="$(image_ref "$HELPENGINE_VERSION")"
    # HELPENGINE_SKIP_PULL=1 only for a local trial run against an image built on the same machine.
    if [ "${HELPENGINE_SKIP_PULL:-0}" = "1" ]; then echo "Using the local $image (no pull)"; else
      echo "Pulling $image"
      compose pull --quiet rails
    fi

    # Releases before the pipeline ran as root, so the existing uploads belong to root. Hand them to uid 1000 once.
    volume="cbz-helpengine_storage_data"
    if docker volume inspect "$volume" >/dev/null 2>&1; then
      docker run --rm --user 0 --entrypoint sh -v "$volume:/s" "$image" -c \
        'if [ -n "$(find /s ! -uid 1000 -print -quit)" ]; then echo "Handing $0 to uid 1000"; chown -R 1000:1000 /s; fi' "$volume"
    fi

    datastores="redis"
    if compose config --services | grep -qx postgres; then datastores="redis postgres"; fi
    echo "Starting $datastores"
    compose up -d --no-build $datastores
    wait_healthy "$datastores" 120
    echo "Datastores healthy: $datastores"
    ;;

  migrate)
    : "${HELPENGINE_VERSION:?HELPENGINE_VERSION is not set}"
    echo "Running database migrations for $HELPENGINE_VERSION"
    compose --profile tools run --rm --no-deps migrate
    ;;

  up)
    : "${HELPENGINE_VERSION:?HELPENGINE_VERSION is not set}"
    echo "Starting rails and sidekiq on $HELPENGINE_VERSION"
    compose up -d --no-build --remove-orphans rails sidekiq
    compose ps
    ;;

  *)
    echo "usage: stack.sh sync|prepare|migrate|up" >&2
    exit 2
    ;;
esac
