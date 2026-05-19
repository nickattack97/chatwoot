# CBZ HelpEngine — API Integration Guide

This guide is for third-party developers and internal CBZ systems that want to
integrate with CBZ HelpEngine programmatically — for example, to create conversations
from another system, look up customer history, send messages, or receive real-time
event notifications via webhooks.

**Base URL:** `https://pg.cbz.co.zw/api/v1`

All requests and responses use JSON. All endpoints require authentication.

---

## Getting access

Contact the CBZ HelpEngine administrator to have an agent account created for your
integration. You will receive an email invitation to set your password.

Once logged in, find your permanent API token at:

**Settings → Profile → Access Token**

This token does not expire. Keep it secret — treat it like a password.

---

## Authentication

Include your token in every request using the `api_access_token` header:

```http
GET /api/v1/profile HTTP/1.1
Host: pg.cbz.co.zw
api_access_token: YOUR_TOKEN_HERE
```

Or as a query parameter (useful for quick tests):

```
https://pg.cbz.co.zw/api/v1/profile?api_access_token=YOUR_TOKEN_HERE
```

All examples below assume the header is set. The **account ID** for CBZ HelpEngine
is `1` — use this in all account-scoped URLs.

---

## Quick start — verify your token

```http
GET /api/v1/profile
api_access_token: YOUR_TOKEN_HERE
```

**Response:**

```json
{
  "id": 5,
  "name": "Integration User",
  "email": "integration@cbz.co.zw",
  "access_token": "YOUR_TOKEN_HERE",
  "role": "agent"
}
```

If you receive `401 Unauthorized`, the token is missing or incorrect.

---

## Common integration scenarios

### 1. Look up a customer by phone number

Before creating a new conversation, check whether the customer already exists.

```http
GET /api/v1/accounts/1/contacts/search?q=%2B263771234567&include_contacts=true
api_access_token: YOUR_TOKEN_HERE
```

**Response:**

```json
{
  "payload": [
    {
      "id": 42,
      "name": "John Doe",
      "phone_number": "+263771234567",
      "email": "john@example.com"
    }
  ],
  "meta": { "count": 1 }
}
```

Use the `id` from the response in subsequent calls. If `payload` is empty, create the contact first (see below).

---

### 2. Create a contact

```http
POST /api/v1/accounts/1/contacts
api_access_token: YOUR_TOKEN_HERE
Content-Type: application/json

{
  "name": "John Doe",
  "phone_number": "+263771234567",
  "email": "john@example.com",
  "identifier": "CIF-00123456"
}
```

`identifier` is optional — use it to store the customer's CBZ CIF number for cross-system linking.

**Response:**

```json
{
  "id": 42,
  "name": "John Doe",
  "phone_number": "+263771234567",
  "email": "john@example.com",
  "identifier": "CIF-00123456"
}
```

---

### 3. Create a conversation

Opens a new support conversation for a contact. You need the contact's `id` and the
target inbox `id`. To find the WhatsApp Support inbox ID:

```http
GET /api/v1/accounts/1/inboxes
api_access_token: YOUR_TOKEN_HERE
```

Look for the inbox named `WhatsApp Support` in the response and note its `id`.

Then create the conversation:

```http
POST /api/v1/accounts/1/conversations
api_access_token: YOUR_TOKEN_HERE
Content-Type: application/json

{
  "contact_id": 42,
  "inbox_id": 1,
  "additional_attributes": {
    "account_number": "1234567890",
    "reference_number": "TXN-98765"
  }
}
```

**Response:**

```json
{
  "id": 101,
  "status": "open",
  "inbox_id": 1,
  "contact": { "id": 42, "name": "John Doe" },
  "meta": { "created_at": "2026-05-19T10:00:00.000Z" }
}
```

Note the conversation `id` — you will need it to send messages or check status.

---

### 4. Send a message to a conversation

```http
POST /api/v1/accounts/1/conversations/101/messages
api_access_token: YOUR_TOKEN_HERE
Content-Type: application/json

{
  "content": "Hello John, your loan application has been received and is under review.",
  "message_type": "outgoing",
  "private": false
}
```

Set `"private": true` to create an internal agent note visible only to staff — the
customer will not see it.

**Response:**

```json
{
  "id": 501,
  "content": "Hello John, your loan application has been received and is under review.",
  "message_type": "outgoing",
  "created_at": 1747648800
}
```

---

### 5. Get conversation status and messages

```http
GET /api/v1/accounts/1/conversations/101
api_access_token: YOUR_TOKEN_HERE
```

```http
GET /api/v1/accounts/1/conversations/101/messages
api_access_token: YOUR_TOKEN_HERE
```

Conversation status will be one of: `open`, `resolved`, `pending`, `snoozed`.

---

### 6. Resolve a conversation

```http
POST /api/v1/accounts/1/conversations/101/toggle_status
api_access_token: YOUR_TOKEN_HERE
Content-Type: application/json

{
  "status": "resolved"
}
```

---

### 7. Get all open conversations

```http
GET /api/v1/accounts/1/conversations?status=open&page=1
api_access_token: YOUR_TOKEN_HERE
```

Filter options for `status`: `open`, `resolved`, `pending`, `snoozed`

Filter options for `assignee_type`: `me`, `assigned`, `unassigned`

Results are paginated — increment `page` to retrieve more.

---

### 8. Get a customer's conversation history

```http
GET /api/v1/accounts/1/contacts/42/conversations
api_access_token: YOUR_TOKEN_HERE
```

Returns all conversations for the contact across all inboxes, newest first.

---

## Receiving events via webhooks

Rather than polling for updates, register a webhook URL to receive real-time
notifications when things happen in HelpEngine.

### Register a webhook

```http
POST /api/v1/accounts/1/webhooks
api_access_token: YOUR_TOKEN_HERE
Content-Type: application/json

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

### Available event types

| Event | When it fires |
|---|---|
| `conversation_created` | A new conversation is opened |
| `conversation_status_changed` | Status changes (open / resolved / pending) |
| `conversation_resolved` | A conversation is marked resolved |
| `conversation_updated` | Conversation attributes are changed |
| `message_created` | A message is sent or received |
| `contact_created` | A new contact is created |
| `contact_updated` | A contact's details are changed |

### Webhook payload structure

HelpEngine sends an HTTP POST to your URL with a JSON body. Example for `message_created`:

```json
{
  "event": "message_created",
  "id": 501,
  "content": "Hello, I need help with my account.",
  "message_type": "incoming",
  "created_at": 1747648800,
  "conversation": {
    "id": 101,
    "status": "open",
    "inbox_id": 1
  },
  "contact": {
    "id": 42,
    "name": "John Doe",
    "phone_number": "+263771234567"
  },
  "account": {
    "id": 1,
    "name": "CBZ HelpEngine"
  }
}
```

### Webhook reliability

Your endpoint must respond with HTTP `2xx` within 15 seconds. If it does not, HelpEngine
will retry. Design your endpoint to be **idempotent** — the same event may be delivered
more than once. Use the event `id` field to deduplicate if needed.

---

## Error responses

All errors return a JSON body with an `error` field:

```json
{
  "error": "You are not authorized to perform this action"
}
```

| Status | Meaning | What to do |
|---|---|---|
| `401` | Missing or invalid API token | Check your `api_access_token` header |
| `403` | Token valid but not authorised for this resource | Contact the HelpEngine administrator |
| `404` | Resource not found | Check the ID in your request |
| `422` | Validation failed | Read the `error` field for details |
| `500` | Server error | Retry after a short delay; contact CBZ IT if persistent |

---

## Pagination

List endpoints return paginated results. Use the `page` query parameter (default: `page=1`).
There is no fixed page size — include `page` on every list request and increment until
you receive an empty `data` array.

```http
GET /api/v1/accounts/1/conversations?status=open&page=2
```

---

## Getting help

For API access, token creation, or integration support contact the CBZ HelpEngine
administrator or raise a request via the internal IT helpdesk.
