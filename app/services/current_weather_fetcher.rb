require "date"

# Asks the provider client for the current weather and turns its JSON payload
# into a CurrentWeather. Every check happens before a value is read, so a
# malformed payload raises OpenMeteo::Error::InvalidResponse and never a
# NoMethodError. It rescues nothing: programming errors stay visible.
class CurrentWeatherFetcher < ApplicationService
  EXPECTED_UNITS = { "temperature_2m" => "°C", "wind_speed_10m" => "km/h", "time" => "iso8601" }.freeze
  TIME_FORMAT = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})\z/

  def initialize(coordinates:, client: OpenMeteo::Client.new)
    @coordinates = coordinates
    @client = client
  end

  def call
    payload = @client.current(@coordinates)
    current, units = structure(payload)

    invalid! unless payload["utc_offset_seconds"] == 0
    invalid! unless EXPECTED_UNITS.all? { |key, unit| units[key] == unit }

    CurrentWeather.new(
      requested_coordinates: @coordinates,
      model_coordinates: model_coordinates(payload),
      temperature_celsius: number(current["temperature_2m"]),
      wind_speed_kmh: number(current["wind_speed_10m"]),
      valid_at: utc_time(current["time"])
    )
  end

  private

  def structure(payload)
    invalid! unless payload.is_a?(Hash)

    current = payload["current"]
    units = payload["current_units"]
    invalid! unless current.is_a?(Hash) && units.is_a?(Hash)

    [ current, units ]
  end

  def model_coordinates(payload)
    latitude = number(payload["latitude"])
    longitude = number(payload["longitude"])
    invalid! unless latitude.between?(-90, 90) && longitude.between?(-180, 180)

    Coordinates.new(latitude: latitude.to_f, longitude: longitude.to_f)
  end

  def number(value)
    invalid! unless (value.is_a?(Integer) || value.is_a?(Float)) && value.finite?

    value
  end

  # Strict: Time.utc would normalize 2026-02-30 to 2026-03-02 and 24:00 to the
  # next day, so every component is validated before building the Time.
  def utc_time(value)
    match = value.is_a?(String) && TIME_FORMAT.match(value)
    invalid! unless match

    year, month, day, hour, minute = match.captures.map(&:to_i)
    invalid! unless month.between?(1, 12) && Date.valid_date?(year, month, day)
    invalid! unless hour.between?(0, 23) && minute.between?(0, 59)

    time = Time.utc(year, month, day, hour, minute)
    invalid! unless time.strftime("%Y-%m-%dT%H:%M") == value

    time
  end

  def invalid!
    raise OpenMeteo::Error::InvalidResponse
  end
end
