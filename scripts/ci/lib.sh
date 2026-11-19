# Shared by scripts/ci/*.sh. Source it; do not run it.
# Every container, network and volume a check job starts carries a run label, so cleanup.sh finds them even if the job is killed.

ROOT="${CI_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
RUN_ID="${CI_PIPELINE_ID:-local}-${CI_JOB_ID:-$$}"
RUN_LABEL="helpengine-ci-run=$RUN_ID"

# The image the releases publish: <registry project path>/helpengine:<version>. One image runs rails, sidekiq and migrate.
COMPONENT="helpengine"
COMPOSE_FILE_NAME="docker-compose.production.yaml"

# Same Ruby as docker/Dockerfile (glibc here, so gems install from the prebuilt platform builds). Change them together.
RUBY_IMAGE="ruby:3.4.4"
PG_IMAGE="pgvector/pgvector:pg16"
REDIS_IMAGE="redis:alpine"
BUNDLER_VERSION="2.5.16"

# A tag is helpengine-v<version>: x.y.z for production (on master), x.y.z-rc.N for UAT.
# (The repository also holds upstream Chatwoot's own v* tags, hence the prefix.)
TAG_PREFIX="helpengine-v"
STABLE_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
RC_RE='^[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$'

image_ref() { echo "${HELPENGINE_IMAGE_PREFIX:?HELPENGINE_IMAGE_PREFIX is not set}/$COMPONENT:${1:?version}"; }

cleanup_run() {
  local id
  docker ps -aq --filter "label=$RUN_LABEL" | while read -r id; do docker rm -f "$id" >/dev/null 2>&1 || true; done
  docker network ls -q --filter "label=$RUN_LABEL" | while read -r id; do docker network rm "$id" >/dev/null 2>&1 || true; done
}
