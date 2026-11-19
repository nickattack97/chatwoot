#!/usr/bin/env bash
# Verifies a deploy: rails and sidekiq run the image for this release, are running, and report healthy.
# Needs DEPLOY_DIR, HELPENGINE_IMAGE_PREFIX and HELPENGINE_VERSION. A service still starting is checked again until
# VERIFY_TIMEOUT seconds (default 180: Rails boots slowly) pass; one that is unhealthy, stopped, missing or on another
# image fails at once. `starting` is never a pass. Exit 0 = all healthy.
# (No `set -u`: bash 3.2 on macOS treats an empty array as unset, and this is tested on a Mac.)
set -o pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${DEPLOY_DIR:?DEPLOY_DIR is not set}" "${HELPENGINE_VERSION:?HELPENGINE_VERSION is not set}"
compose() { docker compose -f "$DEPLOY_DIR/$COMPOSE_FILE_NAME" --project-directory "$DEPLOY_DIR" "$@"; }
want="$(image_ref "$HELPENGINE_VERSION")"
timeout="${VERIFY_TIMEOUT:-180}"
interval="${VERIFY_INTERVAL:-5}"

pending=(rails sidekiq)
failed=0
last=""
deadline=$(( $(date +%s) + timeout ))

while :; do
  next=()
  for svc in "${pending[@]}"; do
    cid="$(compose ps -q "$svc")"
    if [ -z "$cid" ]; then echo "FAILED: $svc container is missing"; failed=1; continue; fi

    image="$(docker inspect -f '{{.Config.Image}}' "$cid")"
    if [ "$image" != "$want" ]; then echo "FAILED: $svc runs $image, expected $want"; failed=1; continue; fi

    running="$(docker inspect -f '{{.State.Running}}' "$cid")"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid")"
    echo "$svc: running=$running health=$health"
    if [ "$running" != "true" ]; then echo "FAILED: $svc is not running"; failed=1; continue; fi

    case "$health" in
      healthy) ;;
      none)      echo "FAILED: $svc has no health check, so it cannot be verified"; failed=1 ;;
      unhealthy) echo "FAILED: $svc is unhealthy"; failed=1 ;;
      *)         next+=("$svc"); last="$health" ;;
    esac
  done

  pending=("${next[@]}")
  [ "${#pending[@]}" -eq 0 ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAILED: not healthy after ${timeout}s (last status: $last): ${pending[*]}"
    failed=1
    break
  fi
  echo "  waiting for: ${pending[*]}"
  sleep "$interval"
done

if [ "$failed" -ne 0 ]; then
  echo "Last log lines of rails and sidekiq:"
  compose logs --no-color --tail 40 rails sidekiq 2>&1 | sed 's/^/  /'
else
  echo "All services are healthy on $HELPENGINE_VERSION."
fi
exit "$failed"
