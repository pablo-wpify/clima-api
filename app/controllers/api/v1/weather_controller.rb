module Api
  module V1
    # Translates HTTP into a CurrentWeatherFetcher call and its
    # CurrentWeatherResult back into HTTP. Only reads the latitude and longitude
    # query parameters; anything else is ignored.
    class WeatherController < ApplicationController
      SOURCE = {
        provider: "Open-Meteo",
        data_type: "model",
        attribution: "Weather data by Open-Meteo.com",
        url: "https://open-meteo.com/",
        license: "CC BY 4.0",
        license_url: "https://creativecommons.org/licenses/by/4.0/"
      }.freeze

      STATUS_BY_CODE = {
        "provider_timeout" => :gateway_timeout,
        "provider_rate_limited" => :service_unavailable,
        "provider_unavailable" => :bad_gateway,
        "provider_error" => :bad_gateway,
        "provider_invalid_response" => :bad_gateway
      }.freeze

      rescue_from Coordinates::Invalid, with: :render_invalid_coordinates

      def show
        coordinates = Coordinates.parse(latitude: params[:latitude], longitude: params[:longitude])
        result = CurrentWeatherFetcher.call(coordinates: coordinates)

        if result.success?
          render json: weather_json(result.data)
        else
          render_provider_failure(result)
        end
      end

      private

      def weather_json(weather)
        {
          requested_coordinates: weather.requested_coordinates.to_h,
          model_coordinates: weather.model_coordinates.to_h,
          temperature_celsius: weather.temperature_celsius,
          wind_speed_kmh: weather.wind_speed_kmh,
          valid_at: weather.valid_at.utc.iso8601,
          source: SOURCE
        }
      end

      def render_invalid_coordinates(error)
        render status: :bad_request, json: {
          error: { code: "invalid_parameters", message: error.message, details: error.details }
        }
      end

      def render_provider_failure(result)
        render status: STATUS_BY_CODE.fetch(result.error_code),
          json: { error: { code: result.error_code, message: result.error_message } }
      end
    end
  end
end
