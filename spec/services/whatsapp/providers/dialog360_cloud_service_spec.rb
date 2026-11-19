require 'rails_helper'

# A whatsapp_cloud inbox whose number is hosted at 360dialog (provider_config api_host: 360dialog):
# the same Cloud API bodies go to https://waba-v2.360dialog.io with a D360-API-KEY header, never to
# graph.facebook.com and never with a bearer token.
describe Whatsapp::Providers::Dialog360CloudService do
  subject(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', provider_config: { 'api_host' => '360dialog' },
                              validate_provider_config: false, sync_templates: false)
  end
  let(:conversation) { create(:conversation, inbox: whatsapp_channel.inbox) }
  let(:message) do
    create(:message, conversation: conversation, message_type: :outgoing, content: 'test', inbox: whatsapp_channel.inbox)
  end
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:dialog360_headers) { { 'D360-API-KEY' => 'test_key', 'Content-Type' => 'application/json' } }

  def expect_no_bearer_token
    expect(WebMock).not_to have_requested(:any, /.*/).with(headers: { 'Authorization' => /Bearer/ })
  end

  describe '#send_message' do
    it 'sends a text message to 360dialog with the API key' do
      stub = stub_request(:post, 'https://waba-v2.360dialog.io/messages')
             .with(headers: dialog360_headers,
                   body: { messaging_product: 'whatsapp', context: nil, to: '+123456789',
                           text: { body: 'test' }, type: 'text' }.to_json)
             .to_return(status: 200, body: { messages: [{ id: 'wamid.sent' }] }.to_json, headers: json)

      expect(service.send_message('+123456789', message)).to eq('wamid.sent')
      expect(stub).to have_been_requested
      expect_no_bearer_token
    end

    it 'uploads an attachment to 360dialog and sends it by media id' do
      message.attachments.create!(account_id: message.account_id, file_type: :image,
                                  file: { io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png' })
      upload = stub_request(:post, 'https://waba-v2.360dialog.io/media')
               .with(headers: { 'D360-API-KEY' => 'test_key' })
               .to_return(status: 200, body: { id: 'media-1' }.to_json, headers: json)
      send = stub_request(:post, 'https://waba-v2.360dialog.io/messages')
             .with(headers: dialog360_headers, body: hash_including('type' => 'image', 'image' => { 'id' => 'media-1', 'caption' => 'test' }))
             .to_return(status: 200, body: { messages: [{ id: 'wamid.media' }] }.to_json, headers: json)

      expect(service.send_message('+123456789', message)).to eq('wamid.media')
      expect(upload).to have_been_requested
      expect(send).to have_been_requested
      expect_no_bearer_token
    end

    it "marks the message failed with 360dialog's own error, which is a plain string" do
      stub_request(:post, 'https://waba-v2.360dialog.io/messages')
        .to_return(status: 401, body: { error: 'Invalid api token.' }.to_json, headers: json)

      expect(service.send_message('+123456789', message)).to be_nil
      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to eq('Invalid api token.')
    end

    it 'marks the message failed with a Meta error relayed by 360dialog' do
      stub_request(:post, 'https://waba-v2.360dialog.io/messages')
        .to_return(status: 400, body: { error: { message: '(#131047) Re-engagement message', code: 131_047 } }.to_json, headers: json)

      expect(service.send_message('+123456789', message)).to be_nil
      expect(message.reload.external_error).to eq('(#131047) Re-engagement message')
    end
  end

  describe '#send_template' do
    it 'sends the template to 360dialog' do
      stub = stub_request(:post, 'https://waba-v2.360dialog.io/messages')
             .with(headers: dialog360_headers, body: hash_including('type' => 'template', 'to' => '+123456789'))
             .to_return(status: 200, body: { messages: [{ id: 'wamid.template' }] }.to_json, headers: json)

      result = service.send_template('+123456789', { name: 'order_update', lang_code: 'en', parameters: [] }, message)

      expect(result).to eq('wamid.template')
      expect(stub).to have_been_requested
    end
  end

  describe '#sync_templates' do
    it "follows 360dialog's paging and stores every template" do
      stub_request(:get, 'https://waba-v2.360dialog.io/message_templates')
        .with(headers: { 'D360-API-KEY' => 'test_key' })
        .to_return(status: 200, headers: json,
                   body: { data: [{ name: 'first' }], paging: { cursors: { after: 'CURSOR' } } }.to_json)
      stub_request(:get, 'https://waba-v2.360dialog.io/message_templates?after=CURSOR')
        .with(headers: { 'D360-API-KEY' => 'test_key' })
        .to_return(status: 200, headers: json, body: { data: [{ name: 'second' }], paging: { cursors: {} } }.to_json)

      service.sync_templates

      expect(whatsapp_channel.reload.message_templates.pluck('name')).to eq(%w[first second])
      expect_no_bearer_token
    end
  end

  describe '#validate_provider_config?' do
    let(:health_check) { stub_request(:get, 'https://waba-v2.360dialog.io/health_status?fields=id').with(headers: dialog360_headers) }

    it 'accepts a key whose number is the configured phone_number_id' do
      health_check.to_return(status: 200, body: { id: '123456789' }.to_json, headers: json)

      expect(service.validate_provider_config?).to be true
    end

    it 'rejects a key that belongs to a different number' do
      health_check.to_return(status: 200, body: { id: '999999999' }.to_json, headers: json)

      expect(service.validate_provider_config?).to be false
    end

    it 'rejects a key 360dialog refuses' do
      health_check.to_return(status: 401, body: { error: 'Invalid api token.' }.to_json, headers: json)

      expect(service.validate_provider_config?).to be false
    end

    it 'never puts the key in a query string or calls Graph' do
      health_check.to_return(status: 200, body: { id: '123456789' }.to_json, headers: json)

      service.validate_provider_config?

      expect(WebMock).not_to have_requested(:any, /graph\.facebook\.com/)
      expect(WebMock).not_to have_requested(:any, /test_key/)
    end
  end

  describe 'media' do
    it 'resolves a media id on 360dialog with the API key' do
      expect(service.media_url('media-1')).to eq('https://waba-v2.360dialog.io/media-1')
      expect(service.api_headers).to eq(dialog360_headers)
    end
  end
end
