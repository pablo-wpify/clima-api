require "rails_helper"
require "net/http"
require "openssl"

RSpec.describe OpenMeteo::Client do
  subject(:client) { described_class.new }

  let(:coordinates) { Coordinates.new(latitude: -37.32, longitude: -59.13) }
  let(:url) { "https://api.open-meteo.com/v1/forecast" }
  let(:expected_query) do
    {
      "latitude" => "-37.32",
      "longitude" => "-59.13",
      "current" => "temperature_2m,wind_speed_10m",
      "temperature_unit" => "celsius",
      "wind_speed_unit" => "kmh",
      "timezone" => "GMT"
    }
  end
  let(:provider_body) { { "latitude" => -37.2935, "current" => { "temperature_2m" => 17.6 } } }

  def stub_provider
    stub_request(:get, url).with(query: expected_query)
  end

  def expect_error(error_class)
    expect { client.current(coordinates) }.to raise_error(error_class) do |error|
      yield error if block_given?
    end
  end

  describe "#current" do
    it "sends exactly the expected query keys and values and returns the parsed object" do
      stub = stub_provider.to_return(status: 200, body: provider_body.to_json)

      expect(client.current(coordinates)).to eq(provider_body)
      expect(stub).to have_been_requested.once
    end

    it "does not match a request with an extra or different parameter" do
      stub_request(:get, url).with(query: expected_query.merge("extra" => "1")).to_return(status: 200, body: "{}")

      expect { client.current(coordinates) }.to raise_error(WebMock::NetConnectNotAllowedError)
    end

    it "raises InvalidResponse when the body is not JSON" do
      stub_provider.to_return(status: 200, body: "<html>oops</html>")

      expect_error(OpenMeteo::Error::InvalidResponse)
    end

    it "raises InvalidResponse when the JSON body is not an object" do
      [ "[]", "\"ok\"" ].each do |body|
        stub_provider.to_return(status: 200, body: body)

        expect_error(OpenMeteo::Error::InvalidResponse)
      end
    end

    it "does not follow redirects and raises HttpError" do
      stub = stub_provider.to_return(status: 301, headers: { "Location" => "https://example.com/elsewhere" })

      expect_error(OpenMeteo::Error::HttpError)
      expect(stub).to have_been_requested.once
      expect(a_request(:get, /example\.com/)).not_to have_been_made
    end

    it "raises HttpError for 400 and 500 without exposing the provider body" do
      [ 400, 500 ].each do |status|
        stub_provider.to_return(status: status, body: { error: true, reason: "secret provider reason" }.to_json)

        expect_error(OpenMeteo::Error::HttpError) do |error|
          expect(error.message).not_to include("secret provider reason")
        end
      end
    end

    it "raises RateLimited for 429" do
      stub_provider.to_return(status: 429)

      expect_error(OpenMeteo::Error::RateLimited)
    end

    it "translates a read timeout from the real adapter into Timeout" do
      stub_provider.to_raise(Net::ReadTimeout)

      expect_error(OpenMeteo::Error::Timeout)
    end

    it "translates a connection timeout (Net::OpenTimeout, wrapped as ConnectionFailed) into Timeout" do
      stub_provider.to_raise(Net::OpenTimeout)

      expect_error(OpenMeteo::Error::Timeout)
    end

    it "translates a refused connection into Unavailable without exposing the original message" do
      stub_provider.to_raise(Errno::ECONNREFUSED.new("secret socket detail"))

      expect_error(OpenMeteo::Error::Unavailable) do |error|
        expect(error.message).not_to include("secret socket detail")
      end
    end

    it "translates a TLS error into Unavailable" do
      stub_provider.to_raise(OpenSSL::SSL::SSLError)

      expect_error(OpenMeteo::Error::Unavailable)
    end

    it "makes a single request even when it fails (no retries)" do
      stub = stub_provider.to_return(status: 500)

      expect_error(OpenMeteo::Error::HttpError)
      expect(stub).to have_been_requested.once
    end
  end

  describe "default connection" do
    it "uses the documented timeouts and no generic timeout" do
      options = described_class.new.connection.options

      expect(options.open_timeout).to eq(2)
      expect(options.read_timeout).to eq(5)
      expect(options.timeout).to be_nil
    end
  end
end
