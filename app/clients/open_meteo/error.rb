module OpenMeteo
  # Base class for every failure talking to Open-Meteo. Messages are fixed on
  # purpose: they never include the provider body or an original exception
  # message, which stays only as the Ruby `cause`.
  class Error < StandardError
    class Timeout < Error
      def initialize(msg = "Weather provider timed out") = super
    end

    class RateLimited < Error
      def initialize(msg = "Weather provider rate limit reached") = super
    end

    class Unavailable < Error
      def initialize(msg = "Weather provider unavailable") = super
    end

    class HttpError < Error
      def initialize(msg = "Weather provider returned an error") = super
    end

    class InvalidResponse < Error
      def initialize(msg = "Weather provider returned an invalid response") = super
    end
  end
end
