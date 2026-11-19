#!/usr/bin/env bash
# Removes old HelpEngine images from this host so releases do not fill the disk. Run after a deploy.
# Keeps the newest KEEP_VERSIONS (default 3) of each kind (stable x.y.z and release candidates x.y.z-rc.N) so a rollback
# does not need a re-pull; the moving <major>.<minor> tags are left alone. Never forces (Docker refuses to remove an image a
# container uses) and touches only this project's image name: other projects share the Docker host. PRUNE_DRY_RUN=1 only prints.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

repo="${HELPENGINE_IMAGE_PREFIX:?HELPENGINE_IMAGE_PREFIX is not set}/$COMPONENT"
keep="${KEEP_VERSIONS:-3}"

remove() {
  if [ "${PRUNE_DRY_RUN:-0}" = "1" ]; then echo "would remove $1"; return; fi
  if docker image rm "$1" >/dev/null 2>&1; then echo "removed $1"; else echo "kept $1 (in use)"; fi
}

tags="$(docker image ls "$repo" --format '{{.Tag}}')"
for re in "$STABLE_RE" "$RC_RE"; do
  n=0
  # Newest first, compared as versions (1.0.10 is newer than 1.0.9; rc.10 newer than rc.9).
  for v in $(printf '%s\n' "$tags" | grep -E "$re" | sort -t. -k1,1nr -k2,2nr -k3,3nr -k4,4nr); do
    n=$((n + 1))
    [ "$n" -gt "$keep" ] && remove "$repo:$v"
  done
done
exit 0
