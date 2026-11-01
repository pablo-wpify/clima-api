# Shared contract for every HttpTransport adapter (design D2, D3 and D9).
#
# The including spec must define:
# - `transport`: the adapter under test, built with open_timeout: 2 and read_timeout: 5.
# - `simulate`: a Hash that tells how to provoke each failure on a WebMock stub with
#   the adapter's own library (:read_timeout, :connect_timeout, :refused, :tls).
#
# WebMock records every attempt, even when a simulated failure means that no server
# received anything: in connection failures, "once" means a single attempt.
RSpec.shared_examples "an HTTP transport" do
  let(:url) { "https://provider.example/v1/resource" }
  let(:params) { { "latitude" => "-37.32", "current" => "temperature_2m,wind_speed_10m" } }
  let(:headers) { { "Accept" => "application/json" } }

  def stub_resource
    stub_request(:get, url).with(query: params, headers: headers)
  end

  def get
    transport.get(url, params: params, headers: headers)
  end

  describe "responses" do
    it "returns its own Response with an Integer status and the whole body as text" do
      stub_resource.to_return(status: 200, body: '{"ok":true}')

      response = get

      expect(response).to be_a(HttpTransport::Response)
      expect(response.status).to eq(200)
      expect(response.status).to be_an(Integer)
      expect(response.body).to eq('{"ok":true}')
    end

    it "sends exactly the given query and Accept header" do
      stub = stub_resource.to_return(status: 200, body: "{}")

      get

      expect(stub).to have_been_requested.once
    end

    it "returns an empty body as an empty String" do
      stub_resource.to_return(status: 204, body: "")

      expect(get.body).to eq("")
    end

    it "returns 400, 429 and 500 as responses with their body" do
      [ 400, 429, 500 ].each do |status|
        stub_resource.to_return(status: status, body: "error #{status}")

        response = get

        expect([ response.status, response.body ]).to eq([ status, "error #{status}" ])
      end
    end

    it "returns a redirect without following it" do
      stub = stub_resource.to_return(status: 301, headers: { "Location" => "https://elsewhere.example/" })

      expect(get.status).to eq(301)
      expect(stub).to have_been_requested.once
      expect(a_request(:get, /elsewhere\.example/)).not_to have_been_made
    end

    it "makes a single request when the server answers 500" do
      stub = stub_resource.to_return(status: 500)

      get

      expect(stub).to have_been_requested.once
    end
  end

  describe "expected communication failures" do
    it "translates a read timeout into Timeout after a single attempt" do
      stub = simulate.fetch(:read_timeout).call(stub_resource)

      expect { get }.to raise_error(HttpTransport::Timeout)
      expect(stub).to have_been_requested.once
    end

    it "translates a connection timeout into Timeout" do
      simulate.fetch(:connect_timeout).call(stub_resource)

      expect { get }.to raise_error(HttpTransport::Timeout)
    end

    it "translates a refused connection into ConnectionFailed after a single attempt, with a fixed message" do
      stub = simulate.fetch(:refused).call(stub_resource)

      expect { get }.to raise_error(HttpTransport::ConnectionFailed) do |error|
        expect(error.message).to eq("HTTP transport connection failed")
        expect(error.message).not_to include("secret socket detail")
      end
      expect(stub).to have_been_requested.once
    end

    it "translates a TLS error into ConnectionFailed" do
      simulate.fetch(:tls).call(stub_resource)

      expect { get }.to raise_error(HttpTransport::ConnectionFailed)
    end

    it "uses a fixed Timeout message" do
      simulate.fetch(:read_timeout).call(stub_resource)

      expect { get }.to raise_error(HttpTransport::Timeout, "HTTP transport timed out")
    end
  end

  describe "unexpected errors" do
    it "propagates them with their original class" do
      stub_resource.to_raise(ArgumentError.new("unexpected"))

      expect { get }.to raise_error(ArgumentError, "unexpected")
    end
  end
end
