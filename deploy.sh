#!/bin/bash
set -e

SERVER="itdevtd@192.168.230.54"
REMOTE_SRC="~/cbz-source"
REMOTE_APP="~/cbz-helpengine"
COMPOSE="docker-compose.production.yaml"
SOCKET="/tmp/cbz-deploy-$$"

# Open one master connection — only password prompt in the whole script.
# All subsequent ssh/rsync calls reuse the socket without re-authenticating.
echo "==> Connecting to server (enter password once)..."
ssh -M -S "$SOCKET" -N -f -o ControlPersist=600 "$SERVER"
trap 'ssh -S "$SOCKET" -O exit "$SERVER" 2>/dev/null; rm -f "$SOCKET"' EXIT

echo "==> Syncing source to server..."
rsync -az --delete \
  --exclude='node_modules' \
  --exclude='tmp' \
  --exclude='log' \
  --exclude='.git' \
  --exclude='public/vite' \
  --exclude='public/packs' \
  -e "ssh -S $SOCKET" \
  . "$SERVER:$REMOTE_SRC/"

echo "==> Building image on server..."
ssh -S "$SOCKET" "$SERVER" "
  cd $REMOTE_SRC
  DOCKER_BUILDKIT=1 docker build -f docker/Dockerfile -t cbz-helpengine:latest . 2>&1 | tail -10
"

echo "==> Restarting containers..."
ssh -S "$SOCKET" "$SERVER" "
  cd $REMOTE_APP
  docker compose -f $COMPOSE up -d --no-deps --force-recreate rails sidekiq
"
echo ">>> Running database migrations..."
ssh -S "$SOCKET" "$SERVER" "
  cd $REMOTE_APP
  docker compose -f $COMPOSE exec -T rails bundle exec rails db:migrate
"
echo "==> Waiting for Rails to boot..."
sleep 25

echo "==> Checking status..."
ssh -S "$SOCKET" "$SERVER" "
  docker compose -f $REMOTE_APP/$COMPOSE logs --since=30s rails 2>&1 | \
    grep -v '^time=' | \
    grep -E 'Listening|Puma|Exiting|Error|NameError|ArgumentError' | \
    head -10
"
