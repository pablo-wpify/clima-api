require "rails_helper"
require "net/http"

RSpec.describe "GET /api/v1/weather", type: :request do
  let(:provider_url) { "https://api.open-meteo.com/v1/forecast" }
  let(:provider_query) do
    {
      "latitude" => "-37.32",
      "longitude" => "-59.13",
      "current" => "temperature_2m,wind_speed_10m",
      "temperature_unit" => "celsius",
      "wind_speed_unit" => "kmh",
      "timezone" => "GMT"
    }
  end
  # Illustrative provider payload, based on the real query of 2026-10-31.
  let(:provider_payload) do
    {
      "latitude" => -37.2935,
      "longitude" => -59.08487,
      "generationtime_ms" => 0.11,
      "utc_offset_seconds" => 0,
      "timezone" => "GMT",
      "timezone_abbreviation" => "GMT",
      "elevation" => 186.0,
      "current_units" => { "time" => "iso8601", "interval" => "seconds", "temperature_2m" => "°C", "wind_speed_10m" => "km/h" },
      "current" => { "time" => "2026-10-31T15:00", "interval" => 900, "temperature_2m" => 17.6, "wind_speed_10m" => 8.8 }
    }
  end
  let(:valid_params) { { latitude: "-37.32", longitude: "-59.13" } }

  def stub_provider(status: 200, body: provider_payload.to_json)
    stub_request(:get, provider_url).with(query: provider_query).to_return(status: status, body: body)
  end

  def json
    JSON.parse(response.body)
  end

  def expect_error(status, code)
    expect(response).to have_http_status(status)
    expect(json).to eq("error" => json["error"].slice("code", "message").merge("code" => code))
    expect(json["error"]["message"]).to be_a(String)
  end

  describe "success" do
    it "returns the current weather contract" do
      stub = stub_provider

      get "/api/v1/weather", params: valid_params

      expect(response).to have_http_status(200)
      expect(json).to eq(
        "requested_coordinates" => { "latitude" => -37.32, "longitude" => -59.13 },
        "model_coordinates" => { "latitude" => -37.2935, "longitude" => -59.08487 },
        "temperature_celsius" => 17.6,
        "wind_speed_kmh" => 8.8,
        "valid_at" => "2026-10-31T15:00:00Z",
        "source" => {
          "provider" => "Open-Meteo",
          "data_type" => "model",
          "attribution" => "Weather data by Open-Meteo.com",
          "url" => "https://open-meteo.com/",
          "license" => "CC BY 4.0",
          "license_url" => "https://creativecommons.org/licenses/by/4.0/"
        }
      )
      expect(stub).to have_been_requested.once
    end

    it "does not use observation wording in the response" do
      stub_provider

      get "/api/v1/weather", params: valid_params

      expect(response).to have_http_status(200)
      expect(json["source"]["data_type"]).to eq("model")
      expect(response.body).not_to match(/observ/i)
    end

    it "ignores unknown parameters and does not forward them" do
      stub = stub_provider

      get "/api/v1/weather", params: valid_params.merge(current: "precipitation", url: "https://example.com")

      expect(response).to have_http_status(200)
      expect(stub).to have_been_requested.once
    end

    it "uses the last value of a repeated key, as Rails does" do
      stub = stub_provider

      get "/api/v1/weather?latitude=10&latitude=-37.32&longitude=-59.13"

      expect(response).to have_http_status(200)
      expect(json["requested_coordinates"]).to eq("latitude" => -37.32, "longitude" => -59.13)
      expect(stub).to have_been_requested.once
    end
  end

  describe "invalid input" do
    it "returns 400 with every invalid field and makes no provider request" do
      get "/api/v1/weather", params: { longitude: "abc" }

      expect(response).to have_http_status(400)
      expect(json).to eq(
        "error" => {
          "code" => "invalid_parameters",
          "message" => "Invalid coordinates",
          "details" => [
            { "field" => "latitude", "issue" => "missing" },
            { "field" => "longitude", "issue" => "invalid_format" }
          ]
        }
      )
      expect(a_request(:get, /open-meteo/)).not_to have_been_made
    end

    it "rejects out-of-range, blank and structured values without calling the provider" do
      [
        { latitude: "91", longitude: "0" },
        { latitude: "", longitude: "0" },
        { latitude: [ "1" ], longitude: "0" },
        { latitude: { "a" => "1" }, longitude: "0" },
        { latitude: "1e2", longitude: "0" }
      ].each do |params|
        get "/api/v1/weather", params: params

        expect(response).to have_http_status(400)
        expect(json.dig("error", "code")).to eq("invalid_parameters")
      end
      expect(a_request(:get, /open-meteo/)).not_to have_been_made
    end
  end

  describe "provider failures" do
    it "returns 504 on a read timeout" do
      stub_request(:get, provider_url).with(query: provider_query).to_raise(Net::ReadTimeout)

      get "/api/v1/weather", params: valid_params

      expect_error(504, "provider_timeout")
    end

    it "returns 504 on a connection timeout" do
      stub_request(:get, provider_url).with(query: provider_query).to_raise(Net::OpenTimeout)

      get "/api/v1/weather", params: valid_params

      expect_error(504, "provider_timeout")
    end

    it "returns 503 provider_rate_limited on HTTP 429" do
      stub_provider(status: 429, body: "")

      get "/api/v1/weather", params: valid_params

      expect_error(503, "provider_rate_limited")
    end

    it "returns 502 provider_unavailable on a failed connection, without the exception message" do
      stub_request(:get, provider_url).with(query: provider_query).to_raise(Errno::ECONNREFUSED.new("secret socket detail"))

      get "/api/v1/weather", params: valid_params

      expect_error(502, "provider_unavailable")
      expect(response.body).not_to include("secret socket detail")
      expect(response.body).not_to include("ECONNREFUSED")
    end

    it "returns 502 provider_error on provider HTTP errors and redirects, without the provider body" do
      [ 400, 500, 301 ].each do |status|
        stub_provider(status: status, body: { error: true, reason: "Latitude must be in range" }.to_json)

        get "/api/v1/weather", params: valid_params

        expect_error(502, "provider_error")
        expect(response.body).not_to include("Latitude must be in range")
      end
    end

    it "returns 502 provider_invalid_response for a body that is not JSON" do
      stub_provider(body: "<html>oops</html>")

      get "/api/v1/weather", params: valid_params

      expect_error(502, "provider_invalid_response")
    end

    it "returns 502, not 500, when current is null" do
      stub_provider(body: provider_payload.merge("current" => nil).to_json)

      get "/api/v1/weather", params: valid_params

      expect_error(502, "provider_invalid_response")
    end

    it "returns 502, not 500, for an impossible date" do
      payload = provider_payload.merge("current" => provider_payload["current"].merge("time" => "2026-02-30T15:00"))
      stub_provider(body: payload.to_json)

      get "/api/v1/weather", params: valid_params

      expect_error(502, "provider_invalid_response")
      expect(response.body).not_to include("valid_at")
    end

    it "returns 502 without partial data when a field is null" do
      payload = provider_payload.merge("current" => provider_payload["current"].merge("temperature_2m" => nil))
      stub_provider(body: payload.to_json)

      get "/api/v1/weather", params: valid_params

      expect_error(502, "provider_invalid_response")
      expect(json.keys).to eq([ "error" ])
    end
  end
end
