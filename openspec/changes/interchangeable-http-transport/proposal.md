# Propuesta: transporte HTTP intercambiable y resultado del caso de uso del clima

## Why

Hoy `OpenMeteo::Client` mezcla las reglas del proveedor con todo lo que sabe de Faraday: construye la conexión, fija los timeouts y traduce sus excepciones. Cambiar de biblioteca HTTP obliga a modificar el cliente, y los fallos previstos del proveedor viajan como excepciones hasta el controller. Este cambio separa el transporte detrás de un contrato propio, para poder elegir entre Faraday y HTTP.rb inyectando una instancia, y hace que el caso de uso devuelva un resultado explícito de éxito o fallo. El contrato HTTP público de la API no cambia.

## What Changes

- Nuevo espacio de nombres `HttpTransport` con `Response` (estado entero y cuerpo completo como texto), errores propios (`Timeout` y `ConnectionFailed`) y dos adaptadores: `FaradayTransport` y `HttpRbTransport`.
- Los estados 3xx, 4xx y 5xx son respuestas, no errores del transporte. Sin redirects ni reintentos. Conexión de 2 s y lectura de 5 s, con su semántica y sus límites documentados, sin prometer una duración total ni cobertura de DNS.
- `OpenMeteo::Client` recibe el transporte como dependencia y conserva las reglas del proveedor: URL, parámetros, clasificación de estados y exigencia de un objeto JSON. Deja de conocer Faraday.
- Faraday sigue como transporte predeterminado, elegido en un único punto explícito de construcción. Sin selección por parámetros HTTP, contenedor de dependencias ni variables de entorno.
- `CurrentWeatherFetcher` devuelve un `CurrentWeatherResult` basado en `Data`: `data`, `error_code` y `error_message`, con `success?` calculado y combinaciones inválidas rechazadas. Convierte en resultado solo los fallos previstos del proveedor; los errores de programación siguen propagándose.
- El controller interpreta el resultado y conserva exactamente la traducción actual a HTTP: estados, códigos y mensajes. `Coordinates::Invalid` mantiene su manejo actual.
- Dependencias de ejecución: se agrega la gema `http` (HTTP.rb), que trae la extensión nativa `llhttp`. Su instalación y funcionamiento con Ruby 4.0.9 se comprueban en local y en CI.
- Pruebas: contrato compartido para ambos adaptadores, pruebas del endpoint con los dos transportes, un grupo separado contra un servidor en `127.0.0.1` para los timeouts de lectura, y una consulta real a Open-Meteo con cada adaptador fuera de la suite.
- `openspec/config.yaml` deja de presentar a Faraday como la única biblioteca HTTP.
- `ApplicationService` no cambia.

Este cambio no es **BREAKING** para quienes consumen la API: el contrato público se mantiene.

## Capabilities

### New Capabilities

- `http-transport`: contrato del transporte HTTP usado para hablar con proveedores externos (petición, respuesta, errores, timeouts, sin redirects ni reintentos) y su intercambio por inyección entre los adaptadores verificados.

### Modified Capabilities

- `current-weather`: se agregan los requisitos del resultado del caso de uso del clima actual (éxito o fallo previsto, con sus invariantes) y se precisa el requisito "Petición al proveedor controlada por la aplicación": un único intento, sin reintentos ni redirects; una sola petición cuando la solicitud llega al proveedor, sabiendo que un fallo previo de DNS o de conexión puede impedir que se envíe. El comportamiento HTTP público no cambia.
- `development-environment`: el requisito de la suite sin peticiones HTTP reales se extiende a HTTP.rb y define el grupo separado contra `127.0.0.1` y la comprobación real con cada transporte.

`service-objects`, `health-check` y `continuous-integration` no cambian.

## Impact

- **Código:** `app/clients/open_meteo/client.rb`, `app/services/current_weather_fetcher.rb`, `app/controllers/api/v1/weather_controller.rb`; nuevos `app/clients/http_transport/*` y `app/models/current_weather_result.rb`.
- **Dependencias:** `Gemfile` y `Gemfile.lock` (`http` con `llhttp` nativa, `http-cookie` y sus dependencias). Hace falta un compilador de C en local y en CI.
- **Pruebas:** se reescriben las del cliente, el servicio y el endpoint; se agregan las de los transportes, el contrato compartido, el resultado y el grupo `127.0.0.1`.
- **Documentación y configuración:** `README.md` (prerrequisitos, arquitectura, comprobación real con cada transporte, límites de los timeouts) y `openspec/config.yaml`.
- **API pública:** sin cambios.
