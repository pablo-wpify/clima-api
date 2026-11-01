require "json"

module OpenMeteo
  # Knows Open-Meteo's rules: the fixed URL, the query built here, how to read
  # the HTTP status and that the body must be a JSON object. It talks to the
  # provider through an injected HttpTransport and translates the transport's
  # expected failures and the provider's statuses into OpenMeteo::Error
  # subclasses. It knows nothing about the HTTP library behind the transport.
  class Client
    URL = "https://api.open-meteo.com/v1/forecast"
    CURRENT_VARIABLES = "temperature_2m,wind_speed_10m"
    HEADERS = { "Accept" => "application/json" }.freeze
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 5

    attr_reader :transport

    # The single place where the production transport is chosen.
    def self.default_transport
      HttpTransport::FaradayTransport.new(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
    end

    def initialize(transport: self.class.default_transport)
      @transport = transport
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
      transport.get(URL, params: query(coordinates), headers: HEADERS)
    rescue HttpTransport::Timeout
      raise Error::Timeout
    rescue HttpTransport::ConnectionFailed
      raise Error::Unavailable
    end

    def query(coordinates)
      {
        "latitude" => coordinates.latitude.to_s,
        "longitude" => coordinates.longitude.to_s,
        "current" => CURRENT_VARIABLES,
        "temperature_unit" => "celsius",
        "wind_speed_unit" => "kmh",
        "timezone" => "GMT"
      }
    end

    def parse(body)
      payload = JSON.parse(body)
      raise Error::InvalidResponse unless payload.is_a?(Hash)

      payload
    rescue JSON::ParserError
      raise Error::InvalidResponse
    end
  end
end
