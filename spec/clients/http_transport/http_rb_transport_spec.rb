require "rails_helper"
require "openssl"
require_relative "../../support/http_transport_contract"

RSpec.describe HttpTransport::HttpRbTransport do
  subject(:transport) { described_class.new(open_timeout: 2, read_timeout: 5) }

  # WebMock replaces HTTP::Client#perform, above HTTP.rb's own error translation:
  # these stubs only test this adapter's mapping. That HTTP.rb raises these
  # exceptions in real situations rests on source inspection and on the
  # loopback group (spec/loopback).
  let(:simulate) do
    {
      read_timeout: ->(stub) { stub.to_raise(HTTP::TimeoutError) },
      connect_timeout: ->(stub) { stub.to_raise(HTTP::ConnectTimeoutError) },
      refused: ->(stub) { stub.to_raise(HTTP::ConnectionError.new("failed to connect: secret socket detail")) },
      tls: ->(stub) { stub.to_raise(OpenSSL::SSL::SSLError) }
    }
  end

  it_behaves_like "an HTTP transport"

  it "exposes the configured timeouts" do
    expect([ transport.open_timeout, transport.read_timeout ]).to eq([ 2, 5 ])
  end
end
