require "rails_helper"

RSpec.describe OpenMeteo::Client do
  # A fake transport: no WebMock and no HTTP library involved.
  def fake_transport(response: nil, error: nil)
    Class.new do
      attr_reader :calls

      define_method(:initialize) { @calls = [] }

      define_method(:get) do |url, params:, headers:|
        @calls << { url: url, params: params, headers: headers }
        raise error if error

        response
      end
    end.new
  end

  let(:coordinates) { Coordinates.new(latitude: -37.32, longitude: -59.13) }
  let(:provider_body) { { "latitude" => -37.2935, "current" => { "temperature_2m" => 17.6 } } }

  def respond(status, body = "")
    fake_transport(response: HttpTransport::Response.new(status: status, body: body))
  end

  def current_with(transport)
    described_class.new(transport: transport).current(coordinates)
  end

  def expect_error(transport, error_class)
    expect { current_with(transport) }.to raise_error(error_class) do |error|
      yield error if block_given?
    end
  end

  describe "#current" do
    it "asks the transport once for the fixed URL with exactly the expected query and Accept header" do
      transport = respond(200, provider_body.to_json)

      expect(current_with(transport)).to eq(provider_body)
      expect(transport.calls).to eq([
        {
          url: "https://api.open-meteo.com/v1/forecast",
          params: {
            "latitude" => "-37.32",
            "longitude" => "-59.13",
            "current" => "temperature_2m,wind_speed_10m",
            "temperature_unit" => "celsius",
            "wind_speed_unit" => "kmh",
            "timezone" => "GMT"
          },
          headers: { "Accept" => "application/json" }
        }
      ])
    end

    it "accepts any 2xx status with a JSON object" do
      expect(current_with(respond(203, provider_body.to_json))).to eq(provider_body)
    end

    it "raises InvalidResponse when the body is not JSON" do
      expect_error(respond(200, "<html>oops</html>"), OpenMeteo::Error::InvalidResponse)
    end

    it "raises InvalidResponse when the JSON body is not an object" do
      [ "[]", "\"ok\"" ].each do |body|
        expect_error(respond(200, body), OpenMeteo::Error::InvalidResponse)
      end
    end

    it "raises HttpError for 301, 400 and 500 without exposing the provider body" do
      [ 301, 400, 500 ].each do |status|
        transport = respond(status, { error: true, reason: "secret provider reason" }.to_json)

        expect_error(transport, OpenMeteo::Error::HttpError) do |error|
          expect(error.message).to eq("Weather provider returned an error")
        end
        expect(transport.calls.size).to eq(1)
      end
    end

    it "raises RateLimited for 429" do
      expect_error(respond(429), OpenMeteo::Error::RateLimited)
    end

    it "translates a transport Timeout into Timeout" do
      expect_error(fake_transport(error: HttpTransport::Timeout.new), OpenMeteo::Error::Timeout) do |error|
        expect(error.message).to eq("Weather provider timed out")
      end
    end

    it "translates a transport ConnectionFailed into Unavailable" do
      expect_error(fake_transport(error: HttpTransport::ConnectionFailed.new), OpenMeteo::Error::Unavailable) do |error|
        expect(error.message).to eq("Weather provider unavailable")
      end
    end

    it "lets an unexpected transport error propagate with its own class" do
      expect_error(fake_transport(error: RuntimeError.new("bug")), RuntimeError)
    end
  end

  describe "composition" do
    it "uses the Faraday transport by default, with 2 s to connect and 5 s per read" do
      transport = described_class.new.transport

      expect(transport).to be_a(HttpTransport::FaradayTransport)
      expect([ transport.open_timeout, transport.read_timeout ]).to eq([ 2, 5 ])
    end

    it "uses an injected transport" do
      transport = HttpTransport::HttpRbTransport.new(open_timeout: 2, read_timeout: 5)

      expect(described_class.new(transport: transport).transport).to equal(transport)
    end
  end
end
