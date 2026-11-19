#!/usr/bin/env bash
# Says whether the database migrations of two releases differ, in EITHER direction. A rollback swaps containers only: it never
# runs or undoes a migration. Rolling back over a migration leaves older code on a newer schema; rolling forward onto one leaves
# newer code on a schema without its changes (a release pipeline runs migrations; a rollback does not).
#   schema-guard.sh <target> <current>      versions without the tag prefix, e.g. 1.2.0 1.2.1-rc.2
# Exit 0: the same migrations. Exit 1: they differ, or it could not tell (and says why).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

target="${1:?usage: schema-guard.sh <target> <current>}"
current="${2:-}"
dirs=(db/migrate enterprise/db/migrate)

if [ -z "$current" ]; then echo "Cannot tell which release is running, so cannot tell whether the schema changed." >&2; exit 1; fi

for v in "$target" "$current"; do
  tag="$TAG_PREFIX$v"
  if ! git rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null; then
    git fetch -q --depth=1 origin "refs/tags/$tag:refs/tags/$tag" 2>/dev/null || { echo "Cannot find git tag $tag to compare migrations." >&2; exit 1; }
  fi
  # A guard that looks at a folder that is not there would say "nothing changed" forever. Refuse instead.
  if [ -z "$(git ls-tree -r --name-only "$tag" -- db/migrate | head -1)" ]; then
    echo "No db/migrate in $tag, so the comparison would mean nothing." >&2
    exit 1
  fi
done

only_in() { git diff --name-only --diff-filter=A "$TAG_PREFIX$1" "$TAG_PREFIX$2" -- "${dirs[@]}" | sed 's#.*/##'; }
in_current_only="$(only_in "$target" "$current")"
in_target_only="$(only_in "$current" "$target")"

status=0
if [ -n "$in_current_only" ]; then
  echo "Rolling back: $current has migrations that $target does not know (the database keeps them):" >&2
  echo "$in_current_only" | sed 's/^/  /' >&2
  status=1
fi
if [ -n "$in_target_only" ]; then
  echo "Rolling forward: $target has migrations that $current has not run (a rollback runs none; use a release tag):" >&2
  echo "$in_target_only" | sed 's/^/  /' >&2
  status=1
fi
[ "$status" -eq 0 ] && echo "$target and $current have the same migrations."
exit "$status"
