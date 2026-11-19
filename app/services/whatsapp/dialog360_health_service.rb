# Health for a number hosted at 360dialog (provider_config api_host: 360dialog). The phone number's
# fields come from 360dialog's /health_status, which mirrors Meta's phone-number node, and the business
# profile from its /whatsapp_business_profile. 360dialog has no endpoint for the WABA's name or owning
# business, so those stay empty. Formatting, persistence and risk logging are inherited unchanged.
class Whatsapp::Dialog360HealthService < Whatsapp::HealthService
  private

  def fetch_health_status_with_error(include_business_profile:)
    validate_channel!

    phone_health = format_phone_health_response(fetch_phone_number_data)
    business_health = format_business_account_response({})
    profile_health = { business_profile: Whatsapp::BusinessProfileService.new(@channel, api_version: @api_version).fetch } if include_business_profile
    [phone_health.merge(business_health, profile_health || {}), nil]
  rescue StandardError => e
    return [phone_health, e] if phone_health

    raise
  end

  def fetch_phone_number_data
    api = @channel.dialog360_cloud_api
    handle_response(HTTParty.get(api.phone_number_url, headers: api.headers, query: { fields: phone_health_fields }))
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP HEALTH] Error fetching health data: #{e.message}"
    raise
  end

  # Meta's errors are a hash, read by the base class; 360dialog's own (a refused key) are a plain string.
  def handle_response(response)
    error = response.parsed_response['error'] if response.parsed_response.is_a?(Hash)
    return super if response.success? || error.is_a?(Hash) || !response.parsed_response.is_a?(Hash)

    message = Whatsapp::Dialog360CloudApi.error_message(response).presence || 'WhatsApp API request failed'
    Rails.logger.error("[WHATSAPP HEALTH] 360dialog API request failed: http_status=#{response.code} message=#{message}")
    raise ApiError.new(message: message, http_status: response.code)
  end
end
