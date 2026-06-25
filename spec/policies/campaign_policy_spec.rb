# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CampaignPolicy, type: :policy do
  subject(:campaign_policy) { described_class }

  let(:account) { create(:account) }
  let(:custom_role) { create(:custom_role, account: account, permissions: ['campaign_manage']) }
  let(:user) { create(:user) }
  let(:account_user) { create(:account_user, user: user, account: account, role: :agent, custom_role: custom_role) }
  let(:context) { { user: user, account: account, account_user: account_user } }
  let(:campaign) { :campaign }

  permissions :index?, :show?, :create?, :update?, :destroy? do
    context 'when agent has campaign_manage permission' do
      it { expect(campaign_policy).to permit(context, campaign) }
    end
  end
end
