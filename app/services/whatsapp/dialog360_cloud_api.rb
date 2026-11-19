# 360dialog's hosted WhatsApp Cloud API (waba-v2), used by a whatsapp_cloud channel whose
# provider_config['api_host'] is '360dialog'. Request and response bodies are the same as Meta's
# Graph API, but paths carry no API version and no phone-number or WABA id: the D360-API-KEY
# header identifies the number. Every 360dialog URL, the auth header and the media host rewrite
# live here so the Graph code paths stay as they are.
# ref: https://docs.360dialog.com/docs/waba-messaging/messaging
class Whatsapp::Dialog360CloudApi
  API_HOST = '360dialog'.freeze
  DEFAULT_BASE_URL = 'https://waba-v2.360dialog.io'.freeze
  API_KEY_HEADER = 'D360-API-KEY'.freeze
  # Media links returned by /{media_id} still name Meta's CDN; they are fetched from 360dialog instead.
  META_MEDIA_HOST = 'lookaside.fbsbx.com'.freeze

  def initialize(channel)
    @channel = channel
  end

  def base_url
    ENV.fetch('WHATSAPP_360DIALOG_CLOUD_BASE_URL', DEFAULT_BASE_URL).chomp('/')
  end

  def headers
    auth_headers.merge('Content-Type' => 'application/json')
  end

  def auth_headers
    { API_KEY_HEADER => @channel.provider_config['api_key'] }
  end

  def media_url(media_id)
    "#{base_url}/#{media_id}"
  end

  def media_upload_url
    "#{base_url}/media"
  end

  # The WABA's templates in Graph's shape ({ data, paging }); supports the name filter and `after` cursor.
  def message_templates_url
    "#{base_url}/message_templates"
  end

  # Template creation and deletion go through 360dialog's template management API.
  def template_management_url
    "#{base_url}/v1/configs/templates"
  end

  # The phone number's own fields, as Meta's phone-number node returns them.
  def phone_number_url
    "#{base_url}/health_status"
  end

  def business_profile_url
    "#{base_url}/whatsapp_business_profile"
  end

  # The URL to download media bytes from, given the url /{media_id} returned: Meta's CDN host is
  # replaced with the 360dialog host, keeping path and query. Returns nil for any other host so the
  # API key is never sent anywhere but 360dialog.
  def media_download_url(url)
    source = URI.parse(url.to_s)
    base = URI.parse(base_url)
    return source.to_s if source.host == base.host && source.scheme == 'https'

    unless source.host == META_MEDIA_HOST
      Rails.logger.warn("[WHATSAPP] 360dialog media url on unexpected host #{source.host} for channel #{@channel.id}; not downloaded")
      return
    end

    source.scheme = base.scheme
    source.host = base.host
    source.port = base.port
    source.to_s
  rescue URI::InvalidURIError
    nil
  end

  # 360dialog relays Meta's errors as { error: { message } } and reports its own as
  # { error: '...' } or { meta: { developer_message } }.
  def self.error_message(response)
    parsed = response.parsed_response
    return unless parsed.is_a?(Hash)

    error = parsed['error']
    return error['message'] if error.is_a?(Hash)
    return error if error.is_a?(String)

    parsed.dig('meta', 'developer_message') if parsed['meta'].is_a?(Hash)
  end
end
