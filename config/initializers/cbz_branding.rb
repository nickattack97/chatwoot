CBZ_BRANDING = {
  'INSTALLATION_NAME' => 'CBZ HelpEngine',
  'BRAND_NAME'        => 'CBZ HelpEngine',
  'LOGO'              => '/brand-assets/cbz-logo.png',
  'LOGO_DARK'         => '/brand-assets/cbz-logo.png',
  'LOGO_THUMBNAIL'    => '/brand-assets/cbz-logo.png',
  'BRAND_URL'         => 'https://www.cbz.co.zw',
  'WIDGET_BRAND_URL'  => 'https://www.cbz.co.zw',
}.freeze

Rails.application.config.after_initialize do
  next unless ActiveRecord::Base.connection.table_exists?('installation_configs')

  changed = false
  CBZ_BRANDING.each do |key, value|
    record = InstallationConfig.find_or_initialize_by(name: key)
    next if record.persisted? && record.value.to_s == value

    record.value = value
    record.save!
    changed = true
  end

  GlobalConfig.clear_cache if changed
rescue StandardError => e
  Rails.logger.warn "[CBZ] Branding initializer failed: #{e.message}"
end
