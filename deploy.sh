#!/bin/bash
set -e

SERVER="itdevtd@192.168.230.54"
REMOTE_SRC="~/cbz-source"
REMOTE_APP="~/cbz-helpengine"
COMPOSE="docker-compose.production.yaml"

echo "==> Syncing source to server..."
rsync -az --delete \
  --exclude='node_modules' \
  --exclude='tmp' \
  --exclude='log' \
  --exclude='.git' \
  . "$SERVER:$REMOTE_SRC/"

echo "==> Building image on server..."
ssh "$SERVER" "
  cd $REMOTE_SRC
  DOCKER_BUILDKIT=1 docker build -f docker/Dockerfile -t cbz-helpengine:latest . 2>&1 | tail -10
"

echo "==> Restarting containers..."
ssh "$SERVER" "
  cd $REMOTE_APP
  docker compose -f $COMPOSE up -d --no-deps --force-recreate rails sidekiq
"

echo "==> Waiting for Rails to boot..."
sleep 25

echo "==> Checking status..."
ssh "$SERVER" "
  docker compose -f $REMOTE_APP/$COMPOSE logs --since=30s rails 2>&1 | \
    grep -v '^time=' | \
    grep -E 'Listening|Puma|Exiting|Error|NameError|ArgumentError' | \
    head -10
"
