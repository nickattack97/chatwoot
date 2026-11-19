class Channels::Whatsapp::HealthSyncJob < ApplicationJob
  queue_as :low

  def perform(whatsapp_channel)
    whatsapp_channel.health_service.sync_health_status!
  rescue Whatsapp::HealthService::ApiError, ArgumentError
    nil
  end
end
