# CBZ HelpEngine — Initial Configuration Seed
#
# Run with:
#   bundle exec rails runner db/seeds/cbz_configs.rb
#
# Or inside a running Docker container:
#   docker compose -f docker-compose.production.yaml exec rails \
#     bundle exec rails runner db/seeds/cbz_configs.rb
#
# This script is idempotent — safe to run multiple times.
# Existing records are updated in place; nothing is duplicated.

account = Account.first
raise "No account found. Complete the onboarding wizard first." unless account

wa_inbox = account.inboxes.find_by(channel_type: 'Channel::Whatsapp')

puts "=== CBZ HelpEngine Config Seed ==="
puts "Account : #{account.name} (id=#{account.id})"
puts "WA Inbox: #{wa_inbox&.name || 'NOT FOUND — inbox settings skipped'}"
puts

# ── 1. Labels ────────────────────────────────────────────────────────────────

puts "── Labels ──"

LABELS = [
  { title: 'account-inquiry',   description: 'Account balance, statements, and general account queries', color: '#1F93FF' },
  { title: 'loan',              description: 'Loan applications, repayments, and loan-related queries',   color: '#FF7E00' },
  { title: 'card-services',     description: 'Debit and credit card issues, activations, and limits',     color: '#9B59B6' },
  { title: 'complaint',         description: 'Customer complaints requiring resolution',                   color: '#E74C3C' },
  { title: 'fraud',             description: 'Suspected fraud, scams, or unauthorised transactions',       color: '#C0392B' },
  { title: 'technical-support', description: 'Digital banking app and internet banking technical issues',  color: '#3498DB' },
  { title: 'internet-banking',  description: 'Internet banking platform support',                         color: '#2980B9' },
  { title: 'mobile-banking',    description: 'CBZ Touch mobile app support',                              color: '#27AE60' },
  { title: 'urgent',            description: 'High-priority issues requiring immediate attention',         color: '#E74C3C' },
  { title: 'pending-customer',  description: 'Waiting for customer response or information',               color: '#F39C12' },
  { title: 'escalated',         description: 'Escalated to a senior team or specialist',                  color: '#8E44AD' },
  { title: 'feedback',          description: 'Customer feedback and suggestions',                          color: '#16A085' },
].freeze

LABELS.each do |attrs|
  label = account.labels.find_or_initialize_by(title: attrs[:title])
  label.assign_attributes(attrs)
  label.save!
  puts "  [ok] #{attrs[:title]}"
end

# ── 2. Custom Attributes ─────────────────────────────────────────────────────

puts "\n── Custom Attributes ──"

CONVERSATION_ATTRIBUTES = [
  {
    attribute_display_name: 'Account Number',
    attribute_key:          'account_number',
    attribute_display_type: 'text',
    attribute_model:        'conversation_attribute',
  },
  {
    attribute_display_name: 'Branch',
    attribute_key:          'branch',
    attribute_display_type: 'list',
    attribute_model:        'conversation_attribute',
    attribute_values:       ['Head Office', 'Harare CBD', 'Bulawayo', 'Mutare', 'Gweru', 'Masvingo', 'Chinhoyi', 'Bindura', 'Kariba', 'Victoria Falls'],
  },
  {
    attribute_display_name: 'Product Type',
    attribute_key:          'product_type',
    attribute_display_type: 'list',
    attribute_model:        'conversation_attribute',
    attribute_values:       ['Current Account', 'Savings Account', 'Fixed Deposit', 'Personal Loan',
                             'Mortgage', 'Business Loan', 'Debit Card', 'Credit Card', 'Internet Banking', 'CBZ Touch'],
  },
  {
    attribute_display_name: 'Reference Number',
    attribute_key:          'reference_number',
    attribute_display_type: 'text',
    attribute_model:        'conversation_attribute',
  },
  {
    attribute_display_name: 'Escalated',
    attribute_key:          'escalated',
    attribute_display_type: 'checkbox',
    attribute_model:        'conversation_attribute',
  },
].freeze

CONTACT_ATTRIBUTES = [
  {
    attribute_display_name: 'Customer ID',
    attribute_key:          'customer_id',
    attribute_display_type: 'text',
    attribute_model:        'contact_attribute',
  },
  {
    attribute_display_name: 'Account Type',
    attribute_key:          'account_type',
    attribute_display_type: 'list',
    attribute_model:        'contact_attribute',
    attribute_values:       ['Personal', 'Business', 'Corporate', 'Premium'],
  },
].freeze

(CONVERSATION_ATTRIBUTES + CONTACT_ATTRIBUTES).each do |attrs|
  attr_def = account.custom_attribute_definitions.find_or_initialize_by(
    attribute_key:   attrs[:attribute_key],
    attribute_model: CustomAttributeDefinition.attribute_models[attrs[:attribute_model]]
  )
  attr_def.assign_attributes(attrs.except(:attribute_values))
  attr_def.attribute_values = attrs[:attribute_values] if attrs[:attribute_values]
  attr_def.save!
  puts "  [ok] #{attrs[:attribute_display_name]} (#{attrs[:attribute_model]})"
end

# ── 3. Canned Responses ──────────────────────────────────────────────────────

puts "\n── Canned Responses ──"

CANNED_RESPONSES = [
  {
    short_code: 'greet',
    content:    "Hello! Thank you for contacting CBZ Bank. My name is {{agent_name}} and I'm here to assist you today. How can I help you?",
  },
  {
    short_code: 'hold',
    content:    "Thank you for your patience. Please allow me a moment to look into this for you.",
  },
  {
    short_code: 'account-details',
    content:    "To assist you further, could you please provide your account number or the last 4 digits of your account? Please do not share your full PIN or password.",
  },
  {
    short_code: 'fraud-alert',
    content:    "We take fraud very seriously. If you believe there has been unauthorised activity on your account, please call our 24/7 fraud hotline immediately at *0800 XXXX*. We will also escalate this conversation to our fraud team right away.",
  },
  {
    short_code: 'hours',
    content:    "Our WhatsApp support is available Monday to Friday, 8:00 AM – 5:00 PM, and Saturday, 8:00 AM – 1:00 PM (CAT). Outside these hours, please leave your message and we will respond on the next business day.",
  },
  {
    short_code: 'escalate',
    content:    "I understand this requires specialist attention. I'm escalating your query to our senior support team who will be in touch with you shortly.",
  },
  {
    short_code: 'resolve',
    content:    "I'm glad we could assist you today. Your query has been resolved. If you need further assistance, please don't hesitate to contact us again. Have a great day!",
  },
  {
    short_code: 'callback',
    content:    "We'd like to arrange a callback to assist you further. Please provide your preferred contact number and a convenient time and our team will reach out to you.",
  },
  {
    short_code: 'internet-banking-reset',
    content:    "To reset your internet banking credentials, please visit your nearest CBZ branch with a valid ID, or call our contact centre at *0800 XXXX*. For security reasons, we are unable to reset credentials via this channel.",
  },
  {
    short_code: 'card-blocked',
    content:    "Your card may have been blocked for security reasons. To unblock it, please call our 24/7 card services line at *0800 XXXX* or visit your nearest CBZ branch.",
  },
  {
    short_code: 'loan-inquiry',
    content:    "Thank you for your interest in a CBZ loan product. To get started, please visit your nearest branch with proof of income, a valid ID, and 3 months of bank statements. A relationship manager will guide you through the application.",
  },
  {
    short_code: 'transfer-failed',
    content:    "I'm sorry to hear your transfer was unsuccessful. Could you please provide the reference number and the approximate time of the transaction? I'll investigate this for you right away.",
  },
].freeze

CANNED_RESPONSES.each do |attrs|
  cr = account.canned_responses.find_or_initialize_by(short_code: attrs[:short_code])
  cr.content = attrs[:content]
  cr.save!
  puts "  [ok] /#{attrs[:short_code]}"
end

# ── 4. Automation Rules ──────────────────────────────────────────────────────

puts "\n── Automation Rules ──"

wa_inbox_id = wa_inbox&.id

AUTOMATION_RULES = [
  # Auto-label fraud keywords
  {
    name:        'Flag Fraud Keywords',
    description: 'Automatically label conversations where the customer mentions fraud or scam',
    event_name:  'message_created',
    active:      true,
    conditions:  [
      { attribute_key: 'content', filter_operator: 'contains', values: ['fraud'],         query_operator: 'OR' },
      { attribute_key: 'content', filter_operator: 'contains', values: ['scam'],          query_operator: 'OR' },
      { attribute_key: 'content', filter_operator: 'contains', values: ['unauthorized'],  query_operator: 'OR' },
      { attribute_key: 'content', filter_operator: 'contains', values: ['unauthorised'],  query_operator: nil  },
    ],
    actions:     [
      { action_name: 'add_label',       action_params: ['fraud'] },
      { action_name: 'add_label',       action_params: ['urgent'] },
      { action_name: 'change_priority', action_params: ['urgent'] },
    ],
  },
  # Auto-label complaint keywords
  {
    name:        'Flag Customer Complaints',
    description: 'Automatically label conversations that mention complaints',
    event_name:  'message_created',
    active:      true,
    conditions:  [
      { attribute_key: 'content', filter_operator: 'contains', values: ['complaint'],   query_operator: 'OR' },
      { attribute_key: 'content', filter_operator: 'contains', values: ['complain'],    query_operator: 'OR' },
      { attribute_key: 'content', filter_operator: 'contains', values: ['unhappy'],     query_operator: 'OR' },
      { attribute_key: 'content', filter_operator: 'contains', values: ['disappointed'], query_operator: nil },
    ],
    actions:     [
      { action_name: 'add_label',       action_params: ['complaint'] },
      { action_name: 'change_priority', action_params: ['high'] },
    ],
  },
  # WhatsApp greeting on new conversation
  (wa_inbox_id ? {
    name:        'WhatsApp Welcome Message',
    description: 'Send an automated greeting when a new WhatsApp conversation is created',
    event_name:  'conversation_created',
    active:      true,
    conditions:  [
      { attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [wa_inbox_id], query_operator: nil },
    ],
    actions:     [
      {
        action_name:   'send_message',
        action_params: ["Welcome to CBZ Bank's WhatsApp Support! 🏦\n\nThank you for reaching out. An agent will be with you shortly.\n\nOur support hours are:\n• Monday – Friday: 8:00 AM – 5:00 PM\n• Saturday: 8:00 AM – 1:00 PM\n\nFor urgent matters please call *0800 XXXX*."],
      },
    ],
  } : nil),
  # Out of hours message
  {
    name:        'Assign Loan Label on Keyword',
    description: 'Automatically label conversations mentioning loan inquiries',
    event_name:  'message_created',
    active:      true,
    conditions:  [
      { attribute_key: 'content', filter_operator: 'contains', values: ['loan'],     query_operator: 'OR' },
      { attribute_key: 'content', filter_operator: 'contains', values: ['borrow'],   query_operator: 'OR' },
      { attribute_key: 'content', filter_operator: 'contains', values: ['mortgage'], query_operator: nil  },
    ],
    actions:     [
      { action_name: 'add_label', action_params: ['loan'] },
    ],
  },
  # Resolved conversation — ask for CSAT
  {
    name:        'Mark Pending on Resolution',
    description: 'When an agent resolves a conversation, mark it pending so CSAT can be collected',
    event_name:  'conversation_resolved',
    active:      true,
    conditions:  [
      { attribute_key: 'status', filter_operator: 'equal_to', values: ['resolved'], query_operator: nil },
    ],
    actions:     [
      { action_name: 'add_label', action_params: ['pending-customer'] },
    ],
  },
].compact.freeze

admin_user = account.users.find_by(role: :administrator)

AUTOMATION_RULES.each do |attrs|
  rule = account.automation_rules.find_or_initialize_by(name: attrs[:name])
  rule.assign_attributes(attrs)
  rule.save!
  puts "  [ok] #{attrs[:name]}"
end

# ── 5. Macros ────────────────────────────────────────────────────────────────

puts "\n── Macros ──"

MACROS = [
  {
    name:       'Resolve and Thank Customer',
    visibility: :global,
    actions:    [
      { action_name: 'send_message',  action_params: ["Thank you for contacting CBZ Bank. Your query has been resolved. We appreciate your patience and hope to continue serving you. Have a wonderful day! 😊"] },
      { action_name: 'add_label',     action_params: ['pending-customer'] },
      { action_name: 'change_status', action_params: ['resolved'] },
    ],
  },
  {
    name:       'Escalate to Senior Team',
    visibility: :global,
    actions:    [
      { action_name: 'send_message', action_params: ["I understand your concern and I'm escalating this to our senior support team who are better equipped to assist you. They will follow up with you shortly. Thank you for your patience."] },
      { action_name: 'add_label',    action_params: ['escalated'] },
      { action_name: 'add_label',    action_params: ['urgent'] },
    ],
  },
  {
    name:       'Request Account Details',
    visibility: :global,
    actions:    [
      { action_name: 'send_message', action_params: ["To locate your account and assist you effectively, could you please provide your account number or the phone number registered with your CBZ account? Please do not share your PIN, password, or OTP codes."] },
    ],
  },
  {
    name:       'Fraud Escalation',
    visibility: :global,
    actions:    [
      { action_name: 'send_message',    action_params: ["We are taking this matter very seriously. Your case has been flagged as a potential fraud incident and is being escalated to our Fraud Investigation team immediately. Please call *0800 XXXX* if you need urgent assistance while we investigate."] },
      { action_name: 'add_label',       action_params: ['fraud'] },
      { action_name: 'add_label',       action_params: ['urgent'] },
      { action_name: 'change_priority', action_params: ['urgent'] },
    ],
  },
  {
    name:       'Snooze — Follow Up Tomorrow',
    visibility: :global,
    actions:    [
      { action_name: 'send_message',       action_params: ["We have noted your query and will follow up with you on the next business day. Thank you for your patience."] },
      { action_name: 'snooze_conversation', action_params: [] },
    ],
  },
].freeze

MACROS.each do |attrs|
  macro = account.macros.find_or_initialize_by(name: attrs[:name])
  macro.assign_attributes(attrs.merge(created_by: admin_user, updated_by: admin_user))
  macro.save!
  puts "  [ok] #{attrs[:name]}"
end

# ── 6. WhatsApp inbox settings ────────────────────────────────────────────────

if wa_inbox
  puts "\n── WhatsApp Inbox Settings ──"

  # Enable greeting
  wa_inbox.update!(
    greeting_enabled:     true,
    greeting_message:     "Hello! Welcome to CBZ Bank WhatsApp Support. An agent will be with you shortly.",
    csat_survey_enabled:  true,
    working_hours_enabled: true,
    timezone:             'Africa/Harare',
    out_of_office_message: "Thank you for contacting CBZ Bank. Our WhatsApp support is available Monday–Friday 8:00 AM–5:00 PM and Saturday 8:00 AM–1:00 PM (CAT). We have received your message and will respond on the next business day."
  )
  puts "  [ok] Greeting enabled"
  puts "  [ok] CSAT enabled"
  puts "  [ok] Working hours enabled (Africa/Harare)"

  # Business hours (0=Sunday, 1=Monday, ..., 6=Saturday)
  # Monday–Friday: 08:00–17:00, Saturday: 08:00–13:00, Sunday: closed
  BUSINESS_HOURS = [
    { day_of_week: 0, closed_all_day: true },                                                          # Sunday
    { day_of_week: 1, closed_all_day: false, open_hour: 8, open_minutes: 0, close_hour: 17, close_minutes: 0 }, # Monday
    { day_of_week: 2, closed_all_day: false, open_hour: 8, open_minutes: 0, close_hour: 17, close_minutes: 0 }, # Tuesday
    { day_of_week: 3, closed_all_day: false, open_hour: 8, open_minutes: 0, close_hour: 17, close_minutes: 0 }, # Wednesday
    { day_of_week: 4, closed_all_day: false, open_hour: 8, open_minutes: 0, close_hour: 17, close_minutes: 0 }, # Thursday
    { day_of_week: 5, closed_all_day: false, open_hour: 8, open_minutes: 0, close_hour: 17, close_minutes: 0 }, # Friday
    { day_of_week: 6, closed_all_day: false, open_hour: 8, open_minutes: 0, close_hour: 13, close_minutes: 0 }, # Saturday
  ].freeze

  BUSINESS_HOURS.each do |hours|
    wh = wa_inbox.working_hours.find_or_initialize_by(day_of_week: hours[:day_of_week])
    wh.assign_attributes(hours)
    wh.save!
  end

  day_names = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]
  BUSINESS_HOURS.each do |h|
    if h[:closed_all_day]
      puts "  [ok] #{day_names[h[:day_of_week]]}: Closed"
    else
      puts "  [ok] #{day_names[h[:day_of_week]]}: #{h[:open_hour]}:00 – #{h[:close_hour]}:#{h[:close_minutes].to_s.rjust(2,'0')}"
    end
  end
else
  puts "\n[SKIP] WhatsApp inbox not found — create the inbox first, then re-run this script."
end

puts "\n=== Done. CBZ HelpEngine initial configuration applied. ==="
