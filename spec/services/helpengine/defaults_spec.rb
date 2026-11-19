require 'rails_helper'

RSpec.describe Helpengine::Defaults do
  let(:account) { create(:account) }
  let(:config) { described_class.config }

  describe '.apply_installation!' do
    it "switches UserConnect sign-in on and points it at this environment's UserConnect" do
      described_class.apply_installation!(env: { 'UC_BASE_URL' => 'http://uc.example:9700', 'UC_SYSTEM_ID' => '10022',
                                                 'UC_BASE_URL_EXTERNAL' => 'https://uc.example' })

      expect(GlobalConfigService.load('UC_SSO_ENABLED', 'false')).to be true
      expect(GlobalConfigService.load('UC_CREDENTIAL_PROXY_ENABLED', 'false')).to be true
      expect(GlobalConfigService.load('UC_BASE_URL', nil)).to eq('http://uc.example:9700')
      expect(GlobalConfigService.load('UC_SYSTEM_ID', nil)).to eq('10022')
      expect(GlobalConfigService.load('UC_BASE_URL_EXTERNAL', nil)).to eq('https://uc.example')
    end

    it 'leaves the UserConnect address alone when the environment does not give one' do
      InstallationConfig.create!(name: 'UC_BASE_URL', value: 'http://existing.example')

      described_class.apply_installation!(env: {})

      expect(GlobalConfigService.load('UC_BASE_URL', nil)).to eq('http://existing.example')
      expect(GlobalConfigService.load('UC_SSO_ENABLED', 'false')).to be true
    end
  end

  describe '.apply_account!' do
    it 'creates the labels, custom attributes, canned responses, automation rules and macros' do
      described_class.apply_account!(account)

      expect(account.labels.pluck(:title)).to match_array(config['labels'].pluck('title'))
      expect(account.custom_attribute_definitions.count).to eq(config['custom_attributes'].size)
      expect(account.canned_responses.pluck(:short_code)).to match_array(config['canned_responses'].pluck('short_code'))
      expect(account.automation_rules.pluck(:name)).to match_array(config['automation_rules'].pluck('name'))
      expect(account.macros.pluck(:name)).to match_array(config['macros'].pluck('name'))
    end

    it 'seeds the resolution rule switched off' do
      described_class.apply_account!(account)

      expect(account.automation_rules.find_by(name: 'Mark Pending on Resolution').active).to be false
      expect(account.automation_rules.where(active: true).count).to eq(3)
    end

    it 'only adds what is missing and never changes what an administrator edited' do
      described_class.apply_account!(account)
      account.labels.find_by(title: 'loan').update!(description: 'Edited by an admin')
      account.canned_responses.find_by(short_code: 'hold').update!(content: 'Edited reply')

      expect { described_class.apply_account!(account) }.not_to(change do
        [account.labels.count, account.canned_responses.count, account.automation_rules.count, account.macros.count,
         account.custom_attribute_definitions.count]
      end)
      expect(account.labels.find_by(title: 'loan').description).to eq('Edited by an admin')
      expect(account.canned_responses.find_by(short_code: 'hold').content).to eq('Edited reply')
    end

    it "makes the account's first administrator the macros' author" do
      admin = create(:user, account: account, role: :administrator)

      described_class.apply_account!(account)

      expect(account.macros.pluck(:created_by_id).uniq).to eq([admin.id])
    end
  end

  describe '.apply_whatsapp_inbox!' do
    let(:inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
    end

    it 'turns the Chatwoot greeting off, does not lock conversations, and sets Harare working hours' do
      inbox.update!(greeting_enabled: true, lock_to_single_conversation: true)

      described_class.apply_whatsapp_inbox!(inbox)

      inbox.reload
      expect(inbox.greeting_enabled).to be false
      expect(inbox.lock_to_single_conversation).to be false
      expect(inbox.working_hours_enabled).to be true
      expect(inbox.timezone).to eq('Africa/Harare')
      expect(inbox.working_hours.find_by(day_of_week: 0).closed_all_day).to be true
      expect(inbox.working_hours.find_by(day_of_week: 6)).to have_attributes(open_hour: 8, close_hour: 13, closed_all_day: false)
    end
  end

  # Everything below goes out on WhatsApp: the WhatsApp Business Messaging Policy forbids asking for full account or card
  # numbers, and a placeholder must never reach a customer.
  describe 'customer-facing text' do
    let(:texts) do
      sent = lambda do |records|
        records.flat_map { |r| r['actions'].select { |a| a['action_name'] == 'send_message' }.flat_map { |a| a['action_params'] } }
      end
      config['canned_responses'].pluck('content') + sent.call(config['macros']) + sent.call(config['automation_rules']) +
        [config.dig('whatsapp_inbox', 'out_of_office_message')]
    end

    it 'contains no placeholder' do
      expect(texts.grep(/XXXX|CHANGE_ME|TODO|\{\{agent_name\}\}/)).to be_empty
    end

    it 'never asks the customer for an account or card number, PIN, password or OTP' do
      asks_for = /\b(provide|send|share|give|confirm|type|enter)\b[^.]{0,30}\b(account number|card number|pin|password|otp)\b/i
      # A warning not to share them ("Never share your PIN ...") is what we want customers to read.
      warns = /\b(never|do not|don't|will not)\b/i
      requests = texts.flat_map { |text| text.split(/(?<=[.!?;])\s+/) }.select { |s| s.match?(asks_for) && !s.match?(warns) }

      expect(requests).to be_empty
    end

    it 'has no welcome rule: WA-Bot-Engine sends the handoff greeting' do
      expect(config['automation_rules'].pluck('event_name')).not_to include('conversation_created')
    end
  end

  describe 'creation hooks' do
    it 'stay off in the test environment, so upstream specs get a bare account' do
      expect(create(:account).labels).to be_empty
    end

    it 'give a new account its defaults and a new WhatsApp inbox its settings when enabled' do
      with_modified_env HELPENGINE_DEFAULTS: 'true' do
        new_account = create(:account)
        expect(new_account.labels.count).to eq(config['labels'].size)

        inbox = create(:channel_whatsapp, account: new_account, provider: 'whatsapp_cloud',
                                          validate_provider_config: false, sync_templates: false).inbox
        expect(inbox.reload.timezone).to eq('Africa/Harare')
        expect(inbox.greeting_enabled).to be false
      end
    end
  end
end
