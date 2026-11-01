# Outcome of the current weather use case. Either a success, with the
# CurrentWeather and no error, or an expected provider failure, with one of the
# public error codes and its public message and no data. Any other combination
# is a programming error and raises ArgumentError. Success is derived from the
# content; it is not stored as a separate field.
CurrentWeatherResult = Data.define(:data, :error_code, :error_message)

class CurrentWeatherResult
  ERROR_CODES = %w[
    provider_timeout
    provider_rate_limited
    provider_unavailable
    provider_error
    provider_invalid_response
  ].freeze

  def self.success(weather)
    new(data: weather, error_code: nil, error_message: nil)
  end

  def self.failure(code:, message:)
    new(data: nil, error_code: code, error_message: message)
  end

  def initialize(data:, error_code:, error_message:)
    raise ArgumentError, "invalid CurrentWeatherResult" unless valid_success?(data, error_code, error_message) ||
      valid_failure?(data, error_code, error_message)

    super
  end

  def success?
    error_code.nil?
  end

  private

  def valid_success?(data, error_code, error_message)
    data.is_a?(CurrentWeather) && error_code.nil? && error_message.nil?
  end

  def valid_failure?(data, error_code, error_message)
    data.nil? && ERROR_CODES.include?(error_code) && error_message.is_a?(String) && !error_message.strip.empty?
  end
end
