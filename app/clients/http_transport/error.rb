module HttpTransport
  # Base class for the expected communication failures of a transport. Messages
  # are fixed on purpose: the library exception stays only as the Ruby `cause`.
  # Unexpected errors are not wrapped: they propagate with their own class.
  class Error < StandardError
  end
end
