require "rails_helper"
require "net/http"

RSpec.describe "HTTP request blocking in the test suite" do
  it "blocks a real Net::HTTP request that has no stub" do
    uri = URI("https://api.open-meteo.com/v1/forecast?latitude=0&longitude=0")

    expect { Net::HTTP.get_response(uri) }
      .to raise_error(WebMock::NetConnectNotAllowedError)
  end

  it "blocks a real HTTP.rb request that has no stub" do
    expect { HTTP.get("https://api.open-meteo.com/v1/forecast", params: { latitude: "0", longitude: "0" }) }
      .to raise_error(WebMock::NetConnectNotAllowedError)
  end
end
