class LabelPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator? || @account_user.can?('label_manage')
  end

  def show?
    @account_user.administrator? || @account_user.can?('label_manage')
  end

  def create?
    @account_user.administrator? || @account_user.can?('label_manage')
  end

  def destroy?
    @account_user.administrator? || @account_user.can?('label_manage')
  end
end

LabelPolicy.prepend_mod_with('LabelPolicy')
