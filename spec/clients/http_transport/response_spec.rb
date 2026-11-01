require "rails_helper"

RSpec.describe HttpTransport::Response do
  it "keeps an Integer status and a String body" do
    response = described_class.new(status: 200, body: "{}")

    expect([ response.status, response.body ]).to eq([ 200, "{}" ])
  end

  it "accepts an empty body" do
    expect(described_class.new(status: 204, body: "").body).to eq("")
  end

  it "rejects a status that is not an Integer between 100 and 599" do
    [ "200", 200.0, nil, 99, 600 ].each do |status|
      expect { described_class.new(status: status, body: "") }.to raise_error(ArgumentError)
    end
  end

  it "rejects a body that is not a String" do
    [ nil, :ok, 1 ].each do |body|
      expect { described_class.new(status: 200, body: body) }.to raise_error(ArgumentError)
    end
  end
end
