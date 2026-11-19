require 'rails_helper'

RSpec.describe Whatsapp::Dialog360CloudApi do
  subject(:api) { described_class.new(channel) }

  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', provider_config: { 'api_host' => '360dialog' },
                              validate_provider_config: false, sync_templates: false)
  end

  describe 'endpoints' do
    it 'puts no version, phone-number id or WABA id in any path' do
      expect(api.base_url).to eq('https://waba-v2.360dialog.io')
      expect(api.media_url('media-1')).to eq('https://waba-v2.360dialog.io/media-1')
      expect(api.media_upload_url).to eq('https://waba-v2.360dialog.io/media')
      expect(api.message_templates_url).to eq('https://waba-v2.360dialog.io/message_templates')
      expect(api.template_management_url).to eq('https://waba-v2.360dialog.io/v1/configs/templates')
      expect(api.phone_number_url).to eq('https://waba-v2.360dialog.io/health_status')
      expect(api.business_profile_url).to eq('https://waba-v2.360dialog.io/whatsapp_business_profile')
    end

    it 'uses WHATSAPP_360DIALOG_CLOUD_BASE_URL when set' do
      with_modified_env WHATSAPP_360DIALOG_CLOUD_BASE_URL: 'https://waba-sandbox.360dialog.io/' do
        expect(api.media_upload_url).to eq('https://waba-sandbox.360dialog.io/media')
      end
    end
  end

  describe 'headers' do
    it 'authenticates with the D360-API-KEY header and never a bearer token' do
      expect(api.headers).to eq('D360-API-KEY' => 'test_key', 'Content-Type' => 'application/json')
      expect(api.auth_headers).to eq('D360-API-KEY' => 'test_key')
    end
  end

  describe '#media_download_url' do
    it "re-hosts Meta's media CDN link onto 360dialog, keeping path and query" do
      url = 'https://lookaside.fbsbx.com/whatsapp_business/attachments/?mid=MEDIA9&ext=1700000000&hash=ATtV'

      expect(api.media_download_url(url))
        .to eq('https://waba-v2.360dialog.io/whatsapp_business/attachments/?mid=MEDIA9&ext=1700000000&hash=ATtV')
    end

    it 'keeps a link that already points at 360dialog' do
      url = 'https://waba-v2.360dialog.io/whatsapp_business/attachments/?mid=MEDIA9'

      expect(api.media_download_url(url)).to eq(url)
    end

    it 'refuses any other host, so the API key is never sent there' do
      expect(api.media_download_url('https://attacker.example/steal?mid=1')).to be_nil
      expect(api.media_download_url('http://waba-v2.360dialog.io/plain-http')).to be_nil
      expect(api.media_download_url('not a url')).to be_nil
    end
  end

  describe '.error_message' do
    def response_with(body)
      instance_double(HTTParty::Response, parsed_response: body)
    end

    it "reads Meta's error relayed by 360dialog" do
      body = { 'error' => { 'message' => '(#131047) Re-engagement message', 'code' => 131_047 } }

      expect(described_class.error_message(response_with(body))).to eq('(#131047) Re-engagement message')
    end

    it "reads 360dialog's own error, which is a plain string" do
      expect(described_class.error_message(response_with({ 'error' => 'Invalid api token.' }))).to eq('Invalid api token.')
    end

    it "reads 360dialog's meta.developer_message shape" do
      body = { 'meta' => { 'developer_message' => 'Endpoint is blocked', 'http_code' => 403 } }

      expect(described_class.error_message(response_with(body))).to eq('Endpoint is blocked')
    end

    it 'returns nil for a body that is not a hash' do
      expect(described_class.error_message(response_with('<html>Bad gateway</html>'))).to be_nil
    end
  end
end
