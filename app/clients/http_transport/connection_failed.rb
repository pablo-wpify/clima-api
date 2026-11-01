module HttpTransport
  # The connection could not be established or was broken: refused, name
  # resolution, reset or TLS failure.
  class ConnectionFailed < Error
    def initialize(msg = "HTTP transport connection failed") = super
  end
end
