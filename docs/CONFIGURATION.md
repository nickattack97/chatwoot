# CBZ HelpEngine — Application Configuration Guide

This guide explains the initial configuration applied to CBZ HelpEngine and how to
add, modify, or extend each feature. A seed script is provided to apply the baseline
configuration automatically on a fresh install.

---

## Applying the seed configuration

Run this once after the first deployment and after creating the WhatsApp inbox:

```bash
docker compose -f docker-compose.production.yaml exec rails \
  bundle exec rails runner db/seeds/cbz_configs.rb
```

The script is **idempotent** — safe to run multiple times. Existing records are updated
in place; nothing is duplicated.

---

## Labels

Labels are used to categorise conversations for filtering, reporting, and automation.

### CBZ default labels

| Label | Colour | Purpose |
|---|---|---|
| `account-inquiry` | Blue | Balance, statements, general account queries |
| `loan` | Orange | Loan applications and repayments |
| `card-services` | Purple | Debit/credit card issues |
| `complaint` | Red | Customer complaints |
| `fraud` | Dark Red | Suspected fraud or unauthorised transactions |
| `technical-support` | Blue | Digital banking technical issues |
| `internet-banking` | Blue | Internet banking platform support |
| `mobile-banking` | Green | CBZ Touch app support |
| `urgent` | Red | Immediate attention required |
| `pending-customer` | Orange | Waiting for customer response |
| `escalated` | Purple | Escalated to senior team |
| `feedback` | Teal | Customer feedback |

### Adding labels

**Via the UI:** Settings → Labels → Add Label

**Via Rails runner:**

```ruby
account = Account.first
account.labels.create!(
  title:       'new-label',         # lowercase, hyphens only
  description: 'What this label means',
  color:       '#3498DB'            # hex colour
)
```

### How labels are used in automation

Labels are applied automatically by automation rules (see Automation section below).
Agents can also apply labels manually from the conversation sidebar.

---

## Custom Attributes

Custom attributes extend conversations and contacts with CBZ-specific data fields.

### Conversation attributes

| Field | Type | Purpose |
|---|---|---|
| Account Number | Text | Customer's CBZ account number |
| Branch | List | CBZ branch associated with the query |
| Product Type | List | CBZ product (Current Account, Loan, Card, etc.) |
| Reference Number | Text | Transaction or case reference |
| Escalated | Checkbox | Whether the conversation has been escalated |

### Contact attributes

| Field | Type | Purpose |
|---|---|---|
| Customer ID | Text | CBZ CIF (Customer Information File) number |
| Account Type | List | Personal / Business / Corporate / Premium |

### Adding custom attributes

**Via the UI:** Settings → Custom Attributes → Add Custom Attribute

Choose between:
- **Conversation attribute** — appears in the conversation sidebar
- **Contact attribute** — appears on the contact profile

**Attribute types available:** Text, Number, Currency, Percent, Link, Date, List, Checkbox

**Via Rails runner:**

```ruby
account = Account.first

# Text attribute on conversations
account.custom_attribute_definitions.create!(
  attribute_display_name: 'Policy Number',
  attribute_key:          'policy_number',   # auto-generated if blank, snake_case
  attribute_display_type: 'text',
  attribute_model:        'conversation_attribute',
  description:            'Insurance policy number'
)

# List attribute on contacts
account.custom_attribute_definitions.create!(
  attribute_display_name: 'Segment',
  attribute_key:          'segment',
  attribute_display_type: 'list',
  attribute_model:        'contact_attribute',
  attribute_values:       ['Retail', 'SME', 'Corporate'],
  description:            'Customer segment'
)
```

---

## Canned Responses

Canned responses are pre-written message templates that agents activate by typing
`/short_code` in the reply box.

### CBZ default canned responses

| Short code | Purpose |
|---|---|
| `/greet` | Standard greeting with agent name |
| `/hold` | Please hold message |
| `/account-details` | Request account number securely |
| `/fraud-alert` | Fraud hotline referral |
| `/hours` | Business hours information |
| `/escalate` | Escalation notice to customer |
| `/resolve` | Closing message |
| `/callback` | Callback request |
| `/internet-banking-reset` | Password reset instructions |
| `/card-blocked` | Card unblock instructions |
| `/loan-inquiry` | Loan application guidance |
| `/transfer-failed` | Failed transaction follow-up |

### Adding canned responses

**Via the UI:** Settings → Canned Responses → Add Canned Response

**Via Rails runner:**

```ruby
account = Account.first

account.canned_responses.create!(
  short_code: 'balance',
  content:    'To check your account balance, please log in to CBZ Touch or visit our internet banking portal at cbz.co.zw.'
)
```

### Placeholders available in canned responses

| Placeholder | Replaced with |
|---|---|
| `{{agent_name}}` | The replying agent's name |
| `{{contact_name}}` | The customer's name |

---

## Automation Rules

Automation rules trigger actions automatically based on events and conditions.
They run without any agent intervention.

### CBZ default rules

| Rule | Event | Trigger | Action |
|---|---|---|---|
| Flag Fraud Keywords | Message created | Content contains "fraud", "scam", "unauthorised" | Add labels `fraud` + `urgent`, set priority Urgent |
| Flag Customer Complaints | Message created | Content contains "complaint", "complain", "unhappy" | Add label `complaint`, set priority High |
| WhatsApp Welcome Message | Conversation created | Inbox is WhatsApp Support | Send welcome message |
| Assign Loan Label | Message created | Content contains "loan", "borrow", "mortgage" | Add label `loan` |
| Mark Pending on Resolution | Conversation resolved | Status = resolved | Add label `pending-customer` |

### Automation events

| Event | When it fires |
|---|---|
| `conversation_created` | A new conversation starts |
| `conversation_updated` | Any conversation attribute changes |
| `conversation_opened` | A snoozed/pending conversation is reopened |
| `conversation_resolved` | A conversation is marked resolved |
| `message_created` | Any message is sent or received |

### Automation conditions (attribute keys)

`content`, `email`, `status`, `message_type`, `inbox_id`, `assignee_id`, `team_id`,
`labels`, `priority`, `phone_number`, `country_code`, `browser_language`, `city`,
`company_name`, `mail_subject`, `referer`, `private_note`

Filter operators: `equal_to`, `not_equal_to`, `contains`, `does_not_contain`,
`is_present`, `is_not_present`, `starts_with`

### Automation actions

| Action | Effect |
|---|---|
| `send_message` | Send a message to the customer |
| `add_label` | Apply a label to the conversation |
| `remove_label` | Remove a label |
| `assign_agent` | Assign to a specific agent |
| `assign_team` | Assign to a team |
| `remove_assigned_agent` | Unassign the current agent |
| `remove_assigned_team` | Unassign the current team |
| `change_status` | Set status (open / resolved / pending) |
| `change_priority` | Set priority (none / low / medium / high / urgent) |
| `mute_conversation` | Mute the conversation |
| `snooze_conversation` | Snooze the conversation |
| `send_email_to_team` | Email a team notification |
| `send_webhook_event` | POST to an external webhook URL |
| `add_private_note` | Add an internal agent note |

### Adding automation rules

**Via the UI:** Settings → Automation → New Automation

**Via Rails runner:**

```ruby
account = Account.first

account.automation_rules.create!(
  name:        'Auto-assign Card Queries',
  description: 'Assign card-related conversations to the Card Services team',
  event_name:  'conversation_created',
  active:      true,
  conditions:  [
    { attribute_key: 'inbox_id', filter_operator: 'equal_to',
      values: [Inbox.find_by(name: 'WhatsApp Support').id], query_operator: nil }
  ],
  actions:     [
    { action_name: 'add_label', action_params: ['card-services'] }
  ]
)
```

---

## Macros

Macros are one-click sequences of actions that agents run manually on a conversation.
Unlike automation rules, macros are agent-triggered.

### CBZ default macros

| Macro | Actions |
|---|---|
| Resolve and Thank Customer | Send thank-you message → Add label `pending-customer` → Resolve |
| Escalate to Senior Team | Send escalation message → Add labels `escalated` + `urgent` |
| Request Account Details | Send account number request message |
| Fraud Escalation | Send fraud message → Add labels `fraud` + `urgent` → Set priority Urgent |
| Snooze — Follow Up Tomorrow | Send follow-up message → Snooze conversation |

### Running a macro

In any open conversation: click the lightning bolt icon (⚡) in the toolbar → select macro → Run.

### Adding macros

**Via the UI:** Settings → Macros → New Macro

Drag and drop actions to build the sequence. Set visibility to **Global** so all agents can use it.

**Via Rails runner:**

```ruby
account   = Account.first
admin     = account.users.find_by(role: :administrator)

account.macros.create!(
  name:        'Send Business Hours',
  visibility:  :global,
  created_by:  admin,
  updated_by:  admin,
  actions:     [
    {
      action_name:   'send_message',
      action_params: ['Our support hours are Mon–Fri 8:00 AM–5:00 PM and Saturday 8:00 AM–1:00 PM (CAT).']
    }
  ]
)
```

---

## WhatsApp Inbox Settings

### Channel greeting

When enabled, an automatic greeting is sent to customers the first time they message
the inbox. This is separate from automation rules — it fires before any agent responds.

**Via the UI:** Settings → Inboxes → WhatsApp Support → Configuration → Greeting Message

**Via Rails runner:**

```ruby
inbox = Account.first.inboxes.find_by(name: 'WhatsApp Support')
inbox.update!(
  greeting_enabled: true,
  greeting_message: 'Hello! Welcome to CBZ Bank WhatsApp Support. An agent will be with you shortly.'
)
```

### Out-of-office message

Sent automatically when a customer messages outside business hours.

```ruby
inbox.update!(
  out_of_office_message: 'Thank you for contacting CBZ Bank. We are currently closed. Our hours are Mon–Fri 8:00 AM–5:00 PM and Saturday 8:00 AM–1:00 PM. We will respond on the next business day.'
)
```

### CSAT (Customer Satisfaction Survey)

When enabled, customers receive a survey link when their conversation is resolved.
Results appear in Reports → CSAT.

**Via the UI:** Settings → Inboxes → WhatsApp Support → Configuration → CSAT Survey

**Via Rails runner:**

```ruby
inbox.update!(csat_survey_enabled: true)
```

---

## Business Hours

Business hours determine when the out-of-office message fires and drive SLA reporting.
`day_of_week` follows Ruby convention: 0 = Sunday, 1 = Monday … 6 = Saturday.

### CBZ default hours (Africa/Harare — CAT, UTC+2)

| Day | Hours |
|---|---|
| Monday – Friday | 08:00 – 17:00 |
| Saturday | 08:00 – 13:00 |
| Sunday | Closed |

### Modifying business hours

**Via the UI:** Settings → Inboxes → WhatsApp Support → Business Hours

**Via Rails runner:**

```ruby
inbox = Account.first.inboxes.find_by(name: 'WhatsApp Support')
inbox.update!(working_hours_enabled: true, timezone: 'Africa/Harare')

# Update a specific day — day_of_week: 1 = Monday
wh = inbox.working_hours.find_by(day_of_week: 1)
wh.update!(open_hour: 8, open_minutes: 0, close_hour: 17, close_minutes: 0, closed_all_day: false)

# Close on a day
wh = inbox.working_hours.find_by(day_of_week: 0) # Sunday
wh.update!(closed_all_day: true)
```

---

## Conversation Workflows (SLA Policies)

SLA policies define response time targets for conversations. When a conversation
breaches its SLA, agents are notified and reports flag it.

### Adding an SLA policy

**Via the UI:** Settings → SLA Policies → New SLA Policy

Configure:
- **First response time** — how quickly the first agent reply must happen
- **Resolution time** — how long until the conversation must be resolved
- **Next response time** — response time for subsequent messages

Assign an SLA to an inbox under Settings → Inboxes → (inbox) → Configuration → SLA Policy.

---

## Summary — Where to find each setting

| Feature | UI Path |
|---|---|
| Labels | Settings → Labels |
| Custom Attributes | Settings → Custom Attributes |
| Canned Responses | Settings → Canned Responses |
| Automation Rules | Settings → Automation |
| Macros | Settings → Macros |
| Inbox Greeting | Settings → Inboxes → (inbox) → Configuration |
| Business Hours | Settings → Inboxes → (inbox) → Business Hours |
| CSAT | Settings → Inboxes → (inbox) → Configuration |
| SLA Policies | Settings → SLA Policies |
| Reports | Reports → Overview / CSAT / Label / Agent |
