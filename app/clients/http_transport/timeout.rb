module HttpTransport
  # Connecting, the TLS handshake or a read took longer than its configured limit.
  class Timeout < Error
    def initialize(msg = "HTTP transport timed out") = super
  end
end
