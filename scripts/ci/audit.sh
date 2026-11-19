#!/usr/bin/env bash
# Known-vulnerable gems (bundle-audit, from the Gemfile's test group). Advisories appear without any code change, so the
# pipeline treats a finding as a warning for UAT and as blocking for a production release.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

arch="$(uname -m)"; case "$arch" in arm64) arch=aarch64 ;; esac
gemenv="$ROOT/tmp/ci-gemenv"
mkdir -p "$gemenv"
cp Gemfile Gemfile.lock .ruby-version "$gemenv/"

docker run --rm --label "$RUN_LABEL" -v "$ROOT":/app:ro -w /app -v "$gemenv":/gemenv \
  -v "helpengine-ci-bundle-$arch":/usr/local/bundle \
  -e BUNDLE_PATH=/usr/local/bundle -e BUNDLE_GEMFILE=/gemenv/Gemfile -e PLATFORM="$arch-linux" -e BUNDLER_VERSION="$BUNDLER_VERSION" \
  "$RUBY_IMAGE" bash -c '
    set -euo pipefail
    gem install bundler -v "$BUNDLER_VERSION" -N >/dev/null
    bundle _${BUNDLER_VERSION}_ lock --add-platform "$PLATFORM" >/dev/null
    bundle _${BUNDLER_VERSION}_ install --jobs 4 --retry 2 --quiet
    # Audit the real lockfile, not the copy with the extra platform.
    bundle _${BUNDLER_VERSION}_ exec bundle-audit check --update --gemfile-lock /app/Gemfile.lock
  '
