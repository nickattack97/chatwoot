class TeamPolicy < ApplicationPolicy
  def index?
    true
  end

  def update?
    @account_user.administrator? || @account_user.can?('team_manage')
  end

  def show?
    true
  end

  def create?
    @account_user.administrator? || @account_user.can?('team_manage')
  end

  def destroy?
    @account_user.administrator? || @account_user.can?('team_manage')
  end
end

TeamPolicy.prepend_mod_with('TeamPolicy')
