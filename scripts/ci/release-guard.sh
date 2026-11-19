#!/usr/bin/env bash
# Checks that a release tag may deploy where it is about to, and prints the version.
#   release-guard.sh uat          the tag is helpengine-vX.Y.Z-rc.N and its commit is on dev
#   release-guard.sh production   the tag is helpengine-vX.Y.Z and its commit is on master
# A production release is whatever was merged to master, never a commit that only exists on a branch.
# Needs CI_COMMIT_TAG and CI_COMMIT_SHA (set by GitLab) and a clone that can fetch origin.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

env="${1:?usage: release-guard.sh uat|production}"
tag="${CI_COMMIT_TAG:?CI_COMMIT_TAG is not set: releases run from tags only}"
version="${tag#"$TAG_PREFIX"}"

case "$env" in
  uat)        pattern="$RC_RE";     branch="dev" ;;
  production) pattern="$STABLE_RE"; branch="master" ;;
  *) echo "usage: release-guard.sh uat|production" >&2; exit 2 ;;
esac

if [ "$version" = "$tag" ] || ! [[ "$version" =~ $pattern ]]; then
  echo "REFUSED: tag $tag is not a $env release tag (${TAG_PREFIX}X.Y.Z$([ "$env" = uat ] && echo '-rc.N'))." >&2
  exit 1
fi

# The pipeline clones shallow (GIT_DEPTH); fetch enough of the branch for the ancestry check to see the tag's commit.
git fetch -q --depth=1000 origin "+refs/heads/$branch:refs/remotes/origin/$branch"
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then git fetch -q --deepen=1000 origin "${CI_COMMIT_SHA:?}" 2>/dev/null || true; fi
if ! git merge-base --is-ancestor "${CI_COMMIT_SHA:?}" "origin/$branch"; then
  echo "REFUSED: $tag points at ${CI_COMMIT_SHA:0:10}, which is not on $branch. A $env release is cut from $branch." >&2
  exit 1
fi
echo "$version"
