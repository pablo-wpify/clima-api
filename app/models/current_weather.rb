# Normalized current weather for a point. Values come from a weather model
# (Open-Meteo), not from an observation; valid_at is a UTC Time.
CurrentWeather = Data.define(
  :requested_coordinates,
  :model_coordinates,
  :temperature_celsius,
  :wind_speed_kmh,
  :valid_at
)
