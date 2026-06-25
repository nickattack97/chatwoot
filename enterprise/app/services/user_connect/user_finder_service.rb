module UserConnect
  class UserFinderService
    # UC roles that map to Chatwoot administrator. Format in JWT: "{systemId}_{roleName}".
    ADMIN_ROLE_NAMES = %w[Administrator Admin].freeze
    SUPERVISOR_ROLE_NAME = 'Supervisor'.freeze

    def initialize(claims)
      @claims  = claims
      @account = Account.first
    end

    def perform
      user = find_or_create_user
      ensure_account_membership(user)
      user
    end

    private

    def find_or_create_user
      User.from_email(@claims[:email]) || create_user
    end

    def create_user
      name = [@claims[:first_name], @claims[:surname]].compact.join(' ').presence ||
             @claims[:username] ||
             @claims[:email].split('@').first

      User.create!(
        email:        @claims[:email],
        name:         name,
        display_name: @claims[:first_name].presence,
        provider:     'userconnect',
        uid:          @claims[:email],
        password:     SecureRandom.hex(32),
        confirmed_at: Time.current
      )
    end

    def ensure_account_membership(user)
      account_user = AccountUser.find_or_create_by!(user: user, account: @account)
      account_user.update!(role: chatwoot_role, custom_role_id: custom_role_id(account_user))

      user.update!(provider: 'userconnect') if user.provider != 'userconnect'
    end

    def custom_role_id(account_user)
      return account_user.custom_role_id if account_user.custom_role_id.present? && !userconnect_supervisor_role?

      return nil unless userconnect_supervisor_role?

      @account.custom_roles.find_by(name: SUPERVISOR_ROLE_NAME)&.id
    end

    def chatwoot_role
      return 'administrator' if admin_role?
      return 'agent' # Always return agent for both regular agents and supervisors

      'agent'
    end

    def admin_role?
      system_id = GlobalConfigService.load('UC_SYSTEM_ID', nil).to_s
      prefix    = "#{system_id}_"

      role_name = @claims[:roles]
        .select { |r| r.start_with?(prefix) }
        .map    { |r| r[prefix.length..] }
        .first

      ADMIN_ROLE_NAMES.include?(role_name)
    end

    def userconnect_supervisor_role?
      system_id = GlobalConfigService.load('UC_SYSTEM_ID', nil).to_s
      prefix    = "#{system_id}_"

      role_names = @claims[:roles]
        .select { |r| r.start_with?(prefix) }
        .map    { |r| r[prefix.length..] }

      role_names.include?(SUPERVISOR_ROLE_NAME)
    end
  end
end
