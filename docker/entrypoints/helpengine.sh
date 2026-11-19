#!/bin/sh
# Production entrypoint for the HelpEngine image: rails, sidekiq and the one-off migrate job.
# Unlike upstream's rails.sh it installs nothing at start (the image is complete and runs as uid 1000 on a read-only
# filesystem) and gives up, rather than waiting forever, if Postgres never answers.
set -eu

rm -f /app/tmp/pids/server.pid

# DATABASE_URL, when set, wins over the POSTGRES_* variables (upstream's helper prints the exports).
eval "$(/app/docker/entrypoints/helpers/pg_database_url.rb)"
: "${POSTGRES_HOST:?POSTGRES_HOST is not set (deploy/env/helpengine.env)}"

wait_seconds="${POSTGRES_WAIT_SECONDS:-120}"
waited=0
until pg_isready -q -h "$POSTGRES_HOST" -p "${POSTGRES_PORT:-5432}" -U "${POSTGRES_USERNAME:-postgres}"; do
  if [ "$waited" -ge "$wait_seconds" ]; then
    echo "Postgres at $POSTGRES_HOST:${POSTGRES_PORT:-5432} did not answer within ${wait_seconds}s" >&2
    exit 1
  fi
  sleep 2
  waited=$((waited + 2))
done

exec "$@"
