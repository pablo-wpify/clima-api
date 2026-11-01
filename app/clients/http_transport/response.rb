module HttpTransport
  # What every transport returns: the HTTP status as an Integer and the body as
  # a String that has already been read completely. Any status, including 3xx,
  # 4xx and 5xx, is a response; interpreting it is up to the caller.
  Response = Data.define(:status, :body)

  class Response
    STATUS_RANGE = 100..599

    def initialize(status:, body:)
      raise ArgumentError, "status must be an Integer between 100 and 599" unless status.is_a?(Integer) && STATUS_RANGE.cover?(status)
      raise ArgumentError, "body must be a String" unless body.is_a?(String)

      super
    end
  end
end
