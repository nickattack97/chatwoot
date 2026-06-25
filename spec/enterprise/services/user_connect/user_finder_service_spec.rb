# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserConnect::UserFinderService, type: :service do
  let(:account) { create(:account) }
  let(:claims) do
    {
      email: 'user@example.com',
      first_name: 'Jane',
      surname: 'Doe',
      username: 'jane.doe',
      roles: ["#{system_id}_Supervisor"]
    }
  end
  let(:system_id) { 'demo-system' }

  before do
    allow(GlobalConfigService).to receive(:load).with('UC_SYSTEM_ID', nil).and_return(system_id)
  end

  describe '#perform' do
    it 'assigns the Supervisor custom role when the userconnect role matches it' do
      custom_role = create(:custom_role, account: account, name: 'Supervisor', permissions: %w[report_manage label_manage team_manage])

      service = described_class.new(claims)
      user = service.perform
      account_user = AccountUser.find_by(user: user, account: account)

      expect(account_user.custom_role_id).to eq(custom_role.id)
      expect(account_user.role).to eq('agent')
    end

    it 'keeps the agent role when there is no matching custom role' do
      service = described_class.new(claims)
      user = service.perform
      account_user = AccountUser.find_by(user: user, account: account)

      expect(account_user.custom_role_id).to be_nil
      expect(account_user.role).to eq('agent')
    end
  end
end
