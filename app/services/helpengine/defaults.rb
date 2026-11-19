# CBZ HelpEngine defaults, from config/helpengine_defaults.yml.
#
#   apply_installation!          at database creation (db/seeds.rb): UserConnect sign-in on, pointed at this
#                                environment's UserConnect (UC_BASE_URL, UC_SYSTEM_ID and UC_BASE_URL_EXTERNAL from env).
#   apply_account!(account)      when an account is created: labels, custom attributes, canned responses, automation
#                                rules and macros.
#   apply_whatsapp_inbox!(inbox) when a WhatsApp inbox is created: the settings the WA-Bot-Engine integration needs.
#
# Every step only creates what is missing, matched by its key (title, short code, name); it never changes a record an
# administrator has edited. The hooks (config/initializers/helpengine_defaults.rb) are off in the test environment
# unless HELPENGINE_DEFAULTS=true, so upstream specs see a bare account.
class Helpengine::Defaults
  CONFIG_PATH = Rails.root.join('config/helpengine_defaults.yml')
  USERCONNECT_FROM_ENV = %w[UC_BASE_URL UC_SYSTEM_ID UC_BASE_URL_EXTERNAL].freeze
  USERCONNECT_SWITCHES = %w[UC_SSO_ENABLED UC_CREDENTIAL_PROXY_ENABLED].freeze

  def self.enabled?
    ENV.fetch('HELPENGINE_DEFAULTS', Rails.env.test? ? 'false' : 'true') == 'true'
  end

  def self.config
    YAML.safe_load_file(CONFIG_PATH)
  end

  # The image's installation_config.yml carries the UAT UserConnect, and a stored value always wins over the
  # environment (GlobalConfigService), so each environment's values are written here, once, when its database is new.
  def self.apply_installation!(env: ENV)
    USERCONNECT_FROM_ENV.each do |name|
      value = env[name].to_s.strip
      save_installation_config(name, value) if value.present?
    end
    USERCONNECT_SWITCHES.each { |name| save_installation_config(name, true) }
    GlobalConfig.clear_cache
    Rails.logger.info("[HelpEngine] UserConnect sign-in enabled (#{env['UC_BASE_URL'].presence || 'image default'}, " \
                      "system #{env['UC_SYSTEM_ID'].presence || 'image default'})")
  end

  def self.apply_account!(account)
    new(account).apply_account
  end

  def self.apply_whatsapp_inbox!(inbox)
    settings = config.fetch('whatsapp_inbox')
    inbox.update!(settings.except('working_hours'))
    settings.fetch('working_hours').each do |hours|
      inbox.working_hours.find_or_initialize_by(day_of_week: hours['day_of_week']).update!(hours)
    end
  end

  def self.save_installation_config(name, value)
    config = InstallationConfig.find_or_initialize_by(name: name)
    config.value = value
    config.save!
  end
  private_class_method :save_installation_config

  def initialize(account)
    @account = account
    @config = self.class.config
  end

  def apply_account
    create_labels
    create_custom_attributes
    create_canned_responses
    create_automation_rules
    create_macros
  end

  private

  def create_labels
    @config.fetch('labels').each do |attrs|
      @account.labels.find_or_create_by!(title: attrs['title']) do |label|
        label.assign_attributes(attrs.merge('show_on_sidebar' => true))
      end
    end
  end

  def create_custom_attributes
    @config.fetch('custom_attributes').each do |attrs|
      next if @account.custom_attribute_definitions.exists?(attribute_key: attrs['attribute_key'],
                                                            attribute_model: attrs['attribute_model'])

      @account.custom_attribute_definitions.create!(attrs)
    end
  end

  def create_canned_responses
    @config.fetch('canned_responses').each do |attrs|
      @account.canned_responses.find_or_create_by!(short_code: attrs['short_code']) { |reply| reply.content = attrs['content'] }
    end
  end

  def create_automation_rules
    @config.fetch('automation_rules').each do |attrs|
      @account.automation_rules.find_or_create_by!(name: attrs['name']) { |rule| rule.assign_attributes(attrs) }
    end
  end

  def create_macros
    admin = @account.administrators.first
    @config.fetch('macros').each do |attrs|
      @account.macros.find_or_create_by!(name: attrs['name']) do |macro|
        macro.assign_attributes(attrs.merge('visibility' => 'global', 'created_by' => admin, 'updated_by' => admin))
      end
    end
  end
end
