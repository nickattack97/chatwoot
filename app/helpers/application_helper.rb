module ApplicationHelper
  # The path FRONTEND_URL is deployed under (e.g. '/helpengine'), so the SPA
  # can prefix its own router/API/websocket URLs to match a reverse proxy
  # that mounts the app under a sub-path rather than at the domain root.
  def frontend_base_path
    URI.parse(ENV.fetch('FRONTEND_URL', '')).path.to_s.chomp('/')
  rescue URI::InvalidURIError
    ''
  end

  def frontend_websocket_url
    uri = URI.parse(ENV.fetch('FRONTEND_URL', ''))
    return '' if uri.host.blank?

    scheme = uri.scheme == 'https' ? 'wss' : 'ws'
    port = uri.port && [80, 443].exclude?(uri.port) ? ":#{uri.port}" : ''
    "#{scheme}://#{uri.host}#{port}#{frontend_base_path}"
  rescue URI::InvalidURIError
    ''
  end

  def available_locales_with_name
    LANGUAGES_CONFIG.map { |_key, val| val.slice(:name, :iso_639_1_code) }
  end

  def feature_help_urls
    features = YAML.safe_load(Rails.root.join('config/features.yml').read).freeze
    features.each_with_object({}) do |feature, hash|
      hash[feature['name']] = feature['help_url'] if feature['help_url']
    end
  end
end
