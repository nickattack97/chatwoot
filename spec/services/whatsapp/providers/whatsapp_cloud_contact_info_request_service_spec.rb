require 'rails_helper'

describe Whatsapp::Providers::WhatsappCloudContactInfoRequestService do
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:conversation) { create(:conversation, inbox: channel.inbox) }
  let(:message) { create(:message, conversation: conversation, message_type: :outgoing, content: 'Please share your details', inbox: channel.inbox) }

  context 'with a Graph inbox' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }

    it 'sends the request to Graph with the bearer token' do
      stub = stub_request(:post, 'https://graph.facebook.com/v22.0/123456789/messages')
             .with(headers: { 'Authorization' => 'Bearer test_key' }, body: hash_including('type' => 'interactive'))
             .to_return(status: 200, body: { messages: [{ id: 'wamid.graph' }] }.to_json, headers: json)

      expect(described_class.perform(channel, '+15550002222', message)).to eq('wamid.graph')
      expect(stub).to have_been_requested
    end
  end

  context 'with a 360dialog-hosted inbox' do
    let(:channel) do
      create(:channel_whatsapp, provider: 'whatsapp_cloud', provider_config: { 'api_host' => '360dialog' },
                                validate_provider_config: false, sync_templates: false)
    end

    it 'sends the request to 360dialog with the API key' do
      stub = stub_request(:post, 'https://waba-v2.360dialog.io/messages')
             .with(headers: { 'D360-API-KEY' => 'test_key' },
                   body: hash_including('type' => 'interactive', 'to' => '+15550002222',
                                        'interactive' => hash_including('type' => 'request_contact_info')))
             .to_return(status: 200, body: { messages: [{ id: 'wamid.360' }] }.to_json, headers: json)

      expect(described_class.perform(channel, '+15550002222', message)).to eq('wamid.360')
      expect(stub).to have_been_requested
      expect(WebMock).not_to have_requested(:any, /graph\.facebook\.com/)
    end

    it "marks the message failed with 360dialog's own error" do
      stub_request(:post, 'https://waba-v2.360dialog.io/messages')
        .to_return(status: 401, body: { error: 'Invalid api token.' }.to_json, headers: json)

      expect(described_class.perform(channel, '+15550002222', message)).to be_nil
      expect(message.reload.external_error).to eq('Invalid api token.')
    end
  end
end
