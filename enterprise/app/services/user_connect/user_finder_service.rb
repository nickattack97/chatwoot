module UserConnect
  class UserFinderService
    # UC roles that map to Chatwoot administrator. Format in JWT: "{systemId}_{roleName}".
    ADMIN_ROLE_NAMES = %w[Administrator Admin].freeze

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
      account_user.update!(role: chatwoot_role)

      user.update!(provider: 'userconnect') if user.provider != 'userconnect'
    end

    def chatwoot_role
      system_id = GlobalConfigService.load('UC_SYSTEM_ID', nil).to_s
      prefix    = "#{system_id}_"

      role_name = @claims[:roles]
        .select { |r| r.start_with?(prefix) }
        .map    { |r| r[prefix.length..] }
        .first

      ADMIN_ROLE_NAMES.include?(role_name) ? 'administrator' : 'agent'
    end
  end
end
