# CBZ HelpEngine: bring an existing install up to the defaults a new one gets (config/helpengine_defaults.yml).
#
#   docker compose -f docker-compose.production.yaml run --rm rails bundle exec rails runner db/seeds/cbz_configs.rb
#
# New accounts and WhatsApp inboxes get these automatically (config/initializers/helpengine_defaults.rb); this is for
# installs created before that. It only adds what is missing (labels, custom attributes, canned responses, automation
# rules, macros) and never changes an existing record. Each WhatsApp inbox is given the integration settings
# (Chatwoot greeting off, conversations not locked, working hours), which DEPLOYMENT.md requires anyway.
# Safe to run more than once.
account = Account.first
abort 'No account yet: complete the onboarding wizard first.' unless account

Helpengine::Defaults.apply_account!(account)
warn "Account defaults applied to #{account.name} (id #{account.id})"

account.inboxes.where(channel_type: 'Channel::Whatsapp').find_each do |inbox|
  Helpengine::Defaults.apply_whatsapp_inbox!(inbox)
  warn "WhatsApp settings applied to inbox #{inbox.name} (id #{inbox.id})"
end
