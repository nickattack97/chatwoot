# CBZ HelpEngine: every new account starts with the bank's labels, custom attributes, canned responses, automation rules
# and macros, and every new WhatsApp inbox with the settings the WA-Bot-Engine integration needs
# (config/helpengine_defaults.yml, Helpengine::Defaults). Kept out of the upstream models so upstream merges stay clean.
# A failure is logged, never raised: it must not stop the onboarding wizard or an inbox from being created.
Rails.application.config.to_prepare do
  Account.after_create_commit do
    Helpengine::Defaults.apply_account!(self) if Helpengine::Defaults.enabled?
  rescue StandardError => e
    Rails.logger.error("[HelpEngine] Account defaults failed for account #{id}: #{e.class}: #{e.message}")
  end

  Inbox.after_create_commit do
    Helpengine::Defaults.apply_whatsapp_inbox!(self) if channel_type == 'Channel::Whatsapp' && Helpengine::Defaults.enabled?
  rescue StandardError => e
    Rails.logger.error("[HelpEngine] WhatsApp inbox defaults failed for inbox #{id}: #{e.class}: #{e.message}")
  end
end
