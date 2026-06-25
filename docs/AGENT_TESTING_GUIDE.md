<p align="center">
  <img src="../public/brand-assets/cbz-logo.png" alt="CBZ Bank" width="80">
</p>

<h1 align="center">CBZ HelpEngine</h1>
<p align="center"><strong>Agent Testing Guide</strong></p>
<p align="center">Internal &nbsp;·&nbsp; UAT &nbsp;·&nbsp; CBZ Contact Centre</p>

---

## Purpose

This guide walks agents through their first login and a live end-to-end test using WhatsApp. By the end you will have sent a real message, seen it arrive in the dashboard, replied to it, and explored the key features of the platform.

---

## Step 1 — Set up your UserConnect password (first time only)

Before your first login to CBZ HelpEngine, you need to set up your password on the CBZ UserConnect portal:

> **[http://192.168.3.173:9801/login](http://192.168.3.173:9801/login)**

1. Your administrator will have created your profile on UserConnect and an **OTP will be sent to your work email address**
2. On the UserConnect login page, enter your username and use the OTP from your email as your password
3. You will immediately be prompted to **change your password** — choose a new password and confirm it
4. Once your password is set you are ready to log in to CBZ HelpEngine

> If you did not receive the OTP email, contact your administrator to resend it.

---

## Step 2 — Log in to CBZ HelpEngine

Open the app in your browser:

> **[https://pg.cbz.co.zw/app/login](https://pg.cbz.co.zw/app/login)**

You will see the CBZ HelpEngine login page with two options:

| Option | When to use |
|---|---|
| **Sign in with Microsoft** | Recommended — uses your CBZ Microsoft/Entra account, no separate password needed |
| **Username / Password** | Use your CBZ UserConnect username and the password you just set |

After logging in you will land on the **Conversations** dashboard.

---

## Step 3 — Start a live WhatsApp test

Send a WhatsApp message to the CBZ HelpEngine support number to generate a real inbound conversation:

### 👉 [Tap here to open WhatsApp and message us](https://wa.me/263788170276)

Or open WhatsApp manually and message: **+263 78 817 0276**

Send any message — for example:
> *"Hi, I'd like to test the CBZ HelpEngine support system."*

Within a few seconds the conversation will appear in the HelpEngine dashboard under **Conversations → All**.

---

## Step 4 — Find and open the conversation

1. In the left sidebar click **Conversations**
2. You should see a new conversation from your WhatsApp number at the top of the list
3. Click on it to open the conversation thread

You will see:
- The message you sent from WhatsApp on the left
- The conversation details panel on the right (contact info, labels, assignee, etc.)

---

## Step 5 — Reply to the message

1. Click in the reply box at the bottom of the conversation
2. Type a reply — for example:
   > *"Hello! Thank you for reaching out to CBZ Bank support. How can I help you today?"*
3. Press **Enter** or click the **Send** button
4. Check your WhatsApp — the reply should arrive within seconds

> **Tip:** Use `/` in the reply box to browse canned responses (pre-written templates). Try typing `/greet` to insert the standard greeting.

---

## Step 6 — Explore key features

### Assign the conversation
- In the right panel under **Conversation Actions**, click **Assignee** and assign it to yourself or another agent
- You can also assign it to a **Team**

### Add a label
- Under **Conversation Labels**, click **Add Labels**
- Try applying `account-inquiry` or `urgent`
- Labels help with filtering, reporting, and automation

### Add a private note
- In the reply box, click the **Note** tab (next to Reply)
- Type an internal comment — this is only visible to agents, not the customer
- Example: *"Test conversation — initiated by IT for UAT validation"*

### Resolve the conversation
- Click the **Resolve** button (green checkmark) in the top-right of the conversation
- The conversation moves to the **Resolved** tab
- The customer does NOT receive a notification when you resolve

### Reopen if needed
- Go to **Conversations → Resolved**
- Open the conversation and click **Reopen**

---

## Step 7 — Explore the dashboard sections

| Section | What it shows |
|---|---|
| **Overview** | Live view of all open conversations and agent availability |
| **Conversations → Mine** | Conversations assigned to you |
| **Conversations → All** | Every conversation across all inboxes |
| **Contacts** | Customer profiles — click any contact to see their full conversation history |
| **Reports** | Summary stats by agent, label, inbox, and team |

---

## Step 8 — Update your profile

1. Click your avatar in the bottom-left corner → **Profile Settings**
2. Set your **Display Name** (shown to other agents in assignments)
3. Set your **Availability** status:
   - 🟢 **Online** — you can receive conversation assignments
   - 🟡 **Busy** — logged in but not available
   - ⚫ **Offline** — not available

---

## What to watch for

During your test, note anything unexpected:

- [ ] Login works with your CBZ credentials
- [ ] WhatsApp message arrives in the dashboard within ~10 seconds
- [ ] Reply from the dashboard is received on WhatsApp
- [ ] Canned responses load when typing `/`
- [ ] Labels can be applied and removed
- [ ] Conversation can be assigned to an agent and a team
- [ ] Conversation resolves and is visible in the Resolved tab
- [ ] Private notes are visible only in the dashboard (not on WhatsApp)

Report any issues to the CBZ IT Core Applications team.

---
