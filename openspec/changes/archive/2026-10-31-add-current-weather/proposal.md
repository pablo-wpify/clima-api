# Propuesta: clima actual por coordenadas

## Why

La base Rails (`add-rails-api-base`) está publicada y verificada, pero la API todavía no cumple su propósito: devolver el clima para unas coordenadas. Este cambio agrega la primera consulta real. Recibe latitud y longitud, consulta Open-Meteo y devuelve temperatura y viento con unidades explícitas, fecha en UTC y atribución del proveedor. Lo hace sin base de datos, caché ni reintentos, y con pruebas que no hacen peticiones HTTP reales al proveedor.

## What Changes

- Nuevo endpoint `GET /api/v1/weather?latitude=…&longitude=…` que responde JSON con `requested_coordinates`, `model_coordinates`, `temperature_celsius`, `wind_speed_kmh`, `valid_at` (UTC) y `source`.
- La respuesta deja claro que los valores son **datos de modelo meteorológico**, no mediciones observadas. Así los describe Open-Meteo: "Current conditions are based on 15-minutely weather model data" (documentación consultada el 2026-10-31).
- Validación estricta de coordenadas, con formatos numéricos definidos y rangos inclusivos. Ante una entrada inválida responde 400 sin consultar al proveedor.
- Contrato de errores propio para el proveedor, sin exponer cuerpos externos ni mensajes internos:
  - 504 ante un timeout.
  - 503 `provider_rate_limited` ante un HTTP 429.
  - 502 con códigos distintos para conexión fallida, otros HTTP y respuesta inválida.
- Sin éxito parcial: si falta un dato requerido, llega `null`, tiene un tipo incorrecto o unidades inesperadas, la respuesta es un error.
- La URL del proveedor es fija y la construye la aplicación; el usuario solo aporta las coordenadas. Una sola petición por consulta: sin redirects automáticos, reintentos ni caché.
- Dependencias nuevas:
  - `faraday` (`~> 2.15`) para HTTP, con el adaptador Net::HTTP que trae como dependencia.
  - `webmock` (`~> 3.34`), solo en el grupo `test`, para bloquear durante la suite las peticiones HTTP reales hechas con las bibliotecas que intercepta (entre ellas, Net::HTTP, que usa Faraday). No es un aislamiento de red del sistema operativo.
- Atribución de Open-Meteo (licencia CC BY 4.0) en cada respuesta exitosa y en el README.
- README ampliado con el endpoint, ejemplos, errores, atribución, condiciones de uso y una comprobación manual real, separada de la suite.
- Se conservan los cinco tests existentes y el CI sin cambios de configuración.

**Fuera de alcance:** base de datos, autenticación, caché, reintentos, pronóstico futuro, otras variables meteorológicas, `interval_seconds`, conversión de unidades a pedido y elección de zona horaria por el usuario.

## Capabilities

### New Capabilities

- `current-weather`: consulta HTTP del clima actual por coordenadas, con su validación de entrada, su contrato de respuesta, el tratamiento de los errores del proveedor y la atribución de los datos.

### Modified Capabilities

- `development-environment`: suma un requisito para que la suite bloquee las peticiones HTTP reales hechas con las bibliotecas interceptadas por WebMock, ahora que la aplicación depende de un servicio externo.

## Impact

- **Código nuevo:**
  - Ruta `api/v1/weather`.
  - `Api::V1::WeatherController`.
  - `Coordinates` y `CurrentWeather` (Ruby `Data`).
  - `CurrentWeatherFetcher < ApplicationService`.
  - `OpenMeteo::Client` en `app/clients/open_meteo/client.rb` y `OpenMeteo::Error` con sus subclases.
  - Specs de cada pieza y un request spec del endpoint.
- **Configuración:** `Gemfile` y `Gemfile.lock` (faraday y webmock) y `spec/rails_helper.rb` (WebMock con red bloqueada).
- **Sistema externo:** `https://api.open-meteo.com/v1/forecast`.
  - Plan gratuito no comercial, sin API key.
  - Límites de 600 llamadas por minuto, 5.000 por hora, 10.000 por día y 300.000 por mes (por IP).
  - Sin garantía de disponibilidad.
  - Datos bajo CC BY 4.0, con la obligación de enlazar la atribución junto a los datos.
  - Fuentes: https://open-meteo.com/en/docs, https://open-meteo.com/en/terms, https://open-meteo.com/en/licence, consultadas el 2026-10-31.
- **CI:** el workflow no cambia. bundler-audit y Brakeman pasan a cubrir las gems y el código nuevos.
