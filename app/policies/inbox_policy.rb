class InboxPolicy < ApplicationPolicy
  class Scope
    attr_reader :user_context, :user, :scope, :account, :account_user

    def initialize(user_context, scope)
      @user_context = user_context
      @user = user_context[:user]
      @account = user_context[:account]
      @account_user = user_context[:account_user]
      @scope = scope
    end

    def resolve
      user.assigned_inboxes
    end
  end

  def index?
    true
  end

  def show?
    # FIXME: for agent bots, lets bring this validation to policies as well in future
    return true if @user.is_a?(AgentBot)

    Current.user.assigned_inboxes.include? record
  end

  def assignable_agents?
    true
  end

  def agent_bot?
    true
  end

  def campaigns?
    administrator? || can?('campaign_manage')
  end

  def create?
    administrator? || can?('inbox_manage')
  end

  def update?
    administrator? || can?('inbox_manage')
  end

  def destroy?
    administrator? || can?('inbox_manage')
  end

  def set_agent_bot?
    administrator? || can?('inbox_manage')
  end

  def avatar?
    administrator? || can?('inbox_manage')
  end

  def sync_templates?
    administrator? || can?('inbox_manage')
  end

  def health?
    administrator? || can?('inbox_manage')
  end

  def reset_secret?
    administrator? || can?('inbox_manage')
  end

  private

  def administrator?
    account_user&.administrator?
  end

  def can?(permission)
    @account_user.can?(permission)
  end
end

