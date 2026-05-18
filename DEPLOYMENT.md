# CBZ HelpEngine — Deployment Guide

## Architecture Overview

| Machine | OS | CPU | Role |
|---|---|---|---|
| Dev Mac | macOS | Apple Silicon (arm64) | Build & development |
| Production server | Ubuntu 22.04.5 LTS | x86_64 (amd64) | Runs the app |

### Why you can't just `docker build` locally for production

The Dockerfile uses Alpine Linux as the base image. Alpine uses musl libc, which means
native gems (notably `grpc`, pulled in by Dialogflow) **must be compiled from source** —
pre-built binary gems won't run on musl. The Dockerfile enforces this with:

```
RUN bundle config set --local force_ruby_platform true
```

Compiling gRPC from source under QEMU emulation (arm64 Mac → amd64 target) exhausts
Docker Desktop's memory and fails. The solution is to **build directly on the production
server** so Docker compiles natively with no emulation overhead.

---

## Prerequisites

### Dev Mac
- Docker Desktop
- `rsync` (built into macOS)
- `scp` (built into macOS)

### Production server
- Docker Engine + Docker Compose v2 (`docker compose` not `docker-compose`)
- SSH access (`itdevtd@192.168.230.54`)
- ~15 GB free disk space for the build

---

## First-time deployment

### 1. Prepare the environment file

Copy `.env.production` to the server:

```bash
scp .env.production itdevtd@192.168.230.54:~/cbz-helpengine/.env
```

The file lives at `~/cbz-helpengine/.env` on the server. Key values to review/update:

| Variable | Notes |
|---|---|
| `FRONTEND_URL` | Must match the IP/hostname users access the app from |
| `POSTGRES_PASSWORD` | Strong random password |
| `REDIS_PASSWORD` | Strong random password |
| `SECRET_KEY_BASE` | 128-char hex string — generate with `openssl rand -hex 64` |
| `SMTP_*` | CBZ mail relay settings |
| `ACTIVE_RECORD_ENCRYPTION_*` | Generate after first boot (see step 5) |

### 2. Copy the compose file

```bash
scp docker-compose.production.yaml itdevtd@192.168.230.54:~/cbz-helpengine/
```

### 3. Build the image on the server

Sync the source code (this takes ~1 minute over LAN):

```bash
cd "/path/to/chatwoot"
rsync -az --exclude='node_modules' --exclude='tmp' --exclude='log' \
  . itdevtd@192.168.230.54:~/cbz-source/
```

SSH in and build:

```bash
ssh itdevtd@192.168.230.54
cd ~/cbz-source
docker build -f docker/Dockerfile -t cbz-helpengine:latest . 2>&1 | tee ~/cbz-build.log
```

Build time: ~25–35 minutes (gRPC compilation is the long step). You can tail progress:

```bash
tail -f ~/cbz-build.log
```

> **If the build fails with `Permission denied` on `apk update`**, it is a transient Alpine
> CDN issue. Just re-run the `docker build` command — it will pick up cached layers and
> skip completed steps.

### 4. Start the stack

```bash
cd ~/cbz-helpengine
docker compose -f docker-compose.production.yaml up -d
```

Wait ~20 seconds for postgres and redis to initialise, then run the database setup
(first deploy only):

```bash
docker compose -f docker-compose.production.yaml exec rails bundle exec rails db:chatwoot_prepare
```

The app is now accessible at `http://192.168.230.54:3000`.

### 5. Generate Active Record Encryption keys (first deploy only)

```bash
docker compose -f docker-compose.production.yaml exec rails bundle exec rails db:encryption:init
```

Copy the three printed values into `~/cbz-helpengine/.env`:

```bash
cat >> ~/cbz-helpengine/.env << 'EOF'

ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=<value>
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=<value>
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=<value>
EOF
```

Also update `.env.production` in this repo so they stay in sync, then restart:

```bash
docker compose -f docker-compose.production.yaml restart rails sidekiq
```

### 6. Complete onboarding

Open `http://192.168.230.54:3000` in a browser and follow the setup wizard to create
the first super admin account.

---

## Subsequent deployments (updates)

When you make code changes and need to redeploy:

```bash
# 1. Sync updated source to server
cd "/path/to/chatwoot"
rsync -az --exclude='node_modules' --exclude='tmp' --exclude='log' \
  . itdevtd@192.168.230.54:~/cbz-source/

# 2. Rebuild image on server
ssh itdevtd@192.168.230.54
cd ~/cbz-source
docker build -f docker/Dockerfile -t cbz-helpengine:latest . 2>&1 | tee ~/cbz-build.log

# 3. Restart the stack
cd ~/cbz-helpengine
docker compose -f docker-compose.production.yaml up -d --no-deps rails sidekiq

# 4. Run any new migrations
docker compose -f docker-compose.production.yaml exec rails bundle exec rails db:migrate
```

> The `--no-deps` flag restarts only rails and sidekiq without touching postgres/redis,
> keeping the database running and avoiding downtime.

---

## Useful commands

```bash
# View live logs
docker compose -f docker-compose.production.yaml logs -f rails

# Check container status
docker compose -f docker-compose.production.yaml ps

# Open a Rails console
docker compose -f docker-compose.production.yaml exec rails bundle exec rails console

# Stop everything
docker compose -f docker-compose.production.yaml down

# Stop and wipe database volumes (DESTRUCTIVE)
docker compose -f docker-compose.production.yaml down -v
```

---

## nginx reverse proxy (pending)

nginx is not yet installed on the server (requires sudo). Once available, configure it
to proxy `http://192.168.230.54` → `http://localhost:3000` so the app is accessible
on port 80. SSL can be added with Let's Encrypt at that point.

---

## File locations on the server

| Path | Purpose |
|---|---|
| `~/cbz-helpengine/.env` | Production environment variables |
| `~/cbz-helpengine/docker-compose.production.yaml` | Compose stack definition |
| `~/cbz-source/` | Source code used for builds |
| `~/cbz-build.log` | Log from the last Docker build |
