#!/usr/bin/env bash
# Checks that this host's env files have everything the HelpEngine containers need. Prints the NAMES of what is missing or
# wrong, never a value. Run it from the folder that holds docker-compose.production.yaml (the deploy folder).
#   scripts/check-env.sh all          .env, deploy/env/helpengine.env, redis.env, and postgres.env if bundled-db is on
#   scripts/check-env.sh helpengine   one file
# Exit status 0 = complete, 1 = something is missing, a placeholder, or inconsistent.
set -u
cd "$(dirname "$0")/.."

status=0
file=""

get() { grep -E "^$1=" "$file" | tail -1 | cut -d= -f2-; }
getf() { grep -E "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2-; }
has() { [ -n "$(get "$1")" ]; }
problem() { echo "  PROBLEM  $1"; status=1; }

require() {   # require KEY [why]
  if ! has "$1"; then echo "  MISSING  $1${2:+  ($2)}"; status=1
  elif get "$1" | grep -q "CHANGE_ME"; then echo "  PLACEHOLDER  $1 still says CHANGE_ME"; status=1; fi
}

open_file() {   # open_file NAME PATH -> 0 if present
  file="$2"
  echo "== $1  ($file)"
  if [ ! -f "$file" ]; then echo "  NO FILE. Copy deploy/env/$1.env.example to $file and fill it in."; status=1; return 1; fi
  if grep -nE '^[A-Za-z0-9_]+=[^"#]*[[:space:]]#' "$file" >/dev/null; then
    problem "a value has an inline # comment: Docker may keep it as part of the value. Put comments on their own line."
  fi
}

bundled_db() { grep -qE '^COMPOSE_PROFILES=.*bundled-db' .env 2>/dev/null; }

check() {
  case "$1" in
    compose)
      open_file compose .env || return
      require COMPOSE_PROFILES "bundled-db, or empty when Postgres is a database server"
      case "$(get HELPENGINE_BIND)" in 0.0.0.0) problem "HELPENGINE_BIND is 0.0.0.0: Rails would be reachable past the host's nginx";; esac
      ;;
    helpengine)
      open_file helpengine deploy/env/helpengine.env || return
      require SECRET_KEY_BASE
      [ "$(get SECRET_KEY_BASE | wc -c)" -ge 65 ] || problem "SECRET_KEY_BASE is shorter than 64 characters (openssl rand -hex 64)"
      require FRONTEND_URL "the URL people open, with the DMZ sub-path"
      case "$(get FRONTEND_URL)" in http://*|https://*) ;; *) problem "FRONTEND_URL must start with http:// or https://";; esac
      require POSTGRES_HOST; require POSTGRES_DATABASE; require POSTGRES_USERNAME; require POSTGRES_PASSWORD
      require REDIS_URL; require REDIS_PASSWORD
      require ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY "rails db:encryption:init"
      require ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY; require ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
      require SMTP_ADDRESS; require MAILER_SENDER_EMAIL
      require SAFE_FETCH_ALLOWED_INTERNAL_HOSTS "the WA-Bot-Engine host:port for this environment"
      require UC_BASE_URL "this environment's UserConnect: sign-in is switched on with it when the database is created"
      require UC_SYSTEM_ID "the HelpEngine's system ID in this UserConnect"
      case "$(get UC_BASE_URL)" in http://*|https://*|CHANGE_ME*) ;; *) problem "UC_BASE_URL must start with http:// or https://";; esac
      case "$(get UC_BASE_URL)" in */api/v1|*/api/v1/) problem "UC_BASE_URL must not end in /api/v1 (the app adds it)";; esac
      has UC_PORTAL_URL || echo "  note: UC_PORTAL_URL is empty, so the change-password link goes nowhere"
      if bundled_db; then
        [ "$(get POSTGRES_HOST)" = "postgres" ] || problem "bundled-db is on but POSTGRES_HOST is not 'postgres'"
      elif [ "$(get POSTGRES_HOST)" = "postgres" ]; then
        problem "POSTGRES_HOST is the bundled container but bundled-db is off in .env"
      fi
      [ "$(get REDIS_PASSWORD)" = "$(getf deploy/env/redis.env REDIS_PASSWORD)" ] || problem "REDIS_PASSWORD differs from deploy/env/redis.env"
      if bundled_db && [ "$(get POSTGRES_PASSWORD)" != "$(getf deploy/env/postgres.env POSTGRES_PASSWORD)" ]; then
        problem "POSTGRES_PASSWORD differs from deploy/env/postgres.env"
      fi
      ;;
    redis)
      open_file redis deploy/env/redis.env || return
      require REDIS_PASSWORD
      ;;
    postgres)
      open_file postgres deploy/env/postgres.env || return
      require POSTGRES_PASSWORD; require POSTGRES_USER; require POSTGRES_DB
      ;;
    *) echo "unknown: $1 (compose, helpengine, redis, postgres or all)"; status=1 ;;
  esac
}

if [ "${1:-all}" = "all" ]; then
  check compose; check helpengine; check redis
  if bundled_db; then check postgres; else echo "== postgres  (bundled-db is off: Postgres is a database server)"; fi
else
  check "$1"
fi

[ "$status" -eq 0 ] && echo "All env files are complete." || echo "Fix the above, then run the job again."
exit "$status"
