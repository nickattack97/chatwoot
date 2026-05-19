# CBZ HelpEngine — Security Configuration

## Network isolation

All internal services (Rails, PostgreSQL, Redis) are bound to `127.0.0.1` and are
not reachable from the network. The only ports open on the server are:

| Port | Service | Accessible from |
|---|---|---|
| 22/tcp | SSH | CBZ network (UFW allowed) |
| 80/tcp | nginx HTTP | CBZ network (redirects to HTTPS) |
| 443/tcp | nginx HTTPS | CBZ network + DMZ |

Port 3000 (Puma), 5432 (PostgreSQL), and 6379 (Redis) are all bound to localhost only.

UFW firewall is active and configured to allow only ports 22, 80, and 443.

---

## TLS / SSL

| Connection | Protocol | Certificate |
|---|---|---|
| Browser → DMZ (pg.cbz.co.zw) | TLS 1.2 / 1.3 | Managed by IT (DMZ) |
| DMZ → server (192.168.230.54) | TLS 1.2 / 1.3 | `*.cbz.co.zw` wildcard — DigiCert Private CA |
| Browser → server (internal direct) | TLS 1.2 / 1.3 | `*.cbz.co.zw` wildcard — DigiCert Private CA |
| nginx → Puma (local) | HTTP (plaintext) | N/A — localhost only |
| App → PostgreSQL | Plaintext | N/A — localhost only |
| App → Redis | Plaintext | N/A — localhost only |

The wildcard certificate (`*.cbz.co.zw`) is issued by the CBZ internal CA
(DigiCert Private SSL SHA256 CA - G2) and expires **March 15, 2028**.

nginx is configured with:

```nginx
ssl_protocols       TLSv1.2 TLSv1.3;
ssl_ciphers         HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers on;
```

Weak ciphers (MD5, anonymous) and SSLv3/TLS 1.0/1.1 are disabled.

---

## DMZ path allowlist

The internet-facing DMZ nginx only forwards requests for specific application paths.
All other requests are blocked at the DMZ level before reaching the internal network.

Paths exposed externally:

- `/app`, `/auth`, `/api`, `/enterprise` — application UI and API
- `/public` — Public API (CSAT survey submission, widget API)
- `/cable` — WebSocket (ActionCable)
- `/webhooks/whatsapp` — WhatsApp webhook callbacks from Meta
- `/bot` — Facebook Messenger webhook
- `/widget` — Embeddable chat widget
- `/survey` — CSAT survey links sent to customers
- `/rails/active_storage` — File attachments
- `/vite`, `/brand-assets`, `/dashboard`, `/integrations` — Static assets
- `/.well-known` — Mobile app deep-link verification
- `/health` — Health check

Paths **not** exposed externally (blocked at DMZ):

- `/super_admin` — Super admin panel
- `/monitoring/sidekiq` — Sidekiq web UI
- Direct database or Redis access (not possible — localhost only)

---

## Authentication

### User authentication

Users authenticate via email and password. The API uses `devise_token_auth` which
issues short-lived session tokens. Each user also has a permanent API token for
programmatic access (visible in Settings → Profile).

### Password policy

Password requirements are enforced by Devise. Minimum length is 6 characters.
Password reset is via email link sent to the registered address.

### Multi-factor authentication (MFA)

MFA support is available and requires `ACTIVE_RECORD_ENCRYPTION_*` keys to be set
in the environment. These keys are used to encrypt MFA secrets at rest.

### Account signup

Public account signup is disabled (`ENABLE_ACCOUNT_SIGNUP=false`). New agents must
be invited by an administrator from within the application.

---

## Secrets management

Secrets are stored exclusively in `~/cbz-helpengine/.env` on the production server.
This file:

- Is not committed to the repository
- Is readable only by the `itdevtd` user
- Should be backed up securely (encrypted) separate from the server

Secrets in use:

| Secret | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Rails session signing and encryption |
| `POSTGRES_PASSWORD` | Database access |
| `REDIS_PASSWORD` | Redis authentication |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | Encrypts MFA secrets and sensitive attributes |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | Deterministic encryption for searchable fields |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Key derivation for encryption |

If any of these secrets are compromised, rotate them and restart the stack.
Rotating `SECRET_KEY_BASE` invalidates all existing user sessions (forces re-login).

---

## WhatsApp webhook security

Incoming webhook payloads from Meta are validated using HMAC-SHA256 signature
verification. Each WhatsApp inbox has a `webhook_verify_token` and the app verifies
the `X-Hub-Signature-256` header on every inbound POST request.

---

## Redis security

Redis is password-protected via `requirepass` in the Docker command:

```yaml
command: ["sh", "-c", "redis-server --requirepass \"$REDIS_PASSWORD\""]
```

The password is read from the `.env` file at container start. Redis is not accessible
outside `127.0.0.1`.

---

## Database security

PostgreSQL is accessible only on `127.0.0.1:5432`. The database user is `postgres`
with a strong random password stored in `.env`. No external database access is possible.

---

## Container security

- All containers run as non-root users (enforced by the Alpine base image setup)
- The `storage_data` volume is the only persistent volume mounted into app containers
- Postgres and Redis data are in separate named volumes, not bind-mounted from the host
- The Docker socket is not mounted into any container

---

## Logging

Application logs are written to stdout and captured by Docker:

```bash
# View Rails logs
docker compose -f docker-compose.production.yaml logs -f rails

# View Sidekiq logs
docker compose -f docker-compose.production.yaml logs -f sidekiq
```

Log level is controlled by `LOG_LEVEL=info` in `.env`. Set to `debug` for
troubleshooting (generates significantly more output).

---

## Certificate renewal

The `*.cbz.co.zw` wildcard certificate expires **March 15, 2028**. Renewal process:

1. Obtain the new PFX file from the certificate authority
2. Extract cert and key on your Mac:
   ```bash
   openssl pkcs12 -in wildcard_internal.pfx -clcerts -nokeys -out cbz.co.zw.crt -passin pass:<password>
   openssl pkcs12 -in wildcard_internal.pfx -nocerts -nodes  -out cbz.co.zw.key -passin pass:<password>
   ```
3. Copy to the server and replace the existing files:
   ```bash
   scp cbz.co.zw.crt cbz.co.zw.key itdevtd@192.168.230.54:~/
   sudo mv ~/cbz.co.zw.crt /etc/nginx/ssl/
   sudo mv ~/cbz.co.zw.key /etc/nginx/ssl/
   sudo chmod 644 /etc/nginx/ssl/cbz.co.zw.crt
   sudo chmod 600 /etc/nginx/ssl/cbz.co.zw.key
   sudo nginx -t && sudo systemctl reload nginx
   ```
4. No application restart required — nginx reloads the cert without downtime

---

## Security checklist (post-deployment)

- [x] Port 3000 bound to localhost only
- [x] Ports 5432 (PostgreSQL) and 6379 (Redis) bound to localhost only
- [x] UFW firewall active — only ports 22, 80, 443 open
- [x] TLS 1.2/1.3 only — older protocols disabled
- [x] Weak SSL ciphers disabled
- [x] Public account signup disabled
- [x] Redis password-protected
- [x] Strong random passwords for PostgreSQL and Redis
- [x] Secrets not committed to repository
- [x] DMZ path allowlist restricts external access
- [ ] Internal DNS entry for `helpengine.cbz.co.zw` (pending IT)
- [ ] CBZ root CA installed on all client machines (pending IT)
- [ ] WhatsApp permanent system user token configured (replace temporary token)
