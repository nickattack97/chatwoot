# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy
# For further information see the following documentation
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy

# CBZ: emitted as Content-Security-Policy-Report-Only (see below) rather than
# enforced — Chatwoot embeds a widget iframe (WidgetsController sets its own
# enforced frame-ancestors header per-inbox, on a separate header so this
# doesn't conflict with it), Vite assets, and ActionCable, so we want to see
# violation reports before flipping this to enforced. Addresses CBZ HelpEngine
# Security Assessment finding #3 (missing CSP).
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :data
  policy.img_src     :self, :https, :data, :blob
  policy.object_src  :none
  policy.script_src  :self
  # Allow @vite/client to hot reload javascript changes in development
  policy.script_src *policy.script_src, :unsafe_eval, "http://#{ViteRuby.config.host_with_port}" if Rails.env.development?
  policy.style_src   :self, :unsafe_inline
  # Allow @vite/client to hot reload style changes in development
  policy.style_src *policy.style_src, "http://#{ViteRuby.config.host_with_port}" if Rails.env.development?
  policy.connect_src :self, :https, :wss
  # Allow @vite/client to hot reload changes in development
  policy.connect_src *policy.connect_src, "ws://#{ViteRuby.config.host_with_port}" if Rails.env.development?
  policy.base_uri    :self
  policy.frame_ancestors :self
end

# Report CSP violations to a specified URI
# For further information see the following documentation:
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy-Report-Only
Rails.application.config.content_security_policy_report_only = true
