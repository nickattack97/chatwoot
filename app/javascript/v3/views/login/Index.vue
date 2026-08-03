<script>
// utils and composables
import {
  login,
  ucSignIn,
  ucVerifyOtp,
  ucForgotPassword,
  ucResendForgotPasswordOtp,
  ucChangeForgottenPassword,
  ucChangePassword,
} from '../../api/auth';
import { setAuthCredentials } from 'dashboard/store/utils/api';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import { useBranding } from 'shared/composables/useBranding';
import { getLoginRedirectURL } from 'v3/helpers/AuthHelper';
import { absoluteURL } from 'dashboard/helper/URLHelper';

// components
import SimpleDivider from '../../components/Divider/SimpleDivider.vue';
import FormInput from '../../components/Form/Input.vue';
import GoogleOAuthButton from '../../components/GoogleOauth/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';

const ERROR_MESSAGES = {
  'no-account-found': 'LOGIN.OAUTH.NO_ACCOUNT_FOUND',
  'business-account-only': 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY',
  'saml-authentication-failed': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'saml-not-enabled': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'uc-authentication-failed': 'LOGIN.USERCONNECT.AUTH_FAILED',
};

const IMPERSONATION_URL_SEARCH_KEY = 'impersonation';
const USER_NOT_CONFIRMED_ERROR_CODE = 'user_not_confirmed';

export default {
  components: {
    FormInput,
    GoogleOAuthButton,
    Spinner,
    NextButton,
    SimpleDivider,
    MfaVerification,
    Icon,
  },
  props: {
    ssoAuthToken: { type: String, default: '' },
    ssoAccountId: { type: String, default: '' },
    ssoConversationId: { type: String, default: '' },
    email: { type: String, default: '' },
    authError: { type: String, default: '' },
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    return {
      replaceInstallationName,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      credentials: {
        email: '',
        password: '',
      },
      ucCredentials: {
        username: '',
        password: '',
      },
      ucOtp: '',
      ucOtpRequired: false,
      ucOtpMessage: '',
      // Forced password change (expired/initial login)
      ucPasswordChangeRequired: false,
      ucChangePasswordToken: null,
      ucNewPassword: '',
      ucConfirmPassword: '',
      // Forgot password flow
      ucForgotStep: null, // null | 'username' | 'reset' | 'success'
      ucForgotUsername: '',
      ucForgotOtp: '',
      ucForgotNewPassword: '',
      ucForgotConfirmPassword: '',
      loginApi: {
        message: '',
        showLoading: false,
        hasErrored: false,
      },
      error: '',
      mfaRequired: false,
      mfaToken: null,
    };
  },
  validations() {
    return {
      credentials: {
        password: {
          required,
        },
        email: {
          required,
          email,
        },
      },
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    allowedLoginMethods() {
      return window.chatwootConfig.allowedLoginMethods || ['email'];
    },
    showGoogleOAuth() {
      return (
        this.allowedLoginMethods.includes('google_oauth') &&
        Boolean(window.chatwootConfig.googleOAuthClientId)
      );
    },
    showSignupLink() {
      return window.chatwootConfig.signupEnabled === 'true';
    },
    showSamlLogin() {
      return this.allowedLoginMethods.includes('saml');
    },
    showUcSsoLogin() {
      return this.allowedLoginMethods.includes('userconnect_sso');
    },
    // Native anchor (full page navigation to a Rails route), so it needs the
    // deployment base path applied explicitly.
    ucSsoUrl() {
      return absoluteURL('/uc/sso');
    },
    showUcCredentialsLogin() {
      return this.allowedLoginMethods.includes('userconnect_credentials');
    },
  },
  created() {
    if (this.ssoAuthToken) {
      this.submitLogin();
    }
    if (this.authError) {
      const messageKey = ERROR_MESSAGES[this.authError] ?? 'LOGIN.API.UNAUTH';
      const translatedMessage = this.getTranslatedMessage(messageKey);
      useAlert(translatedMessage);
      this.requestIdleCallbackPolyfill(() => {
        const { query } = this.$route;
        this.$router.replace({ query: { ...query, error: undefined } });
      });
    }
  },
  methods: {
    getTranslatedMessage(key) {
      switch (key) {
        case 'LOGIN.OAUTH.NO_ACCOUNT_FOUND':
          return this.$t('LOGIN.OAUTH.NO_ACCOUNT_FOUND');
        case 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY':
          return this.$t('LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY');
        case 'LOGIN.USERCONNECT.AUTH_FAILED':
          return this.$t('LOGIN.USERCONNECT.AUTH_FAILED');
        case 'LOGIN.API.UNAUTH':
        default:
          return this.$t('LOGIN.API.UNAUTH');
      }
    },
    requestIdleCallbackPolyfill(callback) {
      if (window.requestIdleCallback) {
        window.requestIdleCallback(callback);
      } else {
        setTimeout(callback, 0);
      }
    },
    showAlertMessage(message) {
      this.loginApi.showLoading = false;
      this.loginApi.message = message;
      useAlert(this.loginApi.message);
    },
    handleImpersonation() {
      const urlParams = new URLSearchParams(window.location.search);
      const impersonation = urlParams.get(IMPERSONATION_URL_SEARCH_KEY);
      if (impersonation) {
        SessionStorage.set(SESSION_STORAGE_KEYS.IMPERSONATION_USER, true);
      }
    },
    submitLogin() {
      this.loginApi.hasErrored = false;
      this.loginApi.showLoading = true;

      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
      };

      login(credentials)
        .then(result => {
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            return;
          }

          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          if (response?.errorCode === USER_NOT_CONFIRMED_ERROR_CODE) {
            this.loginApi.showLoading = false;
            this.$router.push({
              name: 'auth_verify_email',
              state: { email: credentials.email },
            });
            return;
          }

          if (this.email) {
            window.location = absoluteURL('/app/login');
          }
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    submitFormLogin() {
      if (this.v$.credentials.email.$invalid && !this.email) {
        this.showAlertMessage(this.$t('LOGIN.EMAIL.ERROR'));
        return;
      }

      this.submitLogin();
    },
    handleMfaVerified() {
      this.handleImpersonation();
      window.location = absoluteURL('/app');
    },
    handleMfaCancel() {
      this.mfaRequired = false;
      this.mfaToken = null;
      this.credentials.password = '';
    },

    // ── UC credentials login ─────────────────────────────────────────────────
    async submitUcCredentials() {
      if (!this.ucCredentials.username || !this.ucCredentials.password) return;
      this.loginApi.showLoading = true;
      this.loginApi.hasErrored = false;
      try {
        const response = await ucSignIn({
          username: this.ucCredentials.username,
          password: this.ucCredentials.password,
        });
        if (response.data?.requiresOtp) {
          this.ucOtpRequired = true;
          this.ucOtpMessage =
            response.data.otpMessage ||
            this.$t('LOGIN.USERCONNECT.OTP_SUBTITLE');
          this.loginApi.showLoading = false;
          return;
        }
        if (response.data?.requiresPasswordChange) {
          this.ucPasswordChangeRequired = true;
          this.ucChangePasswordToken = response.data.changePasswordToken;
          this.loginApi.showLoading = false;
          return;
        }
        this.handleUcAuthSuccess(response);
      } catch (error) {
        this.loginApi.showLoading = false;
        this.loginApi.hasErrored = true;
        this.showAlertMessage(
          error.response?.data?.error ||
            this.$t('LOGIN.USERCONNECT.UNAVAILABLE')
        );
      }
    },
    async submitUcOtp() {
      if (!this.ucOtp) return;
      this.loginApi.showLoading = true;
      try {
        const response = await ucVerifyOtp({
          username: this.ucCredentials.username,
          otp: this.ucOtp,
        });
        this.handleUcAuthSuccess(response);
      } catch (error) {
        this.loginApi.showLoading = false;
        this.loginApi.hasErrored = true;
        this.showAlertMessage(
          error.response?.data?.error || this.$t('LOGIN.API.UNAUTH')
        );
      }
    },
    handleUcAuthSuccess(response) {
      setAuthCredentials(response);
      const user = response.data?.data;
      window.location = getLoginRedirectURL({
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
        user,
      });
    },
    cancelUcOtp() {
      this.ucOtpRequired = false;
      this.ucOtp = '';
      this.loginApi.showLoading = false;
      this.loginApi.hasErrored = false;
    },

    // ── Forced password change (expired / initial) ───────────────────────────
    async submitUcChangePassword() {
      if (!this.ucNewPassword || !this.ucConfirmPassword) {
        this.showAlertMessage(this.$t('LOGIN.USERCONNECT.PASSWORD_REQUIRED'));
        return;
      }
      if (this.ucNewPassword !== this.ucConfirmPassword) {
        this.showAlertMessage(
          this.$t('LOGIN.USERCONNECT.PASSWORDS_DO_NOT_MATCH')
        );
        return;
      }
      this.loginApi.showLoading = true;
      this.loginApi.hasErrored = false;
      try {
        await ucChangePassword({
          changePasswordToken: this.ucChangePasswordToken,
          newPassword: this.ucNewPassword,
          confirmPassword: this.ucConfirmPassword,
        });
        // Auto-resubmit login with the new password
        this.ucCredentials.password = this.ucNewPassword;
        this.ucPasswordChangeRequired = false;
        this.ucChangePasswordToken = null;
        this.ucNewPassword = '';
        this.ucConfirmPassword = '';
        await this.submitUcCredentials();
      } catch (error) {
        this.loginApi.showLoading = false;
        this.loginApi.hasErrored = true;
        this.showAlertMessage(
          error.response?.data?.error ||
            this.$t('LOGIN.USERCONNECT.UNAVAILABLE')
        );
      }
    },
    cancelUcChangePassword() {
      this.ucPasswordChangeRequired = false;
      this.ucChangePasswordToken = null;
      this.ucNewPassword = '';
      this.ucConfirmPassword = '';
      this.ucCredentials.password = '';
      this.loginApi.hasErrored = false;
    },

    // ── Forgot password flow ─────────────────────────────────────────────────
    openForgotPassword() {
      this.ucForgotStep = 'username';
      this.ucForgotUsername = this.ucCredentials.username;
      this.ucForgotOtp = '';
      this.ucForgotNewPassword = '';
      this.ucForgotConfirmPassword = '';
      this.loginApi.hasErrored = false;
    },
    cancelForgotPassword() {
      this.ucForgotStep = null;
      this.ucForgotUsername = '';
      this.ucForgotOtp = '';
      this.ucForgotNewPassword = '';
      this.ucForgotConfirmPassword = '';
      this.loginApi.hasErrored = false;
    },
    async submitForgotPasswordUsername() {
      if (!this.ucForgotUsername) return;
      this.loginApi.showLoading = true;
      this.loginApi.hasErrored = false;
      try {
        await ucForgotPassword({ username: this.ucForgotUsername });
        this.ucForgotStep = 'reset';
        this.loginApi.showLoading = false;
      } catch (error) {
        this.loginApi.showLoading = false;
        this.loginApi.hasErrored = true;
        this.showAlertMessage(
          error.response?.data?.error ||
            this.$t('LOGIN.USERCONNECT.UNAVAILABLE')
        );
      }
    },
    async resendForgotPasswordOtp() {
      this.loginApi.showLoading = true;
      try {
        await ucResendForgotPasswordOtp({ username: this.ucForgotUsername });
        this.loginApi.showLoading = false;
        useAlert(this.$t('LOGIN.USERCONNECT.FORGOT_OTP_RESEND_SUCCESS'));
      } catch (error) {
        this.loginApi.showLoading = false;
        this.showAlertMessage(
          error.response?.data?.error ||
            this.$t('LOGIN.USERCONNECT.UNAVAILABLE')
        );
      }
    },
    async submitForgotPasswordReset() {
      if (!this.ucForgotNewPassword || !this.ucForgotConfirmPassword) {
        this.showAlertMessage(this.$t('LOGIN.USERCONNECT.PASSWORD_REQUIRED'));
        return;
      }
      if (this.ucForgotNewPassword !== this.ucForgotConfirmPassword) {
        this.showAlertMessage(
          this.$t('LOGIN.USERCONNECT.PASSWORDS_DO_NOT_MATCH')
        );
        return;
      }
      this.loginApi.showLoading = true;
      this.loginApi.hasErrored = false;
      try {
        await ucChangeForgottenPassword({
          username: this.ucForgotUsername,
          otp: this.ucForgotOtp,
          newPassword: this.ucForgotNewPassword,
          confirmPassword: this.ucForgotConfirmPassword,
        });
        this.ucForgotStep = 'success';
        // Pre-fill username on the main form so the user can log in straight away
        this.ucCredentials.username = this.ucForgotUsername;
        this.loginApi.showLoading = false;
      } catch (error) {
        this.loginApi.showLoading = false;
        this.loginApi.hasErrored = true;
        this.showAlertMessage(
          error.response?.data?.error ||
            this.$t('LOGIN.USERCONNECT.UNAVAILABLE')
        );
      }
    },
    returnToLoginFromForgot() {
      this.ucForgotStep = null;
      this.ucForgotOtp = '';
      this.ucForgotNewPassword = '';
      this.ucForgotConfirmPassword = '';
      this.loginApi.hasErrored = false;
    },
  },
};
</script>

<template>
  <main
    class="flex flex-col w-full min-h-screen py-20 bg-n-brand/5 dark:bg-n-background sm:px-6 lg:px-8"
  >
    <section class="max-w-5xl mx-auto">
      <img
        :src="globalConfig.logo"
        :alt="globalConfig.installationName"
        class="block w-auto h-8 mx-auto dark:hidden"
      />
      <img
        v-if="globalConfig.logoDark"
        :src="globalConfig.logoDark"
        :alt="globalConfig.installationName"
        class="hidden w-auto h-8 mx-auto dark:block"
      />
      <h2 class="mt-6 text-3xl font-medium text-center text-n-slate-12">
        {{ replaceInstallationName($t('LOGIN.TITLE')) }}
      </h2>
      <p v-if="showSignupLink" class="mt-3 text-sm text-center text-n-slate-11">
        {{ $t('COMMON.OR') }}
        <router-link to="auth/signup" class="lowercase text-link text-n-brand">
          {{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}
        </router-link>
      </p>
    </section>

    <!-- MFA Verification Section -->
    <section v-if="mfaRequired" class="mt-11">
      <MfaVerification
        :mfa-token="mfaToken"
        @verified="handleMfaVerified"
        @cancel="handleMfaCancel"
      />
    </section>

    <!-- Regular Login Section -->
    <section
      v-else
      class="bg-white shadow sm:mx-auto mt-11 sm:w-full sm:max-w-lg dark:bg-n-solid-2 p-11 sm:shadow-lg sm:rounded-lg"
      :class="{
        'mb-8 mt-15': !showGoogleOAuth,
        'animate-wiggle': loginApi.hasErrored,
      }"
    >
      <!-- UC OTP verification step -->
      <div v-if="ucOtpRequired" class="space-y-5">
        <p class="text-sm text-center text-n-slate-11">{{ ucOtpMessage }}</p>
        <FormInput
          v-model="ucOtp"
          name="otp"
          type="text"
          :label="$t('LOGIN.USERCONNECT.OTP_TITLE')"
          :placeholder="$t('LOGIN.USERCONNECT.OTP_PLACEHOLDER')"
        />
        <NextButton
          lg
          class="w-full"
          :label="$t('LOGIN.USERCONNECT.OTP_SUBMIT')"
          :disabled="loginApi.showLoading"
          :is-loading="loginApi.showLoading"
          @click="submitUcOtp"
        />
        <button
          type="button"
          class="w-full text-sm text-center text-n-slate-11 hover:text-n-slate-12"
          @click="cancelUcOtp"
        >
          {{ $t('LOGIN.USERCONNECT.OTP_BACK') }}
        </button>
      </div>

      <!-- UC forced password change (expired / initial login) -->
      <div v-else-if="ucPasswordChangeRequired" class="space-y-5">
        <div class="space-y-1">
          <h3 class="text-lg font-medium text-n-slate-12">
            {{ $t('LOGIN.USERCONNECT.CHANGE_PASSWORD_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11">
            {{ $t('LOGIN.USERCONNECT.CHANGE_PASSWORD_EXPIRED_SUBTITLE') }}
          </p>
        </div>
        <FormInput
          v-model="ucNewPassword"
          type="password"
          name="uc_new_password"
          :label="$t('LOGIN.USERCONNECT.NEW_PASSWORD_LABEL')"
          :placeholder="$t('LOGIN.USERCONNECT.NEW_PASSWORD_PLACEHOLDER')"
        />
        <FormInput
          v-model="ucConfirmPassword"
          type="password"
          name="uc_confirm_password"
          :label="$t('LOGIN.USERCONNECT.CONFIRM_PASSWORD_LABEL')"
          :placeholder="$t('LOGIN.USERCONNECT.CONFIRM_PASSWORD_PLACEHOLDER')"
        />
        <NextButton
          lg
          class="w-full"
          :label="$t('LOGIN.USERCONNECT.CHANGE_PASSWORD_SUBMIT')"
          :disabled="loginApi.showLoading"
          :is-loading="loginApi.showLoading"
          @click="submitUcChangePassword"
        />
        <button
          type="button"
          class="w-full text-sm text-center text-n-slate-11 hover:text-n-slate-12"
          @click="cancelUcChangePassword"
        >
          {{ $t('LOGIN.USERCONNECT.OTP_BACK') }}
        </button>
      </div>

      <!-- UC forgot password — step 1: enter username -->
      <div v-else-if="ucForgotStep === 'username'" class="space-y-5">
        <div class="space-y-1">
          <h3 class="text-lg font-medium text-n-slate-12">
            {{ $t('LOGIN.USERCONNECT.FORGOT_PASSWORD_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11">
            {{ $t('LOGIN.USERCONNECT.FORGOT_PASSWORD_SUBTITLE') }}
          </p>
        </div>
        <FormInput
          v-model="ucForgotUsername"
          name="uc_forgot_username"
          type="text"
          :label="$t('LOGIN.USERCONNECT.USERNAME_LABEL')"
          :placeholder="$t('LOGIN.USERCONNECT.USERNAME_PLACEHOLDER')"
        />
        <NextButton
          lg
          class="w-full"
          :label="$t('LOGIN.USERCONNECT.FORGOT_PASSWORD_SUBMIT')"
          :disabled="loginApi.showLoading || !ucForgotUsername"
          :is-loading="loginApi.showLoading"
          @click="submitForgotPasswordUsername"
        />
        <button
          type="button"
          class="w-full text-sm text-center text-n-slate-11 hover:text-n-slate-12"
          @click="cancelForgotPassword"
        >
          {{ $t('LOGIN.USERCONNECT.FORGOT_PASSWORD_BACK') }}
        </button>
      </div>

      <!-- UC forgot password — step 2: enter OTP + new password -->
      <div v-else-if="ucForgotStep === 'reset'" class="space-y-5">
        <div class="space-y-1">
          <h3 class="text-lg font-medium text-n-slate-12">
            {{ $t('LOGIN.USERCONNECT.FORGOT_OTP_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11">
            {{ $t('LOGIN.USERCONNECT.FORGOT_OTP_SUBTITLE') }}
          </p>
        </div>
        <FormInput
          v-model="ucForgotOtp"
          name="uc_forgot_otp"
          type="text"
          :label="$t('LOGIN.USERCONNECT.FORGOT_OTP_LABEL')"
          :placeholder="$t('LOGIN.USERCONNECT.FORGOT_OTP_PLACEHOLDER')"
        />
        <FormInput
          v-model="ucForgotNewPassword"
          type="password"
          name="uc_forgot_new_password"
          :label="$t('LOGIN.USERCONNECT.NEW_PASSWORD_LABEL')"
          :placeholder="$t('LOGIN.USERCONNECT.NEW_PASSWORD_PLACEHOLDER')"
        />
        <FormInput
          v-model="ucForgotConfirmPassword"
          type="password"
          name="uc_forgot_confirm_password"
          :label="$t('LOGIN.USERCONNECT.CONFIRM_PASSWORD_LABEL')"
          :placeholder="$t('LOGIN.USERCONNECT.CONFIRM_PASSWORD_PLACEHOLDER')"
        />
        <NextButton
          lg
          class="w-full"
          :label="$t('LOGIN.USERCONNECT.RESET_PASSWORD_SUBMIT')"
          :disabled="loginApi.showLoading"
          :is-loading="loginApi.showLoading"
          @click="submitForgotPasswordReset"
        />
        <div class="flex justify-between text-sm">
          <button
            type="button"
            class="text-n-slate-11 hover:text-n-slate-12"
            :disabled="loginApi.showLoading"
            @click="resendForgotPasswordOtp"
          >
            {{ $t('LOGIN.USERCONNECT.FORGOT_OTP_RESEND') }}
          </button>
          <button
            type="button"
            class="text-n-slate-11 hover:text-n-slate-12"
            @click="cancelForgotPassword"
          >
            {{ $t('LOGIN.USERCONNECT.FORGOT_PASSWORD_BACK') }}
          </button>
        </div>
      </div>

      <!-- UC forgot password — step 3: success -->
      <div v-else-if="ucForgotStep === 'success'" class="space-y-5 text-center">
        <div
          class="flex items-center justify-center w-12 h-12 mx-auto rounded-full bg-n-brand/10"
        >
          <Icon icon="i-lucide-check" class="size-6 text-n-brand" />
        </div>
        <div class="space-y-1">
          <h3 class="text-lg font-medium text-n-slate-12">
            {{ $t('LOGIN.USERCONNECT.FORGOT_SUCCESS_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11">
            {{ $t('LOGIN.USERCONNECT.FORGOT_SUCCESS_SUBTITLE') }}
          </p>
        </div>
        <NextButton
          lg
          class="w-full"
          :label="$t('LOGIN.SUBMIT')"
          @click="returnToLoginFromForgot"
        />
      </div>

      <div v-else-if="!email">
        <div class="flex flex-col gap-4">
          <GoogleOAuthButton v-if="showGoogleOAuth" />
          <!-- Microsoft SSO redirect button (via UserConnect) -->
          <a
            v-if="showUcSsoLogin"
            :href="ucSsoUrl"
            class="inline-flex justify-center w-full px-4 py-3 items-center bg-n-background dark:bg-n-solid-3 rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2"
          >
            <svg
              class="size-5"
              viewBox="0 0 21 21"
              xmlns="http://www.w3.org/2000/svg"
            >
              <rect x="0" y="0" width="10" height="10" fill="#F25022" />
              <rect x="11" y="0" width="10" height="10" fill="#7FBA00" />
              <rect x="0" y="11" width="10" height="10" fill="#00A4EF" />
              <rect x="11" y="11" width="10" height="10" fill="#FFB900" />
            </svg>
            <span class="ml-2 text-base font-medium text-n-slate-12">
              {{ $t('LOGIN.USERCONNECT.SSO_LABEL') }}
            </span>
          </a>
          <div v-if="showSamlLogin" class="text-center">
            <router-link
              to="/app/login/sso"
              class="inline-flex justify-center w-full px-4 py-3 items-center bg-n-background dark:bg-n-solid-3 rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2"
            >
              <Icon
                icon="i-lucide-lock-keyhole"
                class="size-5 text-n-slate-11"
              />
              <span class="ml-2 text-base font-medium text-n-slate-12">
                {{ $t('LOGIN.SAML.LABEL') }}
              </span>
            </router-link>
          </div>
          <SimpleDivider
            v-if="showGoogleOAuth || showSamlLogin || showUcSsoLogin"
            :label="$t('COMMON.OR')"
            class="uppercase"
          />
        </div>

        <!-- UC credential proxy form -->
        <form
          v-if="showUcCredentialsLogin"
          class="space-y-5"
          @submit.prevent="submitUcCredentials"
        >
          <FormInput
            v-model="ucCredentials.username"
            name="uc_username"
            type="text"
            :label="$t('LOGIN.USERCONNECT.USERNAME_LABEL')"
            :placeholder="$t('LOGIN.USERCONNECT.USERNAME_PLACEHOLDER')"
          />
          <FormInput
            v-model="ucCredentials.password"
            type="password"
            name="uc_password"
            :label="$t('LOGIN.PASSWORD.LABEL')"
            :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
          >
            <p>
              <button
                type="button"
                class="text-sm text-link"
                @click.prevent="openForgotPassword"
              >
                {{ $t('LOGIN.USERCONNECT.FORGOT_PASSWORD') }}
              </button>
            </p>
          </FormInput>
          <NextButton
            lg
            type="submit"
            class="w-full"
            :label="$t('LOGIN.SUBMIT')"
            :disabled="loginApi.showLoading"
            :is-loading="loginApi.showLoading"
          />
        </form>

        <!-- Standard email/password form (shown when credential proxy is off) -->
        <form v-else class="space-y-5" @submit.prevent="submitFormLogin">
          <FormInput
            v-model="credentials.email"
            name="email_address"
            type="text"
            data-testid="email_input"
            :tabindex="1"
            required
            :label="$t('LOGIN.EMAIL.LABEL')"
            :placeholder="$t('LOGIN.EMAIL.PLACEHOLDER')"
            :has-error="v$.credentials.email.$error"
            @input="v$.credentials.email.$touch"
          />
          <FormInput
            v-model="credentials.password"
            type="password"
            name="password"
            data-testid="password_input"
            required
            :tabindex="2"
            :label="$t('LOGIN.PASSWORD.LABEL')"
            :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
            :has-error="v$.credentials.password.$error"
            @input="v$.credentials.password.$touch"
          >
            <p v-if="!globalConfig.disableUserProfileUpdate">
              <router-link
                to="auth/reset/password"
                class="text-sm text-link"
                tabindex="4"
              >
                {{ $t('LOGIN.FORGOT_PASSWORD') }}
              </router-link>
            </p>
          </FormInput>
          <NextButton
            lg
            type="submit"
            data-testid="submit_button"
            class="w-full"
            :tabindex="3"
            :label="$t('LOGIN.SUBMIT')"
            :disabled="loginApi.showLoading"
            :is-loading="loginApi.showLoading"
          />
        </form>
      </div>
      <div v-else class="flex items-center justify-center">
        <Spinner color-scheme="primary" size="" />
      </div>
    </section>
  </main>
</template>
