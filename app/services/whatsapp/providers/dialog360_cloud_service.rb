# The WhatsApp Cloud provider for a number hosted at 360dialog (provider_config api_host: 360dialog).
# Message bodies, templates and inbound handling are the Cloud API's, inherited unchanged; only where
# requests go and how they authenticate differ: https://waba-v2.360dialog.io with a D360-API-KEY
# header, no API version and no phone-number or WABA id in the path (Whatsapp::Dialog360CloudApi).
class Whatsapp::Providers::Dialog360CloudService < Whatsapp::Providers::WhatsappCloudService
  # Graph authenticates template reads with a bearer token; 360dialog takes the API key.
  def fetch_whatsapp_templates(after: nil)
    options = { headers: dialog360_api.auth_headers }
    options[:query] = { after: after } if after.present?
    response = HTTParty.get(dialog360_api.message_templates_url, options)
    unless response.success?
      Rails.logger.warn "[WHATSAPP] Template sync failed for account #{whatsapp_channel.account_id} " \
                        "inbox #{whatsapp_channel.inbox&.id}: #{response.code} #{error_message(response)}"
      return []
    end

    next_cursor = response.dig('paging', 'cursors', 'after')
    return response['data'] + fetch_whatsapp_templates(after: next_cursor) if next_cursor.present?

    response['data']
  end

  # One call proves the key and that it belongs to the configured number: a 360dialog key identifies
  # exactly one number, and /health_status returns its Meta phone-number id. The key never goes in a URL.
  def validate_provider_config?
    response = HTTParty.get(dialog360_api.phone_number_url, headers: dialog360_api.headers, query: { fields: 'id' })
    return true if response.success? && response.parsed_response.is_a?(Hash) &&
                   response.parsed_response['id'].to_s == whatsapp_channel.provider_config['phone_number_id'].to_s

    Rails.logger.warn("[WHATSAPP] 360dialog credentials check failed account_id=#{whatsapp_channel.account_id} " \
                      "http_status=#{response.code} error=#{error_message(response)}")
    false
  end

  def api_headers
    dialog360_api.headers
  end

  def media_url(media_id)
    dialog360_api.media_url(media_id)
  end

  private

  def dialog360_api
    @dialog360_api ||= whatsapp_channel.dialog360_cloud_api
  end

  # Both resolve to the API root, so the inherited senders post to {root}/messages.
  def phone_id_path(_version = nil)
    dialog360_api.base_url
  end

  def business_account_path
    dialog360_api.base_url
  end

  def error_message(response)
    Whatsapp::Dialog360CloudApi.error_message(response)
  end
end
