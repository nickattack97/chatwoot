require 'rails_helper'

RSpec.describe Whatsapp::Dialog360HealthService do
  subject(:service) { described_class.new(channel) }

  let(:channel) do
    create(:channel_whatsapp, phone_number: '+15550001111', provider: 'whatsapp_cloud', provider_config: { 'api_host' => '360dialog' },
                              validate_provider_config: false, sync_templates: false)
  end
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:phone_health_response) do
    {
      'id' => '123456789', 'display_phone_number' => '+1 555-000-1111', 'verified_name' => 'Example Store',
      'name_status' => 'APPROVED', 'quality_rating' => 'GREEN', 'whatsapp_business_manager_messaging_limit' => 'TIER_250',
      'status' => 'CONNECTED', 'account_mode' => 'LIVE', 'throughput' => { 'level' => 'STANDARD' }, 'platform_type' => 'CLOUD_API',
      'health_status' => { 'can_send_message' => 'AVAILABLE' }
    }
  end
  let(:profile_response) { { 'data' => [{ 'about' => 'Support that feels personal', 'websites' => ['https://example.com'] }] } }

  def stub_health(status: 200, body: phone_health_response)
    stub_request(:get, %r{\Ahttps://waba-v2\.360dialog\.io/health_status\?fields=})
      .with(headers: { 'D360-API-KEY' => 'test_key' })
      .to_return(status: status, body: body.to_json, headers: json)
  end

  def stub_profile
    stub_request(:get, %r{\Ahttps://waba-v2\.360dialog\.io/whatsapp_business_profile\?fields=})
      .with(headers: { 'D360-API-KEY' => 'test_key' })
      .to_return(status: 200, body: profile_response.to_json, headers: json)
  end

  it "reads the number's health from 360dialog and stores it" do
    stub_health

    result = service.sync_health_status!

    expect(result).to include(id: '123456789', quality_rating: 'GREEN', messaging_limit_tier: 'TIER_250', status: 'CONNECTED',
                              throughput_level: 'STANDARD', business_account_id: nil, business_account_name: nil)
    expect(channel.reload.phone_number_health).to include('quality_rating' => 'GREEN', 'messaging_limit_tier' => 'TIER_250')
    expect(channel.phone_number_health_error).to be_nil
  end

  it 'reads the business profile from 360dialog, never from Graph, and never puts the key in a URL' do
    stub_health
    profile = stub_profile

    result = service.sync_health_status!(include_business_profile: true)

    expect(profile).to have_been_requested
    expect(result[:business_profile]).to eq(profile_response['data'].first)
    expect(WebMock).not_to have_requested(:any, /graph\.facebook\.com/)
    expect(WebMock).not_to have_requested(:any, /test_key/)
  end

  it 'reports the webhook as managed outside Chatwoot, with no Chatwoot URL to expect' do
    stub_health(body: phone_health_response.merge('webhook_configuration' => { 'application' => 'https://callbacker-v2.360dialog.io/webhook/1/abc' }))

    result = service.sync_health_status!

    expect(result).to include(webhook_managed_externally: true, expected_webhook_url: nil)
    expect(result[:webhook_configuration]).to eq('application' => 'https://callbacker-v2.360dialog.io/webhook/1/abc')
  end

  it "records 360dialog's own error when the key is refused" do
    stub_health(status: 401, body: { error: 'Invalid api token.' })

    expect { service.sync_health_status! }.to raise_error(Whatsapp::HealthService::ApiError, 'Invalid api token.') { |error|
      expect(error.http_status).to eq(401)
    }
    expect(channel.reload.phone_number_health_error).to eq('Invalid api token.')
  end

  it 'reads a Meta error relayed by 360dialog through the inherited handling' do
    stub_health(status: 400, body: { error: { message: 'Unsupported get request', code: 100, error_subcode: 33 } })

    expect { service.sync_health_status! }.to raise_error(Whatsapp::HealthService::ApiError, 'Unsupported get request') { |error|
      expect([error.code, error.subcode]).to eq([100, 33])
    }
  end

  it 'is what a 360dialog-hosted channel uses, and Graph channels keep the Graph service' do
    graph_channel = create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)

    expect(channel.health_service).to be_a(described_class)
    expect(graph_channel.health_service).to be_an_instance_of(Whatsapp::HealthService)
  end
end
