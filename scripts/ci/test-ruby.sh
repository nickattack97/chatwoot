#!/usr/bin/env bash
# The Ruby checks, in throwaway containers so the runner needs only Docker (the same script runs on a developer's machine):
#   RuboCop on the Ruby files this merge request or push changes (the tree carries older offenses, mostly in fork files such
#   as db/seeds/cbz_configs.rb, cleared separately; new ones must not get in), and RSpec on scripts/ci/specs.txt: every
#   spec the CBZ fork added or changed against its
#   upstream release, plus the WhatsApp ones. (The full upstream suite needs compiled frontend assets and a long run;
#   ~150 of its examples fail in a container without them, with or without our changes.)
# Gems are cached in the volume helpengine-ci-bundle-<arch> between runs. The lockfile only lists macOS and generic
# platforms, so a temporary copy of Gemfile/Gemfile.lock gets this machine's Linux platform: grpc then installs prebuilt
# instead of compiling (which runs out of memory on 8 GB machines). The repository's lockfile is never changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$ROOT"

arch="$(uname -m)"; case "$arch" in arm64) arch=aarch64 ;; esac
platform="$arch-linux"
gemenv="$ROOT/tmp/ci-gemenv"
net="helpengine-ci-$RUN_ID"
pg="helpengine-ci-pg-$RUN_ID"
redis="helpengine-ci-redis-$RUN_ID"
pg_password="ci$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
trap cleanup_run EXIT

mkdir -p "$gemenv"
cp Gemfile Gemfile.lock .ruby-version "$gemenv/"

# The files to lint: what the merge request changes, or what this push added since the previous one. A tag pipeline
# has no "before" (its code was linted when it was merged), and neither does a local run unless RUBOCOP_BASE is given.
base="${RUBOCOP_BASE:-${CI_MERGE_REQUEST_DIFF_BASE_SHA:-${CI_COMMIT_BEFORE_SHA:-}}}"
: > "$gemenv/rubocop-files"
if [ -n "$base" ] && [ "$base" != "0000000000000000000000000000000000000000" ]; then
  git cat-file -e "$base^{commit}" 2>/dev/null || git fetch -q --depth=1 origin "$base" 2>/dev/null || true
  if git cat-file -e "$base^{commit}" 2>/dev/null; then
    git diff --name-only --diff-filter=AMR "$base" HEAD -- '*.rb' '*.rake' Gemfile > "$gemenv/rubocop-files"
    echo "RuboCop: $(wc -l < "$gemenv/rubocop-files" | tr -d ' ') changed file(s) since ${base:0:10}"
  else
    echo "RuboCop: cannot find $base in this clone; skipped"
  fi
else
  echo "RuboCop: no base commit (tag or local run without RUBOCOP_BASE); skipped"
fi

docker network create --label "$RUN_LABEL" "$net" >/dev/null
docker run -d --label "$RUN_LABEL" --name "$pg" --network "$net" --network-alias postgres \
  -e POSTGRES_PASSWORD="$pg_password" "$PG_IMAGE" >/dev/null
docker run -d --label "$RUN_LABEL" --name "$redis" --network "$net" --network-alias redis "$REDIS_IMAGE" >/dev/null

# A developer's .env must not leak into the checks (CI has none); hide it if present.
hide_env=()
[ -f "$ROOT/.env" ] && hide_env=(-v /dev/null:/app/.env:ro)

docker run --rm --label "$RUN_LABEL" --network "$net" \
  -v "$ROOT":/app -w /app ${hide_env[@]+"${hide_env[@]}"} \
  -v "$gemenv":/gemenv -v "helpengine-ci-bundle-$arch":/usr/local/bundle \
  -e BUNDLE_PATH=/usr/local/bundle -e BUNDLE_GEMFILE=/gemenv/Gemfile \
  -e RAILS_ENV=test -e NODE_ENV=test -e EXECJS_RUNTIME=Disabled \
  -e POSTGRES_HOST=postgres -e POSTGRES_USERNAME=postgres -e POSTGRES_PASSWORD="$pg_password" -e POSTGRES_DATABASE=chatwoot_test \
  -e REDIS_URL=redis://redis:6379 \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e PLATFORM="$platform" -e BUNDLER_VERSION="$BUNDLER_VERSION" \
  "$RUBY_IMAGE" bash -c '
    set -euo pipefail
    status=0
    # Files the checks write into the checkout belong to the caller again afterwards, so the runner can clean up.
    trap "chown -R \$HOST_UID:\$HOST_GID /app/tmp /app/log /app/coverage /gemenv 2>/dev/null || true" EXIT
    gem install bundler -v "$BUNDLER_VERSION" -N >/dev/null
    bundle _${BUNDLER_VERSION}_ lock --add-platform "$PLATFORM" >/dev/null
    bundle _${BUNDLER_VERSION}_ install --jobs 4 --retry 2 --quiet
    until pg_isready -q -h postgres 2>/dev/null || ruby -rsocket -e "TCPSocket.new(%q(postgres), 5432)" 2>/dev/null; do sleep 1; done
    bundle _${BUNDLER_VERSION}_ exec rails db:create db:schema:load >/dev/null

    if [ -s /gemenv/rubocop-files ]; then
      echo "== RuboCop ($(wc -l < /gemenv/rubocop-files) changed files)"
      bundle _${BUNDLER_VERSION}_ exec rubocop --force-exclusion --format progress $(cat /gemenv/rubocop-files) || status=1
    fi
    echo "== RSpec ($(wc -l < scripts/ci/specs.txt) files from scripts/ci/specs.txt)"
    bundle _${BUNDLER_VERSION}_ exec rspec --format progress $(cat scripts/ci/specs.txt) || status=1
    exit $status
  '
