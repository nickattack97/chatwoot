# CBZ HelpEngine — UserConnect IAM Integration

**Status:** Planning  
**Author:** CBZ IT Department  
**Last updated:** 2026-06-12

## UserConnect System Registration

CBZ HelpEngine is registered in UserConnect as:

| Field | Value |
|---|---|
| **System name** | CBZ HelpEngine |
| **System ID** | `20031` |
| **Roles** | `Administrator` → Chatwoot `administrator`; `Agent` → Chatwoot `agent` |
| **Permissions** | None — Chatwoot manages its own authorisation internally |

### Environments

Two environments are registered (both currently typed as UAT/Staging):

| Environment | Purpose | Frontend URL | Backend URL | DB Host | DB Name |
|---|---|---|---|---|---|
| **External** | Internet-facing access via DMZ proxy | `https://pg.cbz.co.zw` | `https://pg.cbz.co.zw` | `192.168.230.54` | `cbz_helpengine` |
| **Internal** | Direct access on CBZ network (no DNS entry for helpengine.cbz.co.zw) | `https://192.168.230.54` | `https://192.168.230.54` | `192.168.230.54` | `cbz_helpengine` |

> Both environments point to the same server and database. The distinction exists because internal users access the app directly by IP while external users go through the DMZ nginx proxy at `pg.cbz.co.zw`. There is currently no DNS entry for `helpengine.cbz.co.zw`.

**`FRONTEND_URL` implication:** The `FRONTEND_URL` in `.env.production` on the server must be set to `https://pg.cbz.co.zw` — this is the URL Rails uses to build the SAML callback redirect after UserConnect authentication. Using the bare IP would break the SSO flow for external users and produce incorrect callback URLs.

---

## Overview

CBZ HelpEngine (Chatwoot) will delegate authentication to **CBZ UserConnect**, the bank's central identity platform. UserConnect is a REST-based SSO service that supports local credential validation, OTP two-factor authentication, and Microsoft Entra ID federation via SAML 2.0.

Two complementary auth paths are implemented:

| Path | Mechanism | Use case |
|---|---|---|
| **Path 1 — SSO redirect** | SAML via UserConnect → Entra ID | Primary: all staff with Microsoft AD accounts |
| **Path 2 — Credential proxy** | Username/password forwarded to UserConnect REST API | Fallback: service accounts or users without Entra access |

Both paths converge at the same session-creation point in Chatwoot's existing SSO token mechanism, keeping the implementation minimal.

---

## Architecture

### Path 1 — SSO Redirect (primary)

```
┌─────────────────────────────────────────────────────────────────────┐
│ Browser                                                             │
└────────────────────────────┬────────────────────────────────────────┘
                             │ 1. Click "Sign in with CBZ SSO"
                             ▼
                   GET /auth/uc_sso (Chatwoot)
                             │
                             │ 2. redirect 302
                             ▼
          UserConnect  /api/v1/auth/saml/login?systemId={id}
                             │
                             │ 3. SAML AuthnRequest redirect
                             ▼
                   Microsoft Entra ID login page
                             │
                             │ 4. User authenticates with CBZ AD credentials
                             ▼
          UserConnect  /api/v1/auth/saml/acs  (SAML ACS)
                             │
                             │ 5. UC validates assertion, issues UC JWT
                             │    redirects to FrontendCallbackUrl:
                             ▼
   GET /auth/uc_callback?token={uc_jwt}&systemId={id}  (Chatwoot)
                             │
                             │ 6. Chatwoot decodes UC JWT
                             │    find-or-create user by email
                             │    map UC role → Chatwoot role
                             │    generate short-lived sso_auth_token
                             │    redirect to /app/login?email=…&sso_auth_token=…
                             ▼
                   Chatwoot login page auto-submits
                             │
                             │ 7. POST /auth/sign_in { email, sso_auth_token }
                             │    existing SSO session mechanism validates token
                             ▼
                   Chatwoot dashboard  ✓
```

### Path 2 — Credential Proxy (fallback)

```
┌─────────────────────────────────────────────────────────────────────┐
│ Browser — Chatwoot login form (username / password)                 │
└────────────────────────────┬────────────────────────────────────────┘
                             │ 1. POST /api/v1/auth/uc_sign_in
                             ▼
           Chatwoot rails container (192.168.230.54)
                             │
                             │ 2. POST {UC_BASE_URL}/api/v1/auth/login
                             │      { username, password, systemId }
                             ▼
                       CBZ UserConnect API
                             │
              ┌──────────────┴──────────────┐
              │ success                      │ OTP required
              ▼                              ▼
   UC JWT returned               { otp: "OTP sent to email" }
              │                              │
              │                    Frontend shows OTP input
              │                              │
              │                    POST /api/v1/auth/uc_verify_otp
              │                              │
              │                    GET {UC}/login-with-otp/{u}/{otp}/{id}
              │                              │
              └──────────────┬───────────────┘
                             │ UC JWT in hand
                             │
                             │ 3. Decode UC JWT → email, name, roles
                             │    find-or-create Chatwoot user
                             │    issue Devise token
                             ▼
                   Return { token, ... }  (standard Chatwoot auth response)
```

---

## Prerequisites

Before writing any code, the following must be in place:

### 1. Register CBZ HelpEngine as a system in UserConnect ✅

**Completed.** CBZ HelpEngine is registered with system ID **`20031`** and has two roles: `Administrator` and `Agent`. No permissions are needed on either role.

### 2. Link agent/admin users to the HelpEngine system

Each staff member who will use HelpEngine must have a `tblUserSystems` row linking their UC account to the HelpEngine `systemId`. This can be done:
- Manually via the UserConnect admin portal: `PUT /admin/user-systems-mapping/{userId}/{systemId}/approve`
- Or automatically if SCIM provisioning is enabled (Entra assigns users to the Enterprise App → SCIM syncs them to UserConnect)

### 3. Update UserConnect's SAML FrontendCallbackUrl (Path 1 only)

In UserConnect's `appsettings.json`, add the HelpEngine callback URL to the allowed set:

```
Saml2:FrontendCallbackUrl = https://helpengine.cbz.co.zw/auth/uc_callback
```

UserConnect redirects here after Entra authentication, passing `?token={uc_jwt}&systemId={id}`.

### 4. Confirm network reachability

The Chatwoot Rails Docker container (`192.168.230.54`) must be able to reach the UserConnect API over HTTP/HTTPS. Verify with:

```bash
ssh itdevtd@192.168.230.54
docker compose -f docker-compose.production.yaml exec rails curl -s {UC_BASE_URL}/api/v1/systems
```

### 5. Update FRONTEND_URL in .env.production

The `FRONTEND_URL` environment variable drives all redirect URLs. Ensure it is set to the URL users actually browse to (not `http://192.168.230.54`):

```
FRONTEND_URL=https://helpengine.cbz.co.zw
```

---

## Configuration

Two new `InstallationConfig` keys and one environment variable are required.

### installation_config.yml additions

```yaml
- name: UC_BASE_URL
  value: ''
  display_title: 'UserConnect Base URL'
  description: 'Base URL of the CBZ UserConnect API (e.g. https://userconnect-api.cbz.co.zw)'

- name: UC_SYSTEM_ID
  value: ''
  display_title: 'UserConnect System ID'
  description: 'The system ID assigned to CBZ HelpEngine in UserConnect'

- name: UC_SSO_ENABLED
  value: 'false'
  display_title: 'UserConnect SSO Login'
  description: 'Enable the "Sign in with CBZ SSO" button (Path 1 — Entra redirect via UserConnect)'

- name: UC_CREDENTIAL_PROXY_ENABLED
  value: 'false'
  display_title: 'UserConnect Credential Proxy'
  description: 'Enable username/password login proxied through UserConnect (Path 2 — fallback)'
```

### Role mapping config

UC roles are scoped to a system as `{systemId}_{roleName}`. Chatwoot has two roles: `agent` and `administrator`. The default mapping:

| UserConnect role | Chatwoot role |
|---|---|
| `{id}_ADMIN` | `administrator` |
| `{id}_SYSADMIN` | `administrator` |
| `{id}_BUSINESS` | `administrator` |
| any other role | `agent` |

This mapping lives in a constant in `UserConnect::UserFinderService` and can be adjusted without DB changes.

---

## Backend Implementation

### New files

```
enterprise/
  app/
    services/
      userconnect/
        auth_service.rb          # HTTP client — talks to UserConnect REST API
        user_finder_service.rb   # find-or-create Chatwoot user from UC JWT claims
    controllers/
      enterprise/
        userconnect_auth_controller.rb  # SSO callback + credential proxy endpoints
```

### `UserConnect::AuthService`

Thin HTTP wrapper around the UserConnect API. All outbound calls go through here.

```ruby
# enterprise/app/services/userconnect/auth_service.rb

module UserConnect
  class AuthService
    class UnavailableError < StandardError; end
    class OtpRequiredError < StandardError
      attr_reader :message
      def initialize(msg) = super
    end
    class PasswordChangeRequiredError < StandardError; end

    def initialize
      @base_url  = GlobalConfigService.load('UC_BASE_URL', nil)
      @system_id = GlobalConfigService.load('UC_SYSTEM_ID', nil)
    end

    # Returns the raw UC JWT string on success.
    # Raises OtpRequiredError, PasswordChangeRequiredError, or
    #   UnauthorizedAccessException with a user-facing message on failure.
    def login(username, password)
      response = post('/api/v1/auth/login', {
        username: username,
        password: password,
        systemId: @system_id.to_i
      })

      body = parse(response)

      raise UnauthorizedError, extract_info(body) unless response.success?
      raise OtpRequiredError, body['otp']     if body.key?('otp')
      raise PasswordChangeRequiredError       if body.key?('expired') || body.key?('initial')

      body['token'] or raise UnavailableError, 'Unexpected response from UserConnect'
    end

    # Returns the raw UC JWT string on success.
    def verify_otp(username, otp)
      path     = "/api/v1/auth/login-with-otp/#{CGI.escape(username)}/#{CGI.escape(otp)}/#{@system_id}"
      response = get(path)
      body     = parse(response)

      raise UnauthorizedError, extract_info(body) || 'Invalid or expired OTP' unless response.success?

      body['token'] or raise UnavailableError, 'Unexpected response from UserConnect'
    end

    # Decodes a UC JWT without signature verification.
    # UC has already authenticated the user — we trust the claims.
    # Returns a hash with symbolised keys.
    def decode_token(uc_token)
      payload = JWT.decode(uc_token, nil, false).first
      {
        email:      payload['email'],
        username:   payload['userName'],
        first_name: payload['firstName'],
        surname:    payload['surname'],
        system_id:  payload['systemID'],
        roles:      Array(payload['roles'])
      }
    end

    private

    def post(path, body)
      conn.post(path, body.to_json, 'Content-Type' => 'application/json')
    rescue Faraday::Error => e
      raise UnavailableError, 'Unable to reach the authentication service'
    end

    def get(path)
      conn.get(path)
    rescue Faraday::Error => e
      raise UnavailableError, 'Unable to reach the authentication service'
    end

    def conn
      @conn ||= Faraday.new(url: @base_url) do |f|
        f.options.timeout      = 10
        f.options.open_timeout = 5
      end
    end

    def parse(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      {}
    end

    def extract_info(body)
      body.is_a?(Hash) ? body['info'] : nil
    end
  end
end
```

### `UserConnect::UserFinderService`

Handles the Chatwoot user side: find by email, create if absent, ensure account membership, map role.

```ruby
# enterprise/app/services/userconnect/user_finder_service.rb

module UserConnect
  class UserFinderService
    # Maps UC role suffix to Chatwoot AccountUser role.
    # Roles arrive as "{systemId}_{roleName}", e.g. "42_ADMIN".
    ADMIN_ROLES = %w[ADMIN SYSADMIN BUSINESS].freeze

    def initialize(claims)
      @claims    = claims
      @account   = Account.first  # CBZ HelpEngine is a single-account install
    end

    # Returns a persisted Chatwoot User, guaranteed to be a member of @account.
    def perform
      user = find_or_create_user
      ensure_account_membership(user)
      user
    end

    private

    def find_or_create_user
      User.from_email(@claims[:email]) || create_user
    end

    def create_user
      name = [@claims[:first_name], @claims[:surname]].compact.join(' ').presence ||
             @claims[:username] ||
             @claims[:email].split('@').first

      User.create!(
        email:        @claims[:email],
        name:         name,
        display_name: @claims[:first_name],
        provider:     'userconnect',
        uid:          @claims[:email],
        password:     SecureRandom.hex(32),
        confirmed_at: Time.current
      )
    end

    def ensure_account_membership(user)
      account_user = AccountUser.find_or_create_by!(user: user, account: @account)
      account_user.update!(role: chatwoot_role)
    end

    def chatwoot_role
      system_id = GlobalConfigService.load('UC_SYSTEM_ID', nil).to_s
      uc_role_suffix = @claims[:roles]
        .map { |r| r.start_with?("#{system_id}_") ? r[(system_id.length + 1)..] : nil }
        .compact
        .first

      ADMIN_ROLES.include?(uc_role_suffix&.upcase) ? 'administrator' : 'agent'
    end
  end
end
```

### `Enterprise::UserconnectAuthController`

Handles the two new HTTP endpoints. Both paths converge at `issue_sso_session` which uses the existing `sso_auth_token` mechanism — no new session logic required.

```ruby
# enterprise/app/controllers/enterprise/userconnect_auth_controller.rb

class Enterprise::UserconnectAuthController < ApplicationController
  skip_before_action :authenticate_user!

  UC_PASSWORD_CHANGE_URL = "#{ENV.fetch('UC_PORTAL_URL', '#')}/change-password".freeze

  # ── Path 1: SSO redirect initiation ────────────────────────────────────────

  # GET /auth/uc_sso
  # Redirects the browser to UserConnect's SAML login endpoint.
  def sso_initiate
    return render_uc_disabled unless uc_sso_enabled?

    uc_base    = GlobalConfigService.load('UC_BASE_URL', nil)
    system_id  = GlobalConfigService.load('UC_SYSTEM_ID', nil)
    redirect_to "#{uc_base}/api/v1/auth/saml/login?systemId=#{system_id}",
                allow_other_host: true
  end

  # GET /auth/uc_callback?token=…&systemId=…
  # Receives the UC JWT after Entra authentication.
  def sso_callback
    return render_uc_disabled unless uc_sso_enabled?

    uc_token = params[:token]
    return redirect_to_login(error: 'uc-missing-token') if uc_token.blank?

    claims = auth_service.decode_token(uc_token)
    user   = UserConnect::UserFinderService.new(claims).perform

    issue_sso_session(user)
  rescue StandardError => e
    Rails.logger.error "[UserConnect] SSO callback error: #{e.message}"
    redirect_to_login(error: 'uc-authentication-failed')
  end

  # ── Path 2: Credential proxy ────────────────────────────────────────────────

  # POST /api/v1/auth/uc_sign_in
  # Body: { username, password }
  def credential_sign_in
    return render_uc_disabled unless uc_credential_proxy_enabled?

    uc_token = auth_service.login(params[:username], params[:password])
    claims   = auth_service.decode_token(uc_token)
    user     = UserConnect::UserFinderService.new(claims).perform

    token = user.create_token
    user.save!

    render json: build_auth_response(user, token), status: :ok

  rescue UserConnect::AuthService::OtpRequiredError => e
    render json: { requiresOtp: true, otpMessage: e.message }, status: :ok

  rescue UserConnect::AuthService::PasswordChangeRequiredError
    render json: {
      error: 'Your password has expired. Please update it in the CBZ UserConnect portal.',
      redirect: UC_PASSWORD_CHANGE_URL
    }, status: :unauthorized

  rescue UserConnect::AuthService::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable

  rescue => e
    render json: { error: e.message }, status: :unauthorized
  end

  # POST /api/v1/auth/uc_verify_otp
  # Body: { username, otp }
  def credential_verify_otp
    return render_uc_disabled unless uc_credential_proxy_enabled?

    uc_token = auth_service.verify_otp(params[:username], params[:otp])
    claims   = auth_service.decode_token(uc_token)
    user     = UserConnect::UserFinderService.new(claims).perform

    token = user.create_token
    user.save!

    render json: build_auth_response(user, token), status: :ok

  rescue UserConnect::AuthService::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable

  rescue => e
    render json: { error: e.message }, status: :unauthorized
  end

  private

  # Issues an sso_auth_token and redirects the browser to the login page.
  # The login page detects the token in the URL and auto-POSTs to /auth/sign_in,
  # which is handled by DeviseOverrides::SessionsController#process_sso_auth_token.
  def issue_sso_session(user)
    sso_token = user.generate_sso_auth_token
    user.save!

    frontend_url = ENV.fetch('FRONTEND_URL', '')
    redirect_to "#{frontend_url}/app/login?email=#{CGI.escape(user.email)}&sso_auth_token=#{sso_token}",
                allow_other_host: true
  end

  def auth_service
    @auth_service ||= UserConnect::AuthService.new
  end

  def uc_sso_enabled?
    GlobalConfigService.load('UC_SSO_ENABLED', 'false').to_s == 'true'
  end

  def uc_credential_proxy_enabled?
    GlobalConfigService.load('UC_CREDENTIAL_PROXY_ENABLED', 'false').to_s == 'true'
  end

  def render_uc_disabled
    render json: { error: 'UserConnect auth is not enabled' }, status: :forbidden
  end

  def redirect_to_login(error:)
    frontend_url = ENV.fetch('FRONTEND_URL', '')
    redirect_to "#{frontend_url}/app/login?error=#{error}", allow_other_host: true
  end

  def build_auth_response(user, token)
    # Mirrors DeviseTokenAuth's standard response shape so the frontend
    # can handle it identically to a normal sign-in response.
    {
      data: {
        id:           user.id,
        email:        user.email,
        name:         user.name,
        access_token: token.token,
        token_type:   'Bearer',
        uid:          user.email,
        client:       token.client
      }
    }
  end
end
```

### Routes additions

```ruby
# config/routes.rb — add alongside existing auth routes

# UserConnect IAM — SSO redirect (Path 1)
get  'auth/uc_sso',      to: 'enterprise/userconnect_auth#sso_initiate'
get  'auth/uc_callback', to: 'enterprise/userconnect_auth#sso_callback'

# UserConnect IAM — credential proxy (Path 2)
namespace :api do
  namespace :v1 do
    post 'auth/uc_sign_in',     to: 'enterprise/userconnect_auth#credential_sign_in'
    post 'auth/uc_verify_otp',  to: 'enterprise/userconnect_auth#credential_verify_otp'
  end
end
```

---

## Frontend Implementation

### Login page changes (`v3/views/login/Index.vue`)

Two additions to the existing login page:

**1. "Sign in with CBZ SSO" button**

Shown when `globalConfig.ucSsoEnabled` is true. Navigates directly to `/auth/uc_sso` — no JS fetch needed, the browser handles the redirect chain.

```vue
<a
  v-if="globalConfig.ucSsoEnabled"
  href="/auth/uc_sso"
  class="w-full flex items-center justify-center gap-2 border border-n-200 dark:border-n-700 rounded-lg py-2.5 text-sm font-medium hover:bg-n-50 dark:hover:bg-n-800 transition-colors"
>
  <img src="/brand-assets/cbz-logo.png" class="h-5 w-5" alt="" />
  Sign in with CBZ SSO
</a>
```

**2. Auto-submit on SSO callback**

When the browser lands on `/app/login?email=…&sso_auth_token=…` (redirected from `/auth/uc_callback`), the login page should silently POST to `/auth/sign_in` and complete the session — the user never sees the form. This is already handled by the existing `sso_auth_token` flow; the login page just needs to detect the query params on mount and trigger the existing `signIn` action.

**3. OTP step (Path 2 only)**

If `POST /api/v1/auth/uc_sign_in` returns `{ requiresOtp: true }`, show an OTP input field and call `POST /api/v1/auth/uc_verify_otp`. The existing MFA step component can be repurposed for this UI.

### globalConfig additions

```javascript
// shared/store/globalConfig.js — add to destructured window.globalConfig
UC_SSO_ENABLED: ucSsoEnabled,
UC_CREDENTIAL_PROXY_ENABLED: ucCredentialProxyEnabled,
```

These are set by the Rails view helper that builds `window.globalConfig` from `InstallationConfig`, just like all other global config values.

---

## Data flow summary

```
UC JWT claims → Chatwoot user
─────────────────────────────────────────────
email           → User.email (lookup key)
firstName       → User.display_name
firstName + surname → User.name (on create)
email           → User.uid (on create)
"userconnect"   → User.provider (on create)
{id}_ADMIN etc  → AccountUser.role (admin or agent)
```

Existing users (created before UC integration) are matched by email. Their `provider` is updated to `userconnect` on first SSO login.

---

## Security considerations

- **UC JWT is decoded without signature verification.** This is intentional and matches the WA Bot Engine pattern. The JWT was issued by UC after a successful Entra authentication — UC is trusted infrastructure on the CBZ internal network. If the production server were ever exposed externally, the `/auth/uc_callback` endpoint should add HMAC or nonce validation.
- **`sso_auth_token` is short-lived.** The existing Chatwoot mechanism generates a one-time token that is invalidated immediately after use (`invalidate_sso_auth_token`).
- **Users cannot bypass role mapping.** The UC role suffix extracted from the JWT is compared against a fixed constant (`ADMIN_ROLES`). Roles not on the list default to `agent`.
- **Credential proxy does not log passwords.** The `params[:password]` value is forwarded to UC and never stored or logged in Chatwoot.
- **`/auth/uc_callback` is internal-only.** The DMZ nginx on `pg.cbz.co.zw` does not currently expose `/auth/*` beyond `/auth` prefix. Confirm the callback URL is routed correctly (see Deployment section).

---

## Deployment checklist

### Server (`192.168.230.54`)

```bash
ssh itdevtd@192.168.230.54
cd ~/cbz-helpengine

# After deploying the new image:

# 1. Seed the new InstallationConfig keys
docker compose -f docker-compose.production.yaml exec rails bundle exec rails runner "
  [
    ['UC_BASE_URL',                  'http://192.168.3.173:9700'],
    ['UC_SYSTEM_ID',                 '20031'],
    ['UC_SSO_ENABLED',               'false'],   # enable after testing
    ['UC_CREDENTIAL_PROXY_ENABLED',  'false'],   # enable after testing
  ].each do |name, value|
    InstallationConfig.find_or_initialize_by(name: name).tap { |c| c.value = value; c.save! }
  end
  GlobalConfig.clear_cache
  puts 'Done.'
"

# 2. Verify UserConnect is reachable from the container
docker compose -f docker-compose.production.yaml exec rails \
  curl -s https://<userconnect-api-host>/api/v1/systems | head -c 200
```

### DMZ nginx (`pg.cbz.co.zw`)

The `/auth` location block already exists. Verify that `/auth/uc_callback` passes through (no path-specific blocklist). If the DMZ only allows `/auth/sign_in`, add:

```nginx
location /auth/uc_sso {
    proxy_pass https://192.168.230.54;
    # ... standard proxy headers
}

location /auth/uc_callback {
    proxy_pass https://192.168.230.54;
    # ... standard proxy headers
}
```

### UserConnect (CBZ IT to action)

- Register CBZ HelpEngine system → note `systemId`
- Create roles for the system: `ADMIN`, `AGENT`
- Set `Saml2:FrontendCallbackUrl` to include `https://helpengine.cbz.co.zw/auth/uc_callback`
- Link initial users (IT admins) to the HelpEngine system for testing

### Enable flags (after smoke test)

```bash
docker compose -f docker-compose.production.yaml exec rails bundle exec rails runner "
  InstallationConfig.find_by(name: 'UC_SSO_ENABLED').update!(value: 'true')
  InstallationConfig.find_by(name: 'UC_CREDENTIAL_PROXY_ENABLED').update!(value: 'true')
  GlobalConfig.clear_cache
  puts 'Enabled.'
"
```

---

## Testing plan

### Unit tests

| Service | Test cases |
|---|---|
| `UserConnect::AuthService#login` | Success → returns JWT; OTP challenge → raises `OtpRequiredError`; expired password → raises `PasswordChangeRequiredError`; UC unreachable → raises `UnavailableError` |
| `UserConnect::AuthService#verify_otp` | Success → returns JWT; invalid OTP → raises `UnauthorizedError` |
| `UserConnect::AuthService#decode_token` | Extracts all expected claims correctly |
| `UserConnect::UserFinderService#perform` | Creates new user; matches existing user by email; maps `ADMIN` role correctly; maps `AGENT` role correctly; sets `provider: 'userconnect'` |

### Integration / smoke test (on staging before production)

1. **Path 1 (SSO):** Click "Sign in with CBZ SSO" → redirects to Entra login → authenticate with CBZ AD credentials → lands on Chatwoot dashboard with correct role
2. **Path 2 (credential proxy):** Enter CBZ username/password → signs in; repeat with OTP-enabled account → OTP prompt appears → enter OTP → signs in
3. **Password expiry:** Use an expired-password account → see redirect message to UC portal
4. **Unknown user:** UC user not linked to HelpEngine `systemId` → login fails with appropriate error
5. **Role mapping:** Log in as a `ADMIN` role UC user → verify Chatwoot shows `administrator`; log in as `AGENT` → verify `agent`

---

## Open questions (to resolve before implementation)

1. ~~**What `systemId` will UserConnect assign to CBZ HelpEngine?**~~ ✅ **`20031`**
2. ~~**Which UC roles will be used for HelpEngine agents vs admins?**~~ ✅ `Administrator` → `administrator`, `Agent` → `agent`
3. ~~**Is the UserConnect API accessible from `192.168.230.54`?**~~ ✅ **Reachable at `192.168.3.173`** (confirmed via ping from production server, ~1.9ms RTT).
4. ~~**What is the UserConnect API base URL?**~~ ✅ **`http://192.168.3.173:9700`**
5. **Will SCIM provisioning be enabled?** If yes, Entra will automatically create UserConnect users when they are assigned to the HelpEngine Enterprise App — removing the manual `user-systems-mapping` step per user.
6. **Should the standard email/password login be disabled once UC is active?** Disabling it forces all logins through UC (cleaner, single source of truth). Keeping it active allows a super-admin fallback if UC is unavailable. Recommended: keep it as fallback initially, disable after UC proves stable.
