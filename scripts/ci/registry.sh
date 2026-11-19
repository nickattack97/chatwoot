#!/usr/bin/env bash
# Registry steps of a release pipeline.
#   login   log in to the GitLab registry with the job token (CI only)
#   logout  log out again (never fails, so it is safe in after_script)
#   check   refuse if this version is already published: a published version is immutable
#   exists  fail unless this version is in the registry (before a rollback)
#   push    push the image built by build-release.sh, then the moving <major>.<minor> tag for a stable release.
#           There is no `latest`. Refuses an image that carries an attestation (see is_index).
# check, exists and push need HELPENGINE_IMAGE_PREFIX and HELPENGINE_VERSION.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# True when `docker manifest inspect` failed because the image is not there, as opposed to a login or network error.
is_absent() {
  case "$1" in
    *"no such manifest"* | *"manifest unknown"* | *"name unknown"* | *"not found"*) return 0 ;;
  esac
  return 1
}

# True when a local image is an OCI index or manifest list, which a provenance attestation makes of it. The GitLab registry
# shows such a tag as invalid (no digest, no size), and a published version cannot be repaired, so this is checked first.
is_index() {
  case "$1" in
    *image.index* | *manifest.list*) return 0 ;;
  esac
  return 1
}

case "${1:-}" in
  login)
    : "${CI_REGISTRY:?CI_REGISTRY is not set}" "${CI_JOB_TOKEN:?CI_JOB_TOKEN is not set}"
    printf '%s' "$CI_JOB_TOKEN" | docker login -u gitlab-ci-token --password-stdin "$CI_REGISTRY" >/dev/null
    echo "Logged in to $CI_REGISTRY"
    ;;

  logout)
    docker logout "${CI_REGISTRY:-}" >/dev/null 2>&1 || true
    ;;

  check)
    image="$(image_ref "${HELPENGINE_VERSION:?HELPENGINE_VERSION is not set}")"
    if out="$(docker manifest inspect "$image" 2>&1)"; then
      echo "REFUSED: $image already exists. A published version is immutable; tag a new version." >&2
      exit 1
    fi
    if is_absent "$out"; then echo "ok: $image is free"; else
      echo "Could not check $image (registry or login problem?):" >&2; echo "$out" >&2; exit 1
    fi
    ;;

  exists)
    image="$(image_ref "${HELPENGINE_VERSION:?HELPENGINE_VERSION is not set}")"
    if out="$(docker manifest inspect "$image" 2>&1)"; then echo "ok: $image exists"
    elif is_absent "$out"; then echo "MISSING: $image is not in the registry" >&2; exit 1
    else echo "Could not check $image (registry or login problem?):" >&2; echo "$out" >&2; exit 1
    fi
    ;;

  push)
    version="${HELPENGINE_VERSION:?HELPENGINE_VERSION is not set}"
    image="$(image_ref "$version")"
    # On Docker's classic image store there is no descriptor and this prints nothing: such an image cannot carry an attestation.
    kind="$(docker image inspect --format '{{.Descriptor.mediaType}}' "$image" 2>/dev/null || true)"
    if is_index "$kind"; then
      echo "REFUSED: $image carries an attestation (it is an image index), which the GitLab registry shows as an invalid tag." >&2
      echo "Nothing was pushed. Build with BUILDX_NO_DEFAULT_ATTESTATIONS=1 (or --provenance=false) and run the job again." >&2
      exit 1
    fi
    docker push --quiet "$image"
    # A stable release also moves its minor tag (1.2.3 -> 1.2); a release candidate never does.
    if [[ "$version" =~ $STABLE_RE ]]; then
      minor="${version%.*}"
      docker tag "$image" "$(image_ref "$minor")"
      docker push --quiet "$(image_ref "$minor")"
    fi
    echo "Published $(docker image inspect --format '{{index .RepoDigests 0}}' "$image" 2>/dev/null || echo "$image")"
    ;;

  *)
    echo "usage: registry.sh login|logout|check|exists|push" >&2
    exit 2
    ;;
esac
