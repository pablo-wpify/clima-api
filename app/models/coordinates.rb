require "bigdecimal"

# A validated geographic point. Build it with Coordinates.parse, which checks
# the raw query values strictly and reports every invalid field at once.
Coordinates = Data.define(:latitude, :longitude)

class Coordinates
  # Raised by .parse; #details lists { field:, issue: } for each invalid field.
  class Invalid < StandardError
    attr_reader :details

    def initialize(details)
      @details = details
      super("Invalid coordinates")
    end
  end

  DECIMAL_FORMAT = /\A-?\d+(\.\d+)?\z/
  RANGES = { "latitude" => -90..90, "longitude" => -180..180 }.freeze

  def self.parse(latitude:, longitude:)
    raw = { "latitude" => latitude, "longitude" => longitude }
    details = raw.filter_map { |field, value| issue_for(field, value) }
    raise Invalid.new(details) if details.any?

    new(latitude: Float(latitude), longitude: Float(longitude))
  end

  def self.issue_for(field, value)
    issue =
      if value.nil? then "missing"
      elsif !value.is_a?(String) then "invalid_type"
      elsif value.strip.empty? then "blank"
      elsif !DECIMAL_FORMAT.match?(value) then "invalid_format"
      elsif !RANGES.fetch(field).cover?(BigDecimal(value)) then "out_of_range"
      end

    { field: field, issue: issue } if issue
  end
  private_class_method :issue_for
end
