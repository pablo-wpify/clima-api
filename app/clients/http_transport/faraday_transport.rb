require "net/http"

module HttpTransport
  # Transport backed by Faraday and faraday-net_http, without middleware: it
  # does not follow redirects and does not retry (faraday-net_http sets
  # Net::HTTP#max_retries to 0). Only expected communication failures are
  # translated; anything else propagates with its own class.
  class FaradayTransport
    attr_reader :open_timeout, :read_timeout

    def initialize(open_timeout:, read_timeout:)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @connection = Faraday.new(request: { open_timeout: open_timeout, read_timeout: read_timeout })
    end

    def get(url, params:, headers:)
      response = @connection.get(url, params, headers)

      Response.new(status: response.status, body: response.body.to_s)
    rescue Faraday::TimeoutError
      raise Timeout
    rescue Faraday::ConnectionFailed => e
      # faraday-net_http wraps Net::OpenTimeout (connection or TLS handshake) in ConnectionFailed.
      raise(e.wrapped_exception.is_a?(Net::OpenTimeout) ? Timeout : ConnectionFailed)
    rescue Faraday::SSLError
      raise ConnectionFailed
    end
  end
end
