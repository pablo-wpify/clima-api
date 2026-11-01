require "rails_helper"
require "net/http"
require "openssl"
require_relative "../../support/http_transport_contract"

RSpec.describe HttpTransport::FaradayTransport do
  subject(:transport) { described_class.new(open_timeout: 2, read_timeout: 5) }

  # WebMock intercepts Net::HTTP, below faraday-net_http, so these failures go
  # through the adapter's real translation.
  let(:simulate) do
    {
      read_timeout: ->(stub) { stub.to_raise(Net::ReadTimeout) },
      connect_timeout: ->(stub) { stub.to_raise(Net::OpenTimeout) },
      refused: ->(stub) { stub.to_raise(Errno::ECONNREFUSED.new("secret socket detail")) },
      tls: ->(stub) { stub.to_raise(OpenSSL::SSL::SSLError) }
    }
  end

  it_behaves_like "an HTTP transport"

  it "exposes the configured timeouts" do
    expect([ transport.open_timeout, transport.read_timeout ]).to eq([ 2, 5 ])
  end

  it "configures Faraday with connection and read timeouts only, without a total timeout" do
    options = transport.instance_variable_get(:@connection).options

    expect([ options.open_timeout, options.read_timeout, options.timeout ]).to eq([ 2, 5, nil ])
  end
end
