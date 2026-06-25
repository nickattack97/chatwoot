# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamPolicy, type: :policy do
  subject(:team_policy) { described_class }

  let(:account) { create(:account) }
  let(:custom_role) { create(:custom_role, account: account, permissions: ['team_manage']) }
  let(:user) { create(:user) }
  let(:account_user) { create(:account_user, user: user, account: account, role: :agent, custom_role: custom_role) }
  let(:context) { { user: user, account: account, account_user: account_user } }
  let(:team) { :team }

  permissions :index?, :show?, :create?, :update?, :destroy? do
    context 'when agent has team_manage permission' do
      it { expect(team_policy).to permit(context, team) }
    end
  end
end
