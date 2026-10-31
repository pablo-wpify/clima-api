module Api
  module V1
    # Translates HTTP into a CurrentWeatherFetcher call and back. Only reads the
    # latitude and longitude query parameters; anything else is ignored.
    class WeatherController < ApplicationController
      SOURCE = {
        provider: "Open-Meteo",
        data_type: "model",
        attribution: "Weather data by Open-Meteo.com",
        url: "https://open-meteo.com/",
        license: "CC BY 4.0",
        license_url: "https://creativecommons.org/licenses/by/4.0/"
      }.freeze

      PROVIDER_ERRORS = {
        OpenMeteo::Error::Timeout => [ :gateway_timeout, "provider_timeout" ],
        OpenMeteo::Error::RateLimited => [ :service_unavailable, "provider_rate_limited" ],
        OpenMeteo::Error::Unavailable => [ :bad_gateway, "provider_unavailable" ],
        OpenMeteo::Error::HttpError => [ :bad_gateway, "provider_error" ],
        OpenMeteo::Error::InvalidResponse => [ :bad_gateway, "provider_invalid_response" ]
      }.freeze

      rescue_from Coordinates::Invalid, with: :render_invalid_coordinates
      rescue_from OpenMeteo::Error, with: :render_provider_error

      def show
        coordinates = Coordinates.parse(latitude: params[:latitude], longitude: params[:longitude])
        weather = CurrentWeatherFetcher.call(coordinates: coordinates)

        render json: weather_json(weather)
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

      def render_provider_error(error)
        status, code = PROVIDER_ERRORS.fetch(error.class)
        render status: status, json: { error: { code: code, message: error.message } }
      end
    end
  end
end
