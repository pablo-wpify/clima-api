# Clima API

API Rails educativa que consulta Open-Meteo a partir de coordenadas y devuelve el clima actual (temperatura y viento) con unidades explícitas. Usa Rails 8.1.4 en modo API, sin base de datos, con RSpec y una ruta de salud.

## Prerrequisitos

- [asdf](https://asdf-vm.com/) con Ruby 4.0.9 instalado. La versión está fijada en `.tool-versions` y `.ruby-version`, y el `Gemfile` la toma de `.ruby-version`.
- Si usás nvm y aparece antes que asdf en el `PATH`, desactivalo en la terminal de trabajo:

  ```sh
  nvm deactivate
  ```

- Un compilador de C y `make` (en Debian o Ubuntu, el paquete `build-essential`). `bundle install` compila la extensión nativa de [llhttp](https://github.com/bryanp/llhttp), que usa HTTP.rb para leer las respuestas.
- La aplicación no usa base de datos: no hace falta instalar ni configurar ninguna.

Comprobá la versión antes de seguir:

```sh
ruby -v
```

Debe mostrar `ruby 4.0.9`.

## Instalación

```sh
bundle install
```

## Pruebas

```sh
bundle exec rspec
```

La suite usa [WebMock](https://github.com/bblimke/webmock) para bloquear las peticiones HTTP reales hechas con las bibliotecas que intercepta (entre ellas Net::HTTP, que usa Faraday, y HTTP.rb). Las respuestas de Open-Meteo se simulan, así que las pruebas no consultan al proveedor. Esto no es un aislamiento de red del sistema operativo.

### Grupo local contra 127.0.0.1

El comando anterior no ejecuta este grupo. Se ejecuta por separado:

```sh
bundle exec rspec --tag loopback spec/loopback
```

Abre servidores propios en `127.0.0.1`, con sockets reales, y comprueba con los dos transportes (Faraday y HTTP.rb) tres situaciones: un servidor que acepta la conexión y no responde, otro que envía los encabezados y deja de enviar el cuerpo (ambos deben dar un timeout de lectura) y un puerto sin nadie escuchando (conexión fallida). WebMock solo permite el puerto de cada servidor local. Cada ejemplo espera a que su servidor esté listo, mide la duración con un reloj monotónico, tiene un límite de 5 segundos y cierra sus servidores, sockets e hilos al terminar.

**Alcance:** comprueba los timeouts de lectura, la conexión rechazada y la limpieza de los recursos que crea cada ejemplo. Cada servidor atiende una sola conexión y puede dejar otras pendientes sin aceptar, así que el contador de peticiones recibidas no demuestra por sí solo que no haya reintentos. Esa garantía se apoya además en las pruebas simuladas (una sola petición o un solo intento registrado) y en la configuración inspeccionada de cada biblioteca.

**Límites:** no demuestra el timeout al conectar, el handshake TLS ni la resolución DNS. Para la conexión rechazada, el puerto se reserva y se libera antes de conectar, así que otro proceso podría ocuparlo en ese intervalo; si pasa, es un problema del montaje de la prueba, no del transporte.

## Análisis de estilo y seguridad

```sh
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit update
bin/bundler-audit
```

- `bin/brakeman` se ejecuta con `--ensure-latest`: si existe una versión nueva de Brakeman, falla hasta que se actualice la gem.
- `bin/bundler-audit update` descarga o actualiza la base local de avisos de seguridad (ruby-advisory-db) y necesita red. `bin/bundler-audit` audita contra esa base local sin actualizarla, así que conviene correr `update` antes de cada auditoría.

## Verificación completa

```sh
bin/ci
```

Ejecuta, en orden, la preparación del entorno, el análisis de estilo, los análisis de seguridad y la suite de pruebas. Termina con código 0 solo si todos pasan. GitHub Actions ejecuta las mismas comprobaciones (`.github/workflows/ci.yml`).

## Servidor y ruta de salud

```sh
bin/rails server
```

En otra terminal:

```sh
curl -i http://localhost:3000/up
```

Debe responder `HTTP/1.1 200 OK`.

## Clima actual

```
GET /api/v1/weather?latitude=<latitud>&longitude=<longitud>
```

Con el servidor levantado:

```sh
curl -i "http://localhost:3000/api/v1/weather?latitude=-37.32&longitude=-59.13"
```

**Respuesta ilustrativa** (los valores cambian en cada consulta):

```json
{
  "requested_coordinates": { "latitude": -37.32, "longitude": -59.13 },
  "model_coordinates": { "latitude": -37.2935, "longitude": -59.08487 },
  "temperature_celsius": 17.6,
  "wind_speed_kmh": 8.8,
  "valid_at": "2026-10-31T15:00:00Z",
  "source": {
    "provider": "Open-Meteo",
    "data_type": "model",
    "attribution": "Weather data by Open-Meteo.com",
    "url": "https://open-meteo.com/",
    "license": "CC BY 4.0",
    "license_url": "https://creativecommons.org/licenses/by/4.0/"
  }
}
```

- `requested_coordinates`: las coordenadas recibidas, convertidas a número de punto flotante (puede haber redondeo si se envían muchos decimales).
- `model_coordinates`: el punto de la grilla del modelo que usa Open-Meteo, que puede no coincidir con el pedido.
- `valid_at`: el momento, en UTC, para el que el proveedor declara válido el dato.

**Son datos de modelo, no mediciones.** Open-Meteo indica que las condiciones actuales se basan en datos de un modelo meteorológico con intervalos de 15 minutos, no en observaciones de una estación.

### Coordenadas aceptadas

- `latitude` y `longitude` son obligatorias. Cada una es un número decimal escrito con un `-` opcional, dígitos y, si hace falta, un punto seguido de dígitos (por ejemplo, `-37.32`, `0` o `45`). No hay límite de decimales.
- No se aceptan `+`, espacios, comas, exponentes (`1e2`), `NaN`, `Infinity`, arrays ni objetos.
- Latitud entre -90 y 90; longitud entre -180 y 180, con los límites incluidos.
- Los demás parámetros se ignoran. Si una clave se repite, se usa el último valor.

### Errores

Todos los errores tienen la forma `{"error": {"code": "...", "message": "..."}}`. Nunca incluyen el cuerpo ni los mensajes del proveedor.

| Status | `code` | Cuándo |
|---|---|---|
| 400 | `invalid_parameters` | Coordenadas ausentes, vacías, mal formadas, de otro tipo o fuera de rango. Incluye `details` con cada campo y su problema (`missing`, `blank`, `invalid_type`, `invalid_format`, `out_of_range`). No se consulta al proveedor |
| 504 | `provider_timeout` | El proveedor no respondió a tiempo, al conectar o al leer |
| 503 | `provider_rate_limited` | El proveedor respondió HTTP 429 |
| 502 | `provider_unavailable` | No se pudo conectar con el proveedor (incluidos errores TLS) |
| 502 | `provider_error` | El proveedor respondió un estado distinto de 2xx y de 429 (los redirects no se siguen) |
| 502 | `provider_invalid_response` | La respuesta del proveedor no es JSON, le falta un dato, trae `null`, un tipo o unidad inesperados o una fecha imposible |

Cada consulta válida hace un único intento de petición a una URL fija de Open-Meteo, sin reintentos, redirects ni caché. Si la solicitud llega al proveedor, este recibe una sola petición; ante un fallo previo de DNS o de conexión puede no haberse enviado ninguna.

### Tiempos de espera

- **Conexión: 2 segundos.** Límite para establecer la conexión. Según la inspección del código de Faraday (Net::HTTP) y de HTTP.rb, también se aplica al handshake TLS.
- **Lectura: 5 segundos por cada espera.** Se aplica a cada espera de datos, no a la respuesta completa: un servidor que envía datos lentamente puede hacer que la petición dure más.
- **No son un límite total.** No hay una duración máxima garantizada para la petición completa.
- **DNS sin comprobar.** No está comprobado si estos límites cubren la resolución de nombres.

### Atribución, licencia y condiciones de uso

- Datos meteorológicos: [Weather data by Open-Meteo.com](https://open-meteo.com/), bajo la licencia [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Cada respuesta exitosa incluye esta atribución en `source`.
- **Modificaciones aplicadas a los datos:** la API selecciona solo la temperatura y la velocidad del viento, expresa la fecha en UTC con formato ISO 8601 y sufijo `Z`, y reorganiza los campos. Los valores numéricos no se alteran.
- Este proyecto usa el plan gratuito para uso no comercial (contenido educativo), sin API key. Sus límites son 600 llamadas por minuto, 5.000 por hora, 10.000 por día y 300.000 por mes, por dirección IP. El servicio se ofrece "as is", sin garantía de disponibilidad.
- Fuentes, consultadas el 2026-10-31: [documentación de la API](https://open-meteo.com/en/docs), [términos de uso](https://open-meteo.com/en/terms) y [licencia](https://open-meteo.com/en/licence).

### Comprobación manual contra Open-Meteo

Las pruebas automáticas nunca consultan al proveedor real. Para verificar la integración real, con el servidor levantado:

```sh
curl -i "http://localhost:3000/api/v1/weather?latitude=-37.32&longitude=-59.13"
curl -i "http://localhost:3000/api/v1/weather?latitude=91&longitude=0"
```

La primera consulta debe responder `200` con la forma de arriba, y la segunda `400` con `invalid_parameters`.

#### Con cada transporte

El servidor usa el transporte predeterminado (Faraday). Para comprobar los dos transportes contra Open-Meteo, sin levantar el servidor, ejecutá este comando una vez con `TRANSPORT=faraday` y otra con `TRANSPORT=http_rb`. Cada ejecución hace dos consultas al proveedor: una al caso de uso, con el transporte inyectado en el cliente, y otra al endpoint completo, reemplazando el transporte predeterminado solo dentro de ese proceso. La variable `TRANSPORT` la lee solo este comando de comprobación; la aplicación no la usa.

```sh
TRANSPORT=faraday bin/rails runner '
  transport = { "faraday" => HttpTransport::FaradayTransport, "http_rb" => HttpTransport::HttpRbTransport }
    .fetch(ENV.fetch("TRANSPORT")).new(open_timeout: 2, read_timeout: 5)
  coordinates = Coordinates.parse(latitude: "-37.32", longitude: "-59.13")
  result = CurrentWeatherFetcher.call(coordinates: coordinates, client: OpenMeteo::Client.new(transport: transport))
  puts({ transport: transport.class.name, success: result.success?, error_code: result.error_code,
         data: result.data&.to_h&.transform_values { |v| v.is_a?(Coordinates) ? v.to_h : v } }.to_json)
  OpenMeteo::Client.define_singleton_method(:default_transport) { transport }
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! "localhost"
  session.get "/api/v1/weather?latitude=-37.32&longitude=-59.13"
  puts({ status: session.response.status, body: JSON.parse(session.response.body) }.to_json)
'
```

Con cada transporte, el resultado debe indicar éxito y la respuesta debe cumplir el contrato de arriba: estado `200`, exactamente esas claves, temperatura y viento numéricos, coordenadas numéricas dentro de rango, `valid_at` en UTC con formato ISO 8601 y sufijo `Z`, y `source` con proveedor, tipo de dato, atribución y licencia. No se espera que los valores meteorológicos ni `valid_at` coincidan entre una ejecución y otra: el dato puede cambiar entre consultas.

## Arquitectura

```
Api::V1::WeatherController   HTTP: lee latitude y longitude, valida con Coordinates.parse (400)
   |                         y traduce el resultado del caso de uso a JSON y a un estado HTTP
CurrentWeatherFetcher        caso de uso: valida los datos del proveedor y devuelve un CurrentWeatherResult
   |
OpenMeteo::Client            reglas de Open-Meteo: URL, parámetros, estados HTTP y JSON objeto
   |
HttpTransport                comunicación: un GET con respuesta propia y dos fallos previstos
   |-- FaradayTransport      predeterminado
   `-- HttpRbTransport       alternativo
```

- **Transporte (`HttpTransport`).** `get(url, params:, headers:)` devuelve un `HttpTransport::Response` con el estado como entero y el cuerpo completo como texto. Cualquier estado HTTP, incluidos 3xx, 4xx y 5xx, es una respuesta. Hace un único intento, sin redirects ni reintentos. Solo traduce los fallos de comunicación previstos: `HttpTransport::Timeout` y `HttpTransport::ConnectionFailed`. Los errores inesperados se propagan con su tipo original. Ningún objeto de respuesta ni fallo previsto de Faraday o HTTP.rb sale del adaptador.
- **Elección del transporte.** `OpenMeteo::Client.default_transport` es el único punto donde se construye el transporte de producción (Faraday, con los tiempos de espera de arriba). Para usar HTTP.rb se inyecta la instancia: `OpenMeteo::Client.new(transport: HttpTransport::HttpRbTransport.new(open_timeout: 2, read_timeout: 5))`. No se elige por parámetros de la petición ni por variables de entorno.
- **Resultado del caso de uso (`CurrentWeatherResult`).** Un `Data` con `data`, `error_code` y `error_message`. `success?` se calcula: es `true` cuando no hay código de error. En el éxito, `data` es un `CurrentWeather` y no hay error; en un fallo previsto del proveedor, `data` es `nil` y el código es uno de los de la tabla de errores (salvo `invalid_parameters`), con su mensaje. Cualquier otra combinación se rechaza al construirlo. Esa validación ocurre solo al construir: como todo `Data`, su inmutabilidad es superficial, así que los textos que contiene (`error_code` y `error_message`) podrían modificarse después. Los errores de programación no se convierten en resultado: se propagan.
- **`ApplicationService`** solo ofrece el atajo `Servicio.call(...)`; no impone un tipo de resultado a los servicios.
