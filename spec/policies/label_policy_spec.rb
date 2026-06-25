# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LabelPolicy, type: :policy do
  subject(:label_policy) { described_class }

  let(:account) { create(:account) }
  let(:custom_role) { create(:custom_role, account: account, permissions: ['label_manage']) }
  let(:user) { create(:user) }
  let(:account_user) { create(:account_user, user: user, account: account, role: :agent, custom_role: custom_role) }
  let(:context) { { user: user, account: account, account_user: account_user } }
  let(:label) { :label }

  permissions :index?, :show?, :create?, :update?, :destroy? do
    context 'when agent has label_manage permission' do
      it { expect(label_policy).to permit(context, label) }
    end
  end
end
