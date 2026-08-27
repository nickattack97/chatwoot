module SafeFetch
  # SSRF protection (ssrf_filter) resolves every target hostname and refuses any that has
  # no public IP. That is the correct default, but it also makes it impossible for Chatwoot
  # to call a service on our own internal network — specifically the WA-Bot-Engine webhook
  # receiver, which lives on an RFC1918 address and cannot be reached over the public
  # hostname either (NAT hairpinning is not permitted at the edge).
  #
  # Rather than disabling the check, an operator names the exact internal hosts that may be
  # reached. This is an allow-list, not a bypass — OWASP A10 prescribes allow-listing
  # destination hosts for server-initiated outbound requests. Anything not named here still
  # goes through ssrf_filter unchanged.
  #
  # Configure with a comma-separated list of "host" or "host:port" entries:
  #
  #   SAFE_FETCH_ALLOWED_INTERNAL_HOSTS=192.168.3.150:5005
  #
  # Prefer host:port over a bare host so the allowance is as narrow as possible.
  module AllowedInternalHosts
    ENV_KEY = 'SAFE_FETCH_ALLOWED_INTERNAL_HOSTS'.freeze

    def self.entries
      ENV.fetch(ENV_KEY, '').split(',').filter_map { |entry| entry.strip.downcase.presence }
    end

    def self.allow?(uri)
      return false if uri.nil? || uri.host.blank?

      host = uri.host.downcase
      entries.any? { |entry| matches?(entry, host, uri.port) }
    end

    def self.matches?(entry, host, port)
      entry_host, entry_port = entry.split(':', 2)
      return false unless entry_host == host

      # A bare host allows any port; host:port pins it.
      entry_port.blank? || entry_port.to_i == port
    end

    private_class_method :matches?
  end
end
