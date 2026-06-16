module UserConnect
  class AuthService
    class UnavailableError < StandardError; end
    class UnauthorizedError < StandardError; end
    class OtpRequiredError < StandardError; end
    # Message carries the CHANGE_PASSWORD JWT issued by UC on expiry/initial login.
    class PasswordChangeRequiredError < StandardError; end

    def initialize
      @base_url  = GlobalConfigService.load('UC_BASE_URL', nil)
      @system_id = GlobalConfigService.load('UC_SYSTEM_ID', nil).to_i
    end

    # Returns the raw UC JWT string on success.
    # Raises OtpRequiredError, PasswordChangeRequiredError (with JWT as message), UnauthorizedError, or UnavailableError.
    def login(username, password)
      response = post('/api/v1/auth/login', { username: username, password: password, systemId: @system_id })
      body = parse(response)

      raise UnauthorizedError, extract_info(body) || 'Invalid username or password.' unless response.success?
      raise OtpRequiredError, body['otp'] if body.key?('otp')
      raise PasswordChangeRequiredError, (body['expired'] || body['initial']) if body.key?('expired') || body.key?('initial')

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

    # Initiates the forgot-password flow — UC sends an OTP to the user's registered email.
    def forgot_password(username)
      response = get("/api/v1/auth/forgot-password/#{CGI.escape(username)}")
      body = parse(response)
      raise UnauthorizedError, extract_info(body) || 'Account not found.' unless response.success?

      body
    end

    # Resends the forgot-password OTP.
    def resend_forgot_password_otp(username)
      response = get("/api/v1/auth/resend-forgot-password-otp/#{CGI.escape(username)}")
      body = parse(response)
      raise UnauthorizedError, extract_info(body) || 'Could not resend OTP.' unless response.success?

      body
    end

    # Completes the forgot-password reset using the OTP sent to email.
    def change_forgotten_password(username, otp, new_password, confirm_password)
      response = put('/api/v1/auth/change-forgotten-password', {
                       username: username, otp: otp,
                       newPassword: new_password, confirmPassword: confirm_password
                     })
      body = parse(response)
      raise UnauthorizedError, extract_info(body) || 'Password reset failed.' unless response.success?

      body
    end

    # Changes the password for an expired/initial-login user.
    # change_password_token is the CHANGE_PASSWORD JWT returned by UC on login.
    def change_password(change_password_token, new_password, confirm_password)
      response = put(
        '/api/v1/auth/change-password',
        { newPassword: new_password, confirmPassword: confirm_password },
        { 'Authorization' => "Bearer #{change_password_token}" }
      )
      body = parse(response)
      raise UnauthorizedError, extract_info(body) || 'Password change failed.' unless response.success?

      body
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

    def put(path, body, extra_headers = {})
      headers = { 'Content-Type' => 'application/json' }.merge(extra_headers)
      conn.put(path, body.to_json, headers)
    rescue Faraday::Error => e
      Rails.logger.error "[UserConnect] PUT #{path} failed: #{e.message}"
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
