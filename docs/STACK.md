<p align="center">
  <img src="../public/brand-assets/cbz-logo.png" alt="CBZ Bank" width="80">
</p>

<h1 align="center">HelpEngine</h1>
<p align="center"><strong>Technology Stack</strong></p>
<p align="center">Internal &nbsp;·&nbsp; Development Reference &nbsp;·&nbsp; Core Applications Development</p>

<p align="center">
  <img src="https://img.shields.io/badge/Ruby-3.4.4-CC342D?style=flat-square&logo=ruby&logoColor=white" alt="Ruby">
  <img src="https://img.shields.io/badge/Rails-7.1.5-CC0000?style=flat-square&logo=ruby-on-rails&logoColor=white" alt="Rails">
  <img src="https://img.shields.io/badge/Vue.js-3.5.12-4FC08D?style=flat-square&logo=vue.js&logoColor=white" alt="Vue.js">
  <img src="https://img.shields.io/badge/Vite-5.4.21-646CFF?style=flat-square&logo=vite&logoColor=white" alt="Vite">
  <img src="https://img.shields.io/badge/Tailwind_CSS-utility--first-38B2AC?style=flat-square&logo=tailwind-css&logoColor=white" alt="Tailwind CSS">
</p>
<p align="center">
  <img src="https://img.shields.io/badge/PostgreSQL-16_(pgvector)-316192?style=flat-square&logo=postgresql&logoColor=white" alt="PostgreSQL">
  <img src="https://img.shields.io/badge/Redis-alpine-DC382D?style=flat-square&logo=redis&logoColor=white" alt="Redis">
  <img src="https://img.shields.io/badge/Sidekiq-%E2%89%A5_7.3.1-B81C2B?style=flat-square" alt="Sidekiq">
  <img src="https://img.shields.io/badge/Docker-Compose_v2-2496ED?style=flat-square&logo=docker&logoColor=white" alt="Docker">
  <img src="https://img.shields.io/badge/nginx-proxy-009639?style=flat-square&logo=nginx&logoColor=white" alt="nginx">
</p>
<p align="center">
  <img src="https://img.shields.io/badge/Node.js-24.x-339933?style=flat-square&logo=node.js&logoColor=white" alt="Node.js">
  <img src="https://img.shields.io/badge/pnpm-10.x-F69220?style=flat-square&logo=pnpm&logoColor=white" alt="pnpm">
  <img src="https://img.shields.io/badge/Ubuntu-22.04_LTS-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu">
</p>

---


## Summary

| Layer | Technology | Version |
|---|---|---|
| Application framework | Ruby on Rails | 7.1.5 |
| Language (backend) | Ruby | 3.4.4 |
| Application server | Puma | bundled with Rails |
| Background jobs | Sidekiq | ≥ 7.3.1 |
| Job scheduling | sidekiq-cron | ≥ 1.12.0 |
| Frontend framework | Vue.js | 3.5.12 |
| State management | Pinia | 3.0.4 |
| Frontend router | Vue Router | 4.4.5 |
| Build tool | Vite (via vite-plugin-ruby) | 5.4.21 |
| CSS framework | Tailwind CSS | — |
| Primary database | PostgreSQL (pgvector) | 16 |
| Cache / queue broker | Redis | latest alpine |
| Containerisation | Docker + Docker Compose v2 | — |
| Web server / proxy | nginx | — |
| Runtime (Node) | Node.js | 24.x |
| Package manager (JS) | pnpm | 10.x |
| OS (production) | Ubuntu 22.04.5 LTS | — |

---

## Backend

### Ruby on Rails 7.1

Full-stack MVC framework providing:
- REST API (JSON) under `/api/v1/`
- Enterprise API under `/enterprise/api/v1/`
- ActionCable WebSocket server at `/cable`
- Background job integration via ActiveJob → Sidekiq
- Active Storage for file attachment management
- Active Record with PostgreSQL

### Puma

Multi-threaded application server. Configured via `config/puma.rb`. In production it
runs inside Docker bound to `127.0.0.1:3000` — nginx handles the public-facing connection.

Thread count is controlled by `RAILS_MAX_THREADS` (default: 5).

### Sidekiq

Background job processing. Runs as a separate Docker container using the same image as
Rails. Job configuration is in `config/sidekiq.yml`.

Key job categories:
- Outbound channel messages (WhatsApp, email)
- Webhook processing and retries
- Automation rule execution
- Report aggregation
- Scheduled maintenance tasks (via sidekiq-cron)

Sidekiq uses Redis as its queue backend. The web UI is available at
`/monitoring/sidekiq` (super admin only).

### Key Ruby gems

| Gem | Purpose |
|---|---|
| `devise_token_auth` | Token-based authentication for API clients |
| `pundit` | Authorization / policy layer |
| `redis` / `redis-namespace` | Redis client and key namespacing |
| `grpc` | gRPC client (Dialogflow integration) |
| `pg` | PostgreSQL adapter |
| `pgvector` | Vector similarity search for AI features |
| `vite_rails` | Vite integration for asset compilation |
| `sidekiq` | Background job processing |
| `sidekiq-cron` | Cron-style scheduled jobs |
| `sentry-ruby` | Error tracking |
| `newrelic_rpm` | Application performance monitoring |

---

## Frontend

### Vue 3 (Composition API)

All UI is built with Vue 3 using the `<script setup>` Composition API style. Components
follow PascalCase naming. The codebase is undergoing a migration from Options API to
Composition API — new components use `components-next/`.

### Pinia

State management library (Vue 3 successor to Vuex). Stores are located in
`app/javascript/dashboard/store/`.

### Vite

Frontend build tool replacing Webpack. Integrated with Rails via `vite_rails` gem.
Configuration is in `vite.config.mts`. In production, compiled assets are output to
`public/vite/` and served by nginx/Rails.

### Tailwind CSS

Utility-first CSS framework. All styling uses Tailwind classes — no custom CSS or
scoped styles. Configuration is in `tailwind.config.js`.

### i18n

All UI strings use Vue i18n — no hardcoded strings in templates. English translations
are in `app/javascript/shared/i18n/locale/en.json`. Other languages are community-maintained.

---

## Database

### PostgreSQL 16 with pgvector

Primary data store for all application data: accounts, conversations, messages,
contacts, inboxes, agents, reports.

The `pgvector` extension enables vector similarity search used by AI/Captain features.

Database name: `cbz_helpengine`

Runs in Docker using the `pgvector/pgvector:pg16` image. Data persisted in a named
Docker volume (`postgres_data`). Accessible only on `127.0.0.1:5432`.

### Redis (Alpine)

Used for two distinct purposes:

1. **Sidekiq queues** — job data serialised as JSON stored in Redis lists
2. **ActionCable pub/sub** — real-time WebSocket message broadcasting

Password-protected. Accessible only on `127.0.0.1:6379`.

---

## Infrastructure

### Docker Compose

The production stack is defined in `docker-compose.production.yaml`. Four services:

| Service | Image | Role |
|---|---|---|
| `rails` | `cbz-helpengine:latest` | Puma web server |
| `sidekiq` | `cbz-helpengine:latest` | Background job worker |
| `postgres` | `pgvector/pgvector:pg16` | Primary database |
| `redis` | `redis:alpine` | Queue broker and pub/sub |

`rails` and `sidekiq` share the same custom image but use different entrypoints.

Puma is bound to `127.0.0.1:3000` (not `0.0.0.0`) — it is never directly reachable
from the network. All external traffic must pass through nginx first.

### Custom Docker image

Built from `docker/Dockerfile` using Alpine Linux as the base. Key characteristics:

- Alpine (musl libc) — native gems compile from source (`force_ruby_platform true`)
- Multi-stage: Ruby gems compiled in build stage, assets compiled in asset stage
- Must be built on the production server (amd64) — cross-compilation from Apple Silicon
  via QEMU exhausts memory during gRPC compilation
- Build time: ~25–35 minutes (gRPC source compilation is the bottleneck)

### nginx (local — Ubuntu server)

Installed on the Ubuntu host (outside Docker) as the TLS termination layer and reverse proxy.

- Config: `/etc/nginx/sites-available/cbz-helpengine` (symlinked to `sites-enabled`)
- Certificate: `/etc/nginx/ssl/cbz.co.zw.crt` and `cbz.co.zw.key` (`*.cbz.co.zw` wildcard, DigiCert Private CA, expires Mar 15 2028)
- Redirects HTTP → HTTPS
- Terminates TLS — proxies to Puma over plain HTTP on `127.0.0.1:3000`
- Handles WebSocket `Upgrade`/`Connection` headers for `/cable` with a 3600s read timeout
- Provides gzip compression and request buffering

### nginx (DMZ — Windows, pg.cbz.co.zw)

Internet-facing reverse proxy that acts as the public entry point for CBZ HelpEngine.

- Proxies upstream to `https://192.168.230.54` (HTTPS — not plain HTTP)
- Uses an **allowlist** approach: only specific paths are forwarded; all others are blocked at the DMZ
- Provides the public webhook URL for Meta WhatsApp callbacks (`/webhooks/whatsapp/...`)
- See [SECURITY.md](SECURITY.md) for the full path allowlist

---

## Development tooling

| Tool | Purpose |
|---|---|
| `overmind` | Process manager for running Rails + Vite + Sidekiq concurrently |
| `rbenv` | Ruby version management |
| `pnpm` | Fast, disk-efficient Node package manager |
| `RuboCop` | Ruby linter (150 char line limit) |
| `ESLint` | JavaScript/Vue linter (Airbnb base + Vue 3 recommended) |
| `RSpec` | Ruby test framework |
| `Jest` | JavaScript test framework |
| `Cypress` | End-to-end browser testing |

### Running locally

```bash
# Install dependencies
bundle install && pnpm install

# Start all processes (Rails, Vite, Sidekiq)
overmind start -f Procfile.dev

# Or with pnpm shortcut
pnpm dev
```

---

## Email

Outbound email is delivered via the CBZ internal mail relay:

| Setting | Value |
|---|---|
| SMTP host | 192.168.145.38 |
| Port | 25 |
| TLS | Disabled (internal relay) |
| From address | Contact Centre \<contactcentre@cbz.co.zw\> |

---

## Monitoring

| Tool | Access |
|---|---|
| Sidekiq Web UI | `/monitoring/sidekiq` (super admin only) |
| Health check endpoint | `/health` |
| Rails logs | `docker compose logs -f rails` |
| Sidekiq logs | `docker compose logs -f sidekiq` |
