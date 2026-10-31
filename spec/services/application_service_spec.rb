require "rails_helper"

RSpec.describe ApplicationService do
  let(:service_class) do
    Class.new(described_class) do
      attr_reader :position, :keyword

      def initialize(position, keyword:)
        @position = position
        @keyword = keyword
      end

      def call
        [ position, keyword ]
      end
    end
  end

  describe ".call" do
    it "forwards positional arguments to the instance" do
      expect(service_class.call(:first, keyword: :second).first).to eq(:first)
    end

    it "forwards keyword arguments to the instance" do
      expect(service_class.call(:first, keyword: :second).last).to eq(:second)
    end

    it "returns the same object the instance returns" do
      result = Object.new
      service_class.define_method(:call) { result }

      expect(service_class.call(:first, keyword: :second)).to equal(result)
    end
  end
end
