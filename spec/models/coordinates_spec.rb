require "rails_helper"

RSpec.describe Coordinates do
  def parse(latitude:, longitude:)
    described_class.parse(latitude: latitude, longitude: longitude)
  end

  def issues_for(latitude:, longitude:)
    parse(latitude: latitude, longitude: longitude)
    raise "expected Coordinates::Invalid"
  rescue Coordinates::Invalid => e
    e.details
  end

  describe ".parse with valid values" do
    it "returns Float coordinates" do
      coordinates = parse(latitude: "-37.32", longitude: "-59.13")

      expect(coordinates).to eq(described_class.new(latitude: -37.32, longitude: -59.13))
      expect(coordinates.latitude).to be_a(Float)
      expect(coordinates.longitude).to be_a(Float)
    end

    it "accepts integers, zero, negative zero and long decimals" do
      %w[0 -0 45 12.345678901234].each do |value|
        expect { parse(latitude: value, longitude: value) }.not_to raise_error
      end
    end

    it "accepts the inclusive limits" do
      expect(parse(latitude: "90", longitude: "180")).to eq(described_class.new(latitude: 90.0, longitude: 180.0))
      expect(parse(latitude: "-90", longitude: "-180")).to eq(described_class.new(latitude: -90.0, longitude: -180.0))
    end

    it "rounds values with more precision than Float to the nearest Float" do
      coordinates = parse(latitude: "12.345678901234567890123", longitude: "0")

      expect(coordinates.latitude).to eq(12.345678901234567890123.to_f)
      expect(coordinates.latitude).to be_a(Float)
    end
  end

  describe ".parse with invalid values" do
    it "reports a missing value" do
      expect(issues_for(latitude: nil, longitude: "0"))
        .to eq([ { field: "latitude", issue: "missing" } ])
    end

    it "reports blank values" do
      [ "", "   " ].each do |value|
        expect(issues_for(latitude: "0", longitude: value))
          .to eq([ { field: "longitude", issue: "blank" } ])
      end
    end

    it "rejects formats outside the accepted decimal notation" do
      [ "abc", "1,5", "+10", " 10", "10 ", "1.", ".5", "1e2", "0x10", "NaN", "Infinity", "-", "--1", "1.2.3" ].each do |value|
        expect(issues_for(latitude: value, longitude: "0"))
          .to eq([ { field: "latitude", issue: "invalid_format" } ]), "expected #{value.inspect} to be invalid_format"
      end
    end

    it "rejects arrays and objects" do
      array = [ "1" ]
      object = ActionController::Parameters.new("a" => "1")

      expect(issues_for(latitude: array, longitude: object)).to eq([
        { field: "latitude", issue: "invalid_type" },
        { field: "longitude", issue: "invalid_type" }
      ])
    end

    it "rejects values out of range using the exact decimal" do
      expect(issues_for(latitude: "90.0000000000000000001", longitude: "0"))
        .to eq([ { field: "latitude", issue: "out_of_range" } ])
      expect(issues_for(latitude: "-91", longitude: "180.5")).to eq([
        { field: "latitude", issue: "out_of_range" },
        { field: "longitude", issue: "out_of_range" }
      ])
    end

    it "reports every invalid field together" do
      expect(issues_for(latitude: nil, longitude: "abc")).to eq([
        { field: "latitude", issue: "missing" },
        { field: "longitude", issue: "invalid_format" }
      ])
    end
  end
end
