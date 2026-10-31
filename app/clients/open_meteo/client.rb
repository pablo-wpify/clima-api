require "json"
require "net/http"

module OpenMeteo
  # The only object that knows about HTTP and Faraday. It sends one GET to a
  # fixed Open-Meteo URL with parameters built here, and translates transport
  # failures and HTTP statuses into OpenMeteo::Error subclasses.
  class Client
    BASE_URL = "https://api.open-meteo.com"
    PATH = "/v1/forecast"
    CURRENT_VARIABLES = "temperature_2m,wind_speed_10m"
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 5

    attr_reader :connection

    def initialize(connection: self.class.default_connection)
      @connection = connection
    end

    def self.default_connection
      Faraday.new(
        url: BASE_URL,
        request: { open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT },
        headers: { "Accept" => "application/json" }
      )
    end

    # Returns the provider JSON object as a Hash.
    def current(coordinates)
      response = request(coordinates)

      case response.status
      when 200..299 then parse(response.body)
      when 429 then raise Error::RateLimited
      else raise Error::HttpError
      end
    end

    private

    def request(coordinates)
      connection.get(PATH, query(coordinates))
    rescue Faraday::TimeoutError
      # TimeoutError inherits from ServerError, so it is rescued first.
      raise Error::Timeout
    rescue Faraday::ConnectionFailed => e
      # faraday-net_http wraps Net::OpenTimeout (connect timeout) in ConnectionFailed.
      raise(e.wrapped_exception.is_a?(Net::OpenTimeout) ? Error::Timeout : Error::Unavailable)
    rescue Faraday::SSLError, Faraday::Error
      raise Error::Unavailable
    end

    def query(coordinates)
      {
        latitude: coordinates.latitude.to_s,
        longitude: coordinates.longitude.to_s,
        current: CURRENT_VARIABLES,
        temperature_unit: "celsius",
        wind_speed_unit: "kmh",
        timezone: "GMT"
      }
    end

    def parse(body)
      payload = JSON.parse(body.to_s)
      raise Error::InvalidResponse unless payload.is_a?(Hash)

      payload
    rescue JSON::ParserError
      raise Error::InvalidResponse
    end
  end
end
