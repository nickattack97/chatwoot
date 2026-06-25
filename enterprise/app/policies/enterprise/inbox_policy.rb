module Enterprise::InboxPolicy
  def index?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('inbox_manage') || super
  end

  def show?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('inbox_manage') || super
  end

  def campaigns?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('campaign_manage') || super
  end

  def create?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('inbox_manage') || super
  end

  def update?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('inbox_manage') || super
  end

  def destroy?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('inbox_manage') || super
  end

  def set_agent_bot?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('inbox_manage') || super
  end

  def avatar?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('inbox_manage') || super
  end

  def sync_templates?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('inbox_manage') || super
  end

  def health?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('inbox_manage') || super
  end

  def reset_secret?
    @account_user.administrator? || @account_user.custom_role&.permissions&.include?('inbox_manage') || super
  end
end
