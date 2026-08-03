<p align="center">
  <img src="../public/brand-assets/cbz-logo.png" alt="CBZ Bank" width="80">
</p>

<h1 align="center">CBZ HelpEngine</h1>
<p align="center"><strong>API Documentation</strong></p>
<p align="center">Internal &nbsp;·&nbsp; Developer Reference &nbsp;·&nbsp; CBZ IT Department</p>

---

# CBZ HelpEngine — API Documentation

## Overview

CBZ HelpEngine exposes a REST API built on the Chatwoot v1 API standard. All API
endpoints return JSON. A full interactive API reference (Swagger UI) is available
at `/swagger` on the running application.

**Base URL (external):** `https://pg.cbz.co.zw/helpengine/api/v1`
**Base URL (internal):** `https://helpengine.cbz.co.zw/api/v1` _(DNS pending — use `https://192.168.230.54/api/v1` until the DNS record is created)_

**OpenAPI spec:** `/swagger/swagger.json`

---

## Authentication

The API uses token-based authentication via `devise_token_auth`.

### Obtain a token

```http
POST /auth/sign_in
Content-Type: application/json

{
  "email": "agent@cbz.co.zw",
  "password": "your-password"
}
```

**Response:**

```json
{
  "data": {
    "access_token": "your-access-token",
    "token_type": "Bearer",
    "id": 1,
    "name": "Agent Name",
    "email": "agent@cbz.co.zw",
    "account_id": 1,
    "role": "administrator"
  }
}
```

### Using the token

Include the token in all subsequent requests:

```http
api_access_token: your-access-token
```

Or as a query parameter:

```
GET /api/v1/profile?api_access_token=your-access-token
```

### User API token (permanent)

Each user has a permanent API token visible in their profile settings
(Settings → Profile → Access Token). This is the recommended approach for
integrations — it does not expire.

---

## Core concepts

### Account

All resources belong to an Account. The CBZ HelpEngine has one account (ID: 1).
Account-scoped endpoints follow the pattern:

```
/api/v1/accounts/{account_id}/...
```

### Inbox

An Inbox represents a communication channel (WhatsApp, Email, etc.). Each inbox has:
- A unique ID
- A channel type (`Channel::Whatsapp`, `Channel::Email`, etc.)
- Agents assigned to it

### Conversation

A Conversation is a thread of messages between a contact and agents. Conversations
belong to an inbox and have a status (`open`, `resolved`, `pending`, `snoozed`).

### Contact

A Contact represents a customer/end-user. Contacts can have multiple conversations
across different inboxes.

---

## Key endpoints

### Profile

```http
GET /api/v1/profile
```

Returns the authenticated user's profile including their permanent API token.

---

### Conversations

```http
# List conversations
GET /api/v1/accounts/{account_id}/conversations

# Query parameters:
# ?status=open|resolved|pending|snoozed
# ?assignee_type=me|assigned|unassigned
# ?page=1

# Get a conversation
GET /api/v1/accounts/{account_id}/conversations/{id}

# Create a conversation
POST /api/v1/accounts/{account_id}/conversations

# Update status
PATCH /api/v1/accounts/{account_id}/conversations/{id}

# Toggle status (open ↔ resolved)
POST /api/v1/accounts/{account_id}/conversations/{id}/toggle_status
```

**Create conversation request body:**

```json
{
  "inbox_id": 1,
  "contact_id": 123,
  "additional_attributes": {},
  "assignee_id": 5,
  "team_id": 2
}
```

---

### Messages

```http
# List messages in a conversation
GET /api/v1/accounts/{account_id}/conversations/{conversation_id}/messages

# Send a message
POST /api/v1/accounts/{account_id}/conversations/{conversation_id}/messages
```

**Send message request body:**

```json
{
  "content": "Hello, how can I help you?",
  "message_type": "outgoing",
  "private": false
}
```

Set `"private": true` to send an internal note visible only to agents.

---

### Contacts

```http
# List contacts
GET /api/v1/accounts/{account_id}/contacts

# Search contacts
GET /api/v1/accounts/{account_id}/contacts/search?q=name_or_email

# Get contact
GET /api/v1/accounts/{account_id}/contacts/{id}

# Create contact
POST /api/v1/accounts/{account_id}/contacts

# Get contact's conversations
GET /api/v1/accounts/{account_id}/contacts/{id}/conversations
```

**Create contact request body:**

```json
{
  "name": "John Doe",
  "email": "john@example.com",
  "phone_number": "+263771234567",
  "identifier": "unique-id"
}
```

---

### Inboxes

```http
# List inboxes
GET /api/v1/accounts/{account_id}/inboxes

# Get inbox
GET /api/v1/accounts/{account_id}/inboxes/{id}

# List inbox members (agents)
GET /api/v1/accounts/{account_id}/inbox_members/{inbox_id}
```

---

### Agents

```http
# List agents
GET /api/v1/accounts/{account_id}/agents

# Create agent
POST /api/v1/accounts/{account_id}/agents

# Update agent
PUT /api/v1/accounts/{account_id}/agents/{id}

# Delete agent
DELETE /api/v1/accounts/{account_id}/agents/{id}
```

**Create agent request body:**

```json
{
  "name": "New Agent",
  "email": "agent@cbz.co.zw",
  "role": "agent"
}
```

Role is either `"agent"` or `"administrator"`.

---

### Teams

```http
# List teams
GET /api/v1/accounts/{account_id}/teams

# Get team members
GET /api/v1/accounts/{account_id}/teams/{id}/team_members

# Add members to team
POST /api/v1/accounts/{account_id}/teams/{id}/team_members
```

---

### Reports

```http
# Account summary (totals)
GET /api/v1/accounts/{account_id}/reports/summary
  ?since=1700000000&until=1700086400

# Conversation reports over time
GET /api/v1/accounts/{account_id}/reports
  ?metric=account&type=account&since=...&until=...

# Agent summary
GET /api/v1/accounts/{account_id}/reports/agents/summary
```

---

### Search

```http
GET /api/v1/accounts/{account_id}/search?q=search+term
```

Searches across conversations, contacts, and messages. Returns results grouped by type.

---

## Webhooks (outbound — app → external systems)

You can register external webhooks to receive events when things happen in HelpEngine.

```http
# List webhooks
GET /api/v1/accounts/{account_id}/webhooks

# Create webhook
POST /api/v1/accounts/{account_id}/webhooks

# Delete webhook
DELETE /api/v1/accounts/{account_id}/webhooks/{id}
```

**Create webhook request body:**

```json
{
  "url": "https://your-system.cbz.co.zw/helpengine-events",
  "subscriptions": [
    "conversation_created",
    "conversation_status_changed",
    "message_created",
    "conversation_resolved"
  ]
}
```

Available event types:

| Event | Triggered when |
|---|---|
| `conversation_created` | A new conversation is started |
| `conversation_status_changed` | Status changes (open/resolved/pending) |
| `conversation_resolved` | A conversation is resolved |
| `conversation_updated` | Conversation attributes change |
| `message_created` | Any message is sent or received |
| `contact_created` | A new contact is created |
| `contact_updated` | A contact's details change |

---

## Inbound webhooks (channel callbacks)

These are URLs the application exposes to receive events from external platforms.
They are not called by your code — they are called by the channel provider (Meta, etc.).

| Path | Channel |
|---|---|
| `POST /webhooks/whatsapp/{phone_number}` | WhatsApp Cloud API messages |
| `GET /webhooks/whatsapp/{phone_number}` | WhatsApp webhook verification |
| `POST /webhooks/instagram` | Instagram messages |
| `POST /webhooks/telegram/{bot_token}` | Telegram messages |
| `POST /webhooks/line/{line_channel_id}` | LINE messages |
| `POST /webhooks/sms/{phone_number}` | SMS messages |

The WhatsApp webhook for CBZ HelpEngine:
```
https://pg.cbz.co.zw/helpengine/webhooks/whatsapp/+263788170276
```

---

## Embeddable widget API

The chat widget is embedded via a script tag. It exposes a JavaScript API for
integration with your website or web application.

**Embed script:**

```html
<script>
  window.chatwootSettings = {
    hideMessageBubble: false,
    position: 'right',
    locale: 'en',
    type: 'standard',
  };
  (function(d, t) {
    var BASE_URL = "https://pg.cbz.co.zw/helpengine";
    var g = d.createElement(t), s = d.getElementsByTagName(t)[0];
    g.src = BASE_URL + "/packs/js/sdk.js";
    g.defer = true;
    g.async = true;
    s.parentNode.insertBefore(g, s);
    g.onload = function() {
      window.chatwootSDK.run({
        websiteToken: 'YOUR_WEBSITE_TOKEN',
        baseUrl: BASE_URL
      });
    };
  })(document, "script");
</script>
```

The `websiteToken` is found in Settings → Inboxes → your web widget inbox → Configuration.

---

## Rate limiting

The API does not enforce a strict rate limit by default, but Puma is configured with
`RAILS_MAX_THREADS` threads. Avoid bulk operations without pagination — use the `page`
query parameter on list endpoints.

---

## Error responses

All errors return a JSON body:

```json
{
  "error": "Human-readable error message"
}
```

| Status | Meaning |
|---|---|
| 401 | Missing or invalid API token |
| 403 | Authenticated but not authorised for this resource |
| 404 | Resource not found |
| 422 | Validation failed — check the `error` field |
| 429 | Rate limited |
| 500 | Internal server error — check Rails logs |

---

## Interactive API reference

> **Note:** The Swagger UI (`/swagger`) is disabled in production by design — it returns
> 404 on the live server. It is only available in the local development environment.

To explore the API interactively:

**Option 1 — Local development (recommended)**

Start the app locally and open `http://localhost:3000/swagger`. The Swagger UI is fully
functional in development mode with live request/response testing against your local DB.

**Option 2 — OpenAPI spec file**

The raw OpenAPI spec lives at `swagger/swagger.json` in the repository. Import it into
any API client that supports OpenAPI 3.0:
- [Postman](https://www.postman.com) — File → Import → select `swagger/swagger.json`
- [Insomnia](https://insomnia.rest) — Import from file
- [Bruno](https://www.usebruno.com) — Import OpenAPI spec

**Option 3 — Chatwoot public API docs**

The upstream Chatwoot API reference (covers all standard endpoints) is published at
`https://www.chatwoot.com/developers/api`. CBZ-specific customisations are not
reflected there but the core endpoint contracts are identical.
