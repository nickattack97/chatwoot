class Enterprise::UserconnectAuthController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  # GET /auth/uc_sso
  # Redirects the browser to UserConnect's SAML login endpoint (Path 1).
  def sso_initiate
    return render_disabled unless uc_sso_enabled?

    uc_base   = GlobalConfigService.load('UC_BASE_URL', nil)
    system_id = GlobalConfigService.load('UC_SYSTEM_ID', nil)
    redirect_to "#{uc_base}/api/v1/auth/saml/login?systemId=#{system_id}", allow_other_host: true
  end

  # GET /auth/uc_callback?token=…&systemId=…
  # Receives the UC JWT after Entra authentication, issues an sso_auth_token, redirects to login page.
  def sso_callback
    return render_disabled unless uc_sso_enabled?

    uc_token = params[:token]
    return redirect_to_login(error: 'uc-authentication-failed') if uc_token.blank?

    claims = auth_service.decode_token(uc_token)
    user   = UserConnect::UserFinderService.new(claims).perform
    redirect_to user.generate_sso_link, allow_other_host: true
  rescue StandardError => e
    Rails.logger.error "[UserConnect] SSO callback error: #{e.message}"
    redirect_to_login(error: 'uc-authentication-failed')
  end

  # POST /api/v1/auth/uc_sign_in
  # Body: { username, password } — proxied to UserConnect (Path 2).
  def credential_sign_in
    return render_disabled unless uc_credential_proxy_enabled?

    uc_token = auth_service.login(params[:username], params[:password])
    sign_in_from_uc_token(uc_token)

  rescue UserConnect::AuthService::OtpRequiredError => e
    render json: { requiresOtp: true, otpMessage: e.message }, status: :ok

  rescue UserConnect::AuthService::PasswordChangeRequiredError => e
    render json: { requiresPasswordChange: true, changePasswordToken: e.message }, status: :ok

  rescue UserConnect::AuthService::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable

  rescue UserConnect::AuthService::UnauthorizedError => e
    render json: { error: e.message }, status: :unauthorized
  end

  # POST /api/v1/auth/uc_verify_otp
  # Body: { username, otp }
  def credential_verify_otp
    return render_disabled unless uc_credential_proxy_enabled?

    uc_token = auth_service.verify_otp(params[:username], params[:otp])
    sign_in_from_uc_token(uc_token)

  rescue UserConnect::AuthService::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable

  rescue UserConnect::AuthService::UnauthorizedError => e
    render json: { error: e.message }, status: :unauthorized
  end

  # POST /api/v1/auth/uc_forgot_password
  # Body: { username }
  def forgot_password
    return render_disabled unless uc_credential_proxy_enabled?

    auth_service.forgot_password(params[:username])
    render json: { info: 'A reset code has been sent to your registered email.' }, status: :ok

  rescue UserConnect::AuthService::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable

  rescue UserConnect::AuthService::UnauthorizedError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/auth/uc_resend_forgot_password_otp
  # Body: { username }
  def resend_forgot_password_otp
    return render_disabled unless uc_credential_proxy_enabled?

    auth_service.resend_forgot_password_otp(params[:username])
    render json: { info: 'Reset code resent.' }, status: :ok

  rescue UserConnect::AuthService::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable

  rescue UserConnect::AuthService::UnauthorizedError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PUT /api/v1/auth/uc_change_forgotten_password
  # Body: { username, otp, newPassword, confirmPassword }
  def change_forgotten_password
    return render_disabled unless uc_credential_proxy_enabled?

    auth_service.change_forgotten_password(
      params[:username], params[:otp],
      params[:newPassword], params[:confirmPassword]
    )
    render json: { info: 'Password changed successfully. You can now sign in.' }, status: :ok

  rescue UserConnect::AuthService::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable

  rescue UserConnect::AuthService::UnauthorizedError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PUT /api/v1/auth/uc_change_password
  # Body: { changePasswordToken, newPassword, confirmPassword }
  def change_password
    return render_disabled unless uc_credential_proxy_enabled?

    auth_service.change_password(
      params[:changePasswordToken],
      params[:newPassword],
      params[:confirmPassword]
    )
    render json: { info: 'Password changed successfully.' }, status: :ok

  rescue UserConnect::AuthService::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable

  rescue UserConnect::AuthService::UnauthorizedError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def sign_in_from_uc_token(uc_token)
    claims    = auth_service.decode_token(uc_token)
    @resource = UserConnect::UserFinderService.new(claims).perform
    @token    = @resource.create_token
    @resource.save!
    sign_in(:user, @resource, store: false, bypass: false)

    render partial: 'devise/auth', formats: [:json], locals: { resource: @resource }
  end

  def auth_service
    @auth_service ||= UserConnect::AuthService.new
  end

  def uc_sso_enabled?
    GlobalConfigService.load('UC_SSO_ENABLED', 'false').to_s == 'true'
  end

  def uc_credential_proxy_enabled?
    GlobalConfigService.load('UC_CREDENTIAL_PROXY_ENABLED', 'false').to_s == 'true'
  end

  def render_disabled
    render json: { error: 'UserConnect auth is not enabled.' }, status: :forbidden
  end

  def redirect_to_login(error:)
    frontend_url = ENV.fetch('FRONTEND_URL', '')
    redirect_to "#{frontend_url}/app/login?error=#{error}", allow_other_host: true
  end
end
