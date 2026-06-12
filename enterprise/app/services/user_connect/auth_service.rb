module UserConnect
  class AuthService
    class UnavailableError < StandardError; end
    class UnauthorizedError < StandardError; end
    class OtpRequiredError < StandardError; end
    class PasswordChangeRequiredError < StandardError; end

    def initialize
      @base_url  = GlobalConfigService.load('UC_BASE_URL', nil)
      @system_id = GlobalConfigService.load('UC_SYSTEM_ID', nil).to_i
    end

    # Returns the raw UC JWT string on success.
    # Raises OtpRequiredError, PasswordChangeRequiredError, UnauthorizedError, or UnavailableError.
    def login(username, password)
      response = post('/api/v1/auth/login', { username: username, password: password, systemId: @system_id })
      body = parse(response)

      raise UnauthorizedError, extract_info(body) || 'Invalid username or password.' unless response.success?
      raise OtpRequiredError, body['otp'] if body.key?('otp')
      raise PasswordChangeRequiredError if body.key?('expired') || body.key?('initial')

      body['token'] or raise UnavailableError, 'Unexpected response from UserConnect'
    end

    # Returns the raw UC JWT string on OTP verification success.
    def verify_otp(username, otp)
      path = "/api/v1/auth/login-with-otp/#{CGI.escape(username)}/#{CGI.escape(otp)}/#{@system_id}"
      response = get(path)
      body = parse(response)

      raise UnauthorizedError, extract_info(body) || 'Invalid or expired OTP.' unless response.success?

      body['token'] or raise UnavailableError, 'Unexpected response from UserConnect'
    end

    # Decodes a UC JWT without signature verification — UC already authenticated the user.
    # Returns a hash with symbolised keys.
    def decode_token(uc_token)
      payload = JWT.decode(uc_token, nil, false).first
      {
        email:      payload['email'],
        username:   payload['userName'],
        first_name: payload['firstName'],
        surname:    payload['surname'],
        system_id:  payload['systemID'],
        roles:      Array(payload['roles'])
      }
    end

    private

    def post(path, body)
      conn.post(path, body.to_json, { 'Content-Type' => 'application/json' })
    rescue Faraday::Error => e
      Rails.logger.error "[UserConnect] POST #{path} failed: #{e.message}"
      raise UnavailableError, 'Unable to reach the authentication service. Please try again later.'
    end

    def get(path)
      conn.get(path)
    rescue Faraday::Error => e
      Rails.logger.error "[UserConnect] GET #{path} failed: #{e.message}"
      raise UnavailableError, 'Unable to reach the authentication service. Please try again later.'
    end

    def conn
      @conn ||= Faraday.new(url: @base_url) do |f|
        f.options.timeout      = 10
        f.options.open_timeout = 5
      end
    end

    def parse(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      {}
    end

    def extract_info(body)
      body.is_a?(Hash) ? body['info'] : nil
    end
  end
end
