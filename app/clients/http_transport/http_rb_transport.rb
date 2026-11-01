require "openssl"

module HttpTransport
  # Transport backed by HTTP.rb. HTTP.rb has no timeouts unless configured, does
  # not follow redirects without `follow` and does not retry without
  # `retriable`; neither option is used. It reads the body lazily, so the body
  # is read here, inside the error handling, before returning. The block form
  # of `get` closes the connection when the block ends, also when reading the
  # body fails (without it, a read timeout in the body left the socket in
  # CLOSE-WAIT). Only expected communication failures are translated; anything
  # else propagates with its own class.
  class HttpRbTransport
    attr_reader :open_timeout, :read_timeout

    def initialize(open_timeout:, read_timeout:)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def get(url, params:, headers:)
      ::HTTP.timeout(connect: open_timeout, read: read_timeout).headers(headers).get(url, params: params) do |response|
        Response.new(status: response.code, body: response.to_s)
      end
    rescue ::HTTP::TimeoutError
      # Includes HTTP::ConnectTimeoutError and the TLS handshake timeout.
      raise Timeout
    rescue ::HTTP::ConnectionError, OpenSSL::SSL::SSLError
      raise ConnectionFailed
    end
  end
end
