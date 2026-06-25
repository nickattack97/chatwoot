module Enterprise::TeamPolicy
  def index?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('team_manage') || super
  end

  def update?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('team_manage') || super
  end

  def show?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('team_manage') || super
  end

  def create?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('team_manage') || super
  end

  def destroy?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('team_manage') || super
  end
end
