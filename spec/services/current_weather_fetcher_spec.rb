require "rails_helper"

RSpec.describe CurrentWeatherFetcher do
  let(:coordinates) { Coordinates.new(latitude: -37.32, longitude: -59.13) }

  def valid_payload
    {
      "latitude" => -37.2935,
      "longitude" => -59.08487,
      "utc_offset_seconds" => 0,
      "timezone" => "GMT",
      "current_units" => { "time" => "iso8601", "interval" => "seconds", "temperature_2m" => "°C", "wind_speed_10m" => "km/h" },
      "current" => { "time" => "2026-10-31T15:00", "interval" => 900, "temperature_2m" => 17.6, "wind_speed_10m" => 8.8 }
    }
  end

  def fetch(payload)
    client = instance_double(OpenMeteo::Client, current: payload)
    described_class.call(coordinates: coordinates, client: client)
  end

  def expect_invalid(payload)
    expect { fetch(payload) }.to raise_error(OpenMeteo::Error::InvalidResponse)
  end

  it "builds CurrentWeather with requested and model coordinates and valid_at in UTC" do
    weather = fetch(valid_payload)

    expect(weather).to be_a(CurrentWeather)
    expect(weather.requested_coordinates).to eq(coordinates)
    expect(weather.model_coordinates).to eq(Coordinates.new(latitude: -37.2935, longitude: -59.08487))
    expect(weather.temperature_celsius).to eq(17.6)
    expect(weather.wind_speed_kmh).to eq(8.8)
    expect(weather.valid_at).to eq(Time.utc(2026, 10, 31, 15, 0))
    expect(weather.valid_at.utc.iso8601).to eq("2026-10-31T15:00:00Z")
  end

  it "accepts integer values" do
    payload = valid_payload.merge("current" => valid_payload["current"].merge("temperature_2m" => 17, "wind_speed_10m" => 0))

    expect(fetch(payload).temperature_celsius).to eq(17)
  end

  describe "payload structure" do
    it "rejects a payload that is not an object" do
      [ nil, [], "x", true ].each { |payload| expect_invalid(payload) }
    end

    it "rejects current and current_units that are missing or not objects" do
      %w[current current_units].each do |key|
        expect_invalid(valid_payload.except(key))

        [ nil, [], "x", true, 1 ].each do |value|
          expect_invalid(valid_payload.merge(key => value))
        end
      end
    end
  end

  describe "strict date" do
    it "rejects impossible dates without normalizing them" do
      %w[2026-02-30T15:00 2026-13-01T15:00 2026-10-31T24:00 2026-10-31T15:60].each do |time|
        expect_invalid(valid_payload.merge("current" => valid_payload["current"].merge("time" => time)))
      end
    end

    it "rejects other formats and non-string times" do
      [ "2026-10-31T15:00:00", "2026-10-31T15:00Z", "2026-10-31 15:00", "31/10/2026 15:00", "", 1_793_458_800, nil ].each do |time|
        expect_invalid(valid_payload.merge("current" => valid_payload["current"].merge("time" => time)))
      end
    end
  end

  describe "fields, types and units" do
    it "rejects missing or null values" do
      %w[temperature_2m wind_speed_10m time].each do |key|
        expect_invalid(valid_payload.merge("current" => valid_payload["current"].except(key)))
        expect_invalid(valid_payload.merge("current" => valid_payload["current"].merge(key => nil)))
      end
    end

    it "rejects numbers sent as text or booleans" do
      [ "17.6", true, false ].each do |value|
        expect_invalid(valid_payload.merge("current" => valid_payload["current"].merge("temperature_2m" => value)))
        expect_invalid(valid_payload.merge("current" => valid_payload["current"].merge("wind_speed_10m" => value)))
      end
    end

    it "rejects unexpected units" do
      expect_invalid(valid_payload.merge("current_units" => valid_payload["current_units"].merge("temperature_2m" => "°F")))
      expect_invalid(valid_payload.merge("current_units" => valid_payload["current_units"].merge("wind_speed_10m" => "m/s")))
      expect_invalid(valid_payload.merge("current_units" => valid_payload["current_units"].merge("time" => "unixtime")))
    end

    it "rejects a non-UTC offset" do
      expect_invalid(valid_payload.merge("utc_offset_seconds" => -10_800))
      expect_invalid(valid_payload.except("utc_offset_seconds"))
    end

    it "rejects model coordinates that are missing, not numeric or out of range" do
      expect_invalid(valid_payload.except("latitude"))
      expect_invalid(valid_payload.merge("longitude" => "-59.08"))
      expect_invalid(valid_payload.merge("latitude" => 91))
      expect_invalid(valid_payload.merge("longitude" => -180.5))
    end
  end
end
