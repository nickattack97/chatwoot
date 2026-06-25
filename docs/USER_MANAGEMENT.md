<p align="center">
  <img src="../public/brand-assets/cbz-logo.png" alt="CBZ Bank" width="80">
</p>

<h1 align="center">CBZ HelpEngine</h1>
<p align="center"><strong>User Management</strong></p>
<p align="center">Internal &nbsp;·&nbsp; Administrator Guide &nbsp;·&nbsp; CBZ IT Department</p>

---

# CBZ HelpEngine — User Management

## Overview

CBZ HelpEngine uses an invitation-only model. Public self-registration is disabled
(`ENABLE_ACCOUNT_SIGNUP=false`). All agents must be invited by an administrator.

---

## Roles

There are two roles, stored per-account on the `account_users` join table (not on the user record itself):

| Role | What they can do |
|---|---|
| `agent` | Handle conversations, send messages, apply labels and macros |
| `administrator` | Everything an agent can do, plus manage settings, inboxes, teams, automation, and invite/remove agents |

A user's role is specific to an account — the same email address could be an agent in one account and an administrator in another.

---

## Inviting agents

### Via the UI

Settings → Agents → Invite Agent

Enter the agent's name, email address, and role. An invitation email is sent automatically.
The agent clicks the link in the email to set their own password and activate their account.

### Via Rails runner

```ruby
account = Account.first
admin   = account.account_users.find_by(role: :administrator)&.user

AgentBuilder.new(
  email:     'agent@cbz.co.zw',
  name:      'Jane Moyo',
  role:      :agent,            # or :administrator
  inviter:   admin,
  account:   account
).perform
```

The builder:
1. Looks up an existing `User` record by email — if found, links them to this account
2. If not found, creates a new user with a temporary random password
3. Creates an `AccountUser` record linking the user to the account with the specified role
4. Sends a Devise invitation email so the user can set their own password

### Bulk invite via the UI

Settings → Agents → Import — paste a list of email addresses. Each is invited as an
`agent` with the name defaulting to the email prefix. Useful for initial onboarding.

---

## Availability status

Each agent has an availability status tracked in real time:

| Status | Meaning |
|---|---|
| `online` | Active in the browser — can receive conversation assignments |
| `busy` | Logged in but unavailable for new assignments |
| `offline` | Not available |

Availability is stored in `account_users` and mirrored to Redis for live presence tracking.

### Auto-offline

When **Auto Offline** is enabled (`auto_offline: true`, the default), the agent is
automatically set to `offline` when they close all browser tabs. When they return,
they are set back to `online`.

Agents can toggle their own availability from the avatar menu in the bottom-left corner.
Administrators can set availability when creating or editing an agent.

---

## Updating an agent

### Via the UI

Settings → Agents → click the edit icon next to the agent.

You can update:
- **Name** — display name shown in conversations
- **Role** — promote to administrator or demote to agent
- **Availability** — override their current status
- **Auto Offline** — toggle automatic offline on browser close

### Via Rails runner

```ruby
account = Account.first
user    = User.find_by(email: 'agent@cbz.co.zw')
au      = account.account_users.find_by(user: user)

# Change role
au.update!(role: :administrator)

# Change availability
au.update!(availability: :busy)

# Disable auto-offline
au.update!(auto_offline: false)
```

---

## Removing an agent

### Via the UI

Settings → Agents → click the delete icon. The agent is removed from the account.
If they have no other accounts, their user record is deleted asynchronously.

### Via Rails runner

```ruby
account = Account.first
user    = User.find_by(email: 'agent@cbz.co.zw')
account.account_users.find_by(user: user).destroy!
```

Removing an agent:
- Unassigns them from all open conversations (conversations remain open, unassigned)
- Removes them from all teams and inboxes within this account
- Sends an `AGENT_REMOVED` event for any webhooks subscribed to it

---

## Teams

Teams group agents for routing and reporting. A conversation can be assigned to a team,
and automation rules can route conversations to specific teams.

### Creating a team

**Via the UI:** Settings → Teams → Create New Team

**Via Rails runner:**

```ruby
account = Account.first
team = account.teams.create!(
  name:              'Card Services',
  description:       'Handles debit and credit card queries',
  allow_auto_assign: true
)
```

`allow_auto_assign: true` enables the round-robin auto-assignment feature for that team.

### Adding agents to a team

**Via the UI:** Settings → Teams → (team) → Settings → Add Agents

**Via Rails runner:**

```ruby
account = Account.first
team    = account.teams.find_by(name: 'Card Services')
users   = account.users.where(email: ['agent1@cbz.co.zw', 'agent2@cbz.co.zw'])

team.add_members(users.pluck(:id))
```

### Removing agents from a team

```ruby
team.remove_members(users.pluck(:id))
```

---

## Inbox assignment

Agents must be assigned to an inbox to appear as assignment options for conversations
in that inbox. Unassigned agents can still be manually assigned by an administrator.

### Assigning agents to an inbox

**Via the UI:** Settings → Inboxes → (inbox) → Collaborators → Add Agents

**Via Rails runner:**

```ruby
account = Account.first
inbox   = account.inboxes.find_by(name: 'WhatsApp Support')
users   = account.users.where(email: ['agent1@cbz.co.zw', 'agent2@cbz.co.zw'])

inbox.add_members(users.pluck(:id))
```

### Removing agents from an inbox

```ruby
inbox.remove_members(users.pluck(:id))
```

---

## Notification settings

When an agent is added to the account, default notification settings are created automatically:

| Notification | Default |
|---|---|
| Email — conversation assigned to me | Enabled |
| Push — conversation assigned to me | Enabled |
| All other notifications | Disabled |

Agents can adjust their own notifications from Settings → Notifications.

---

## User lifecycle flow

```mermaid
flowchart TD
    A([Admin invites agent\nvia UI or Rails runner])
    B[AgentBuilder creates User\nwith temp password]
    C[AccountUser record created\nwith role and availability]
    D[Invitation email sent\nvia Devise]
    E([Agent clicks link\nsets own password])
    F[Account activated\nAgent can log in]
    G([Admin removes agent])
    H[AccountUser destroyed\nAgent unassigned from all convos]
    I{Other accounts?}
    J[User record deleted]
    K[User record kept]

    A --> B --> C --> D --> E --> F
    F --> G --> H --> I
    I -->|No| J
    I -->|Yes| K
```

---

## UserConnect IAM Integration

CBZ HelpEngine is integrated with **UserConnect** — CBZ's internal identity platform.
Agents authenticate using their standard CBZ credentials (the same ones used for all
other CBZ systems). There is no separate HelpEngine password.

Two login methods are available on the login page (both can be active simultaneously):

| Method | How it works |
|---|---|
| **Sign in with Microsoft** | Redirects through UserConnect → Microsoft Entra ID (SAML). One-click, no credentials entered in HelpEngine. |
| **Username / Password** | Credentials entered in HelpEngine are proxied to the UserConnect API. Supports OTP (two-factor) if configured in UserConnect. |

Both methods are controlled by InstallationConfig flags — see [CONFIGURATION.md](CONFIGURATION.md#userconnect-iam).

### Agent onboarding (JIT provisioning)

Agents do **not** need to be invited or pre-created. On first login via UserConnect,
HelpEngine automatically:

1. Looks up the user by email from the UserConnect JWT claims
2. Creates a `User` record if one does not exist (name and email from UserConnect)
3. Creates an `AccountUser` record with the `agent` role
4. Logs the user in immediately — no email confirmation, no password setup

The agent account will show **Verification Pending** until the email address is confirmed,
but this does not block login or access. Agents can be promoted to `administrator` by
an existing admin after their first login.

### Agent offboarding

HelpEngine does not receive real-time deprovisioning events from UserConnect. When
a staff member leaves:

1. Their UserConnect account is disabled by IT — they can no longer authenticate
2. An administrator should remove them from HelpEngine manually:
   - **Via UI:** Settings → Agents → delete icon
   - **Via Rails runner:** `account.account_users.find_by(user: User.find_by(email: 'agent@cbz.co.zw')).destroy!`

> Removing an agent unassigns them from all open conversations and removes them from
> all teams and inboxes. The conversations remain open and unassigned.

### Role management

Roles are managed in HelpEngine independently of UserConnect — UserConnect only handles
authentication, not role assignment.

| Role | Assigned by |
|---|---|
| `agent` | Default on first login via UserConnect |
| `administrator` | An existing HelpEngine administrator promotes the agent manually |

To promote an agent:
- **Via UI:** Settings → Agents → edit icon → change Role to Administrator
- **Via Rails runner:** `account.account_users.find_by(user: User.find_by(email: '...')).update!(role: :administrator)`

### Password reset

The **Reset Password** button is hidden for UserConnect users — their password is managed
in UserConnect/Entra ID, not in HelpEngine. Staff should use the CBZ UserConnect portal
or contact IT to reset their password.

The Forgot Password link on the login page is also not shown when UserConnect credential
proxy login is active.

### User lifecycle flow (with UserConnect)

```mermaid
flowchart TD
    A([Staff member logs in\nvia UserConnect])
    B{User exists\nin HelpEngine?}
    C[JIT provision:\nCreate User + AccountUser\nrole = agent]
    D[Log in to existing account]
    E([Admin promotes to administrator\nif needed])
    F([Staff member leaves CBZ])
    G([IT disables UserConnect account])
    H([Admin removes agent\nfrom HelpEngine])
    I[Agent unassigned from\nall open conversations]

    A --> B
    B -->|No| C --> D
    B -->|Yes| D
    D --> E
    F --> G
    G -->|Access blocked at login| H
    H --> I
```

---

## Summary — Where to find each setting

| Task | UI Path |
|---|---|
| Invite an agent (non-UC users) | Settings → Agents → Invite Agent |
| Change role / availability | Settings → Agents → edit icon |
| Remove an agent | Settings → Agents → delete icon |
| Create a team | Settings → Teams → Create New Team |
| Add agents to a team | Settings → Teams → (team) → Settings |
| Assign agents to an inbox | Settings → Inboxes → (inbox) → Collaborators |
| Agent notification preferences | Settings → Notifications |
| Agent profile (name, avatar) | Settings → Profile |
| Enable/disable UC login methods | Super Admin → Installation Configs or Rails runner |
| Reset a UC user's password | CBZ UserConnect portal / IT |
