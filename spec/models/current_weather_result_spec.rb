require "rails_helper"

RSpec.describe CurrentWeatherResult do
  let(:weather) do
    CurrentWeather.new(
      requested_coordinates: Coordinates.new(latitude: -37.32, longitude: -59.13),
      model_coordinates: Coordinates.new(latitude: -37.2935, longitude: -59.08487),
      temperature_celsius: 17.6,
      wind_speed_kmh: 8.8,
      valid_at: Time.utc(2026, 10, 31, 15, 0)
    )
  end

  describe "success" do
    it "holds the weather and no error" do
      result = described_class.success(weather)

      expect(result.success?).to be(true)
      expect(result.data).to equal(weather)
      expect([ result.error_code, result.error_message ]).to eq([ nil, nil ])
    end
  end

  describe "failure" do
    it "holds a known code and a message, and no data" do
      result = described_class.failure(code: "provider_timeout", message: "Weather provider timed out")

      expect(result.success?).to be(false)
      expect(result.data).to be_nil
      expect([ result.error_code, result.error_message ]).to eq([ "provider_timeout", "Weather provider timed out" ])
    end

    it "accepts each of the five public provider codes" do
      %w[provider_timeout provider_rate_limited provider_unavailable provider_error provider_invalid_response].each do |code|
        expect(described_class.failure(code: code, message: "x").error_code).to eq(code)
      end
    end
  end

  describe "invalid combinations" do
    it "rejects a success with an error code or message" do
      expect { described_class.new(data: weather, error_code: "provider_timeout", error_message: nil) }.to raise_error(ArgumentError)
      expect { described_class.new(data: weather, error_code: nil, error_message: "x") }.to raise_error(ArgumentError)
    end

    it "rejects a success without data or with an object that is not CurrentWeather" do
      expect { described_class.new(data: nil, error_code: nil, error_message: nil) }.to raise_error(ArgumentError)
      expect { described_class.success({ temperature_celsius: 17.6 }) }.to raise_error(ArgumentError)
    end

    it "rejects a failure with data" do
      expect { described_class.new(data: weather, error_code: "provider_error", error_message: "x") }.to raise_error(ArgumentError)
    end

    it "rejects an unknown code, including the input validation code and symbols" do
      [ "unknown", "invalid_parameters", :provider_timeout ].each do |code|
        expect { described_class.failure(code: code, message: "x") }.to raise_error(ArgumentError)
      end
    end

    it "rejects a missing, empty or blank message" do
      [ nil, "", "   ", :timeout ].each do |message|
        expect { described_class.failure(code: "provider_error", message: message) }.to raise_error(ArgumentError)
      end
    end

    it "validates positional construction and #with in the same way" do
      expect { described_class.new(weather, "provider_error", "x") }.to raise_error(ArgumentError)

      success = described_class.success(weather)
      expect { success.with(error_code: "provider_error") }.to raise_error(ArgumentError)
    end
  end

  it "does not store a separate success flag" do
    expect(described_class.members).to eq(%i[data error_code error_message])
  end
end
