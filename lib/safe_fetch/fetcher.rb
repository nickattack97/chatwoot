class SafeFetch::Fetcher
  def initialize(options)
    @options = options
  end

  def fetch
    with_tempfile do |tempfile|
      response = stream_response(tempfile)
      raise SafeFetch::HttpError, "#{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

      tempfile.rewind
      yield SafeFetch::Result.new(
        tempfile: tempfile,
        filename: options.filename,
        content_type: normalized_content_type(response['content-type'])
      )
    end
  end

  private

  attr_reader :options

  def with_tempfile
    tempfile = Tempfile.new('chatwoot-safe-fetch', binmode: true)
    yield tempfile
  ensure
    tempfile&.close!
  end

  def stream_response(tempfile)
    response = nil
    bytes_written = 0

    handler = lambda do |res|
      response = res
      next unless res.is_a?(Net::HTTPSuccess)

      validate_content_type!(res['content-type'])
      bytes_written = write_response_body(res, tempfile, bytes_written)
    end

    if SafeFetch::AllowedInternalHosts.allow?(options.uri)
      request_allowed_internal_host(&handler)
    else
      SsrfFilter.public_send(options.method, options.url, **options.request_options, &handler)
    end

    response
  end

  # Bypasses ssrf_filter for hosts an operator has explicitly allow-listed. See
  # SafeFetch::AllowedInternalHosts for why this exists and how narrow it is.
  def request_allowed_internal_host
    uri = options.uri
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = uri.scheme == 'https'
    http.open_timeout = options.open_timeout
    http.read_timeout = options.read_timeout

    http.start { |conn| conn.request(build_internal_request(uri)) { |res| yield res } }
  end

  def build_internal_request(uri)
    request = Net::HTTP.const_get(options.method.to_s.capitalize).new(uri)
    options.headers&.each { |key, value| request[key] = value }
    request.body = options.body if options.body.present?
    options.request_options[:request_proc]&.call(request)
    request
  end

  def validate_content_type!(content_type)
    return unless options.validate_content_type?
    return if allowed_content_type?(content_type)

    raise SafeFetch::UnsupportedContentTypeError, "content-type not allowed: #{content_type}"
  end

  def write_response_body(response, tempfile, bytes_written)
    response.read_body do |chunk|
      bytes_written += chunk.bytesize
      raise SafeFetch::FileTooLargeError, "exceeded #{options.effective_max_bytes} bytes" if bytes_written > options.effective_max_bytes

      tempfile.write(chunk)
    end

    bytes_written
  end

  def allowed_content_type?(value)
    mime = normalized_content_type(value)
    return false if mime.blank?

    options.allowed_content_type_prefixes.any? { |prefix| mime.start_with?(prefix) } ||
      options.allowed_content_types.include?(mime)
  end

  def normalized_content_type(value)
    value.to_s.split(';').first&.strip&.downcase
  end
end
