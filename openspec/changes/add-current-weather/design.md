# Diseño: clima actual por coordenadas

## Context

Ver `proposal.md` (Why). Para el comportamiento exigido, ver `specs/current-weather/spec.md` y `specs/development-environment/spec.md`.

**Estado de partida:**
- `main` en `d3b36f6`, con el árbol limpio.
- Specs vigentes: `health-check`, `development-environment`, `continuous-integration` y `service-objects`.
- Código existente: `ApplicationController < ActionController::API`, `ApplicationService` (`self.call(...) = new(...).call`) y la ruta `/up`.
- Suite: 5 ejemplos. CI con los jobs `scan_ruby`, `lint` y `test`.
- Faraday y WebMock no están en el `Gemfile`; `json` 3.1.0 y `logger` 1.7.0 ya están en `Gemfile.lock`.

**Datos verificados el 2026-10-31.** Las evidencias están en `/home/pablo/clima-api-evidencias/explore-weather.TFxOrE4l/`.

| Tema | Hecho | Fuente |
|---|---|---|
| Endpoint | `https://api.open-meteo.com/v1/forecast`; `current` acepta las variables horarias (`temperature_2m`, `wind_speed_10m`) | https://open-meteo.com/en/docs |
| Naturaleza del dato | "Current conditions are based on 15-minutely weather model data"; `time` es "the moment at which the data is valid" | ídem |
| Unidades | `temperature_unit=celsius` y `wind_speed_unit=kmh` por defecto | ídem |
| Zona horaria | `timezone=GMT` por defecto; `time` en `iso8601` **sin sufijo de zona** (consulta real: `"2026-10-31T15:00"`) | ídem y consulta real |
| Grilla | Las coordenadas devueltas son las del punto del modelo: se pidió `-37.32, -59.13` y se recibió `-37.2935, -59.08487` | consulta real |
| Errores | HTTP 400 con `{"error": true, "reason": …}`; los `reason` pueden exponer tipos internos | documentación y consulta real |
| Uso | No comercial sin API key; 600 llamadas por minuto, 5.000 por hora, 10.000 por día y 300.000 por mes, por IP; servicio "as is", sin garantía de continuidad | https://open-meteo.com/en/terms |
| Licencia | CC BY 4.0: crédito, enlace a la licencia, indicar cambios y enlace junto a cada lugar donde se muestren los datos; "Weather data by Open-Meteo.com" es un ejemplo de redacción | https://open-meteo.com/en/licence |
| Faraday | 2.15.1 (2026-10-26), Ruby `>= 3.0`; depende de `faraday-net_http >= 2.0, < 3.6` (3.5.0), `json` y `logger` | RubyGems |
| Timeouts | `options[:read_timeout] \|\| options[:timeout]` (igual para `open` y `write`) | `faraday` v2.15.1, `lib/faraday/adapter.rb` |
| Adaptador | `faraday-net_http` 3.5.0 asigna `read_timeout`, `write_timeout` y `open_timeout` a Net::HTTP, pone `max_retries = 0` y no sigue redirects. `Net::OpenTimeout` está en `NET_HTTP_EXCEPTIONS`, por lo que se convierte en **`Faraday::ConnectionFailed`**; `Net::ReadTimeout` (un `Timeout::Error`) se convierte en `Faraday::TimeoutError` | `faraday-net_http` v3.5.0, `lib/faraday/adapter/net_http.rb` |
| Jerarquía de errores | `Faraday::Error` expone `wrapped_exception`. `TimeoutError < ServerError < Error`; `ConnectionFailed`, `SSLError` y `ParsingError` heredan de `Error` | `faraday` v2.15.1, `lib/faraday/error.rb` |
| WebMock | 3.34.0 (2026-10-14), Ruby `>= 2.6`; depende de `addressable`, `crack` y `hashdiff` | RubyGems |
| `Time.utc` | En Ruby 4.0.9 **normaliza** fechas imposibles: `Time.utc(2026, 2, 30, 15, 0)` da `2026-03-02T15:00:00Z` y `Time.utc(2026, 10, 31, 24, 0)` da `2026-11-01T00:00:00Z`. En cambio, el mes 13 y el minuto 60 lanzan `ArgumentError`. `Date.valid_date?(2026, 2, 30)` y `Date.valid_date?(2026, 13, 1)` devuelven `false` | `ruby -rdate -e …`, ejecutado el 2026-10-31 |

## Goals / Non-Goals

**Goals:**
- Pocas piezas, cada una con una sola razón para cambiar, y dependencias inyectables para probar sin red (criterios de SOLID y de Sandi Metz).
- Que la traducción de errores del proveedor sea explícita y probada contra el adaptador real, no contra suposiciones.
- No prometer más de lo que garantiza el adaptador, sobre todo en tiempos.

**Non-Goals:**
- Serializadores, capas de manejo de errores genéricas o abstracciones de "proveedor" pensadas para varios servicios.
- Reintentos, caché, redirects o tiempos totales garantizados.
- Cambios en el workflow de CI.

## Decisions

### D1. Piezas y responsabilidades

```
GET /api/v1/weather
        |
        v
Api::V1::WeatherController ---- Coordinates.parse ---- (inválida) --> 400
        |                            (Data)
        v
CurrentWeatherFetcher.call(coordinates:)       < ApplicationService
        |   valida el JSON del proveedor y arma CurrentWeather (Data)
        v
OpenMeteo::Client#current(coordinates)  --> Faraday (net_http) --> api.open-meteo.com
        |   errores de transporte y HTTP como OpenMeteo::Error::*
        v
Controller: CurrentWeather -> JSON 200;  OpenMeteo::Error::* -> 502/503/504
```

| Archivo | Constante | Responsabilidad |
|---|---|---|
| `config/routes.rb` | — | `namespace :api { namespace :v1 { get "weather", to: "weather#show" } }` |
| `app/controllers/api/v1/weather_controller.rb` | `Api::V1::WeatherController` | Leer `params[:latitude]` y `params[:longitude]`, llamar a `Coordinates.parse` y al servicio, traducir resultado y errores a HTTP y JSON (D6, D7) |
| `app/models/coordinates.rb` | `Coordinates = Data.define(:latitude, :longitude)` | `.parse(latitude:, longitude:)`: valida formato, tipo, presencia y rango (D5); devuelve la instancia o lanza `Coordinates::Invalid` con `details` |
| `app/models/current_weather.rb` | `CurrentWeather = Data.define(:requested_coordinates, :model_coordinates, :temperature_celsius, :wind_speed_kmh, :valid_at)` | Resultado normalizado; `valid_at` es un `Time` en UTC |
| `app/services/current_weather_fetcher.rb` | `CurrentWeatherFetcher < ApplicationService` | `initialize(coordinates:, client: OpenMeteo::Client.new)`; `#call` pide el payload, lo valida (D4) y devuelve `CurrentWeather` |
| `app/clients/open_meteo/client.rb` | `OpenMeteo::Client` | `initialize(connection: …)` (D2); `#current(coordinates)` hace una única petición GET, traduce transporte y estado HTTP (D3) y devuelve el JSON como `Hash` |
| `app/clients/open_meteo/error.rb` | `OpenMeteo::Error` y sus subclases anidadas `Timeout`, `RateLimited`, `Unavailable`, `HttpError` e `InvalidResponse` | Errores propios del proveedor, con mensajes genéricos que no copian nada externo |

- Zeitwerk carga `app/clients/` como raíz de autoload, así que `app/clients/open_meteo/client.rb` define `OpenMeteo::Client`. Las subclases anidadas dentro de `OpenMeteo::Error` cumplen la regla de un archivo por constante raíz.
- **Alternativa descartada:** que el cliente devuelva directamente `CurrentWeather`. Eso dejaría al servicio como un pasamanos vacío y mezclaría en el cliente el transporte con el contrato de datos. Con la separación elegida, el cliente sabe de HTTP y el servicio sabe del formato de los datos.

### D2. Petición y conexión

- `BASE_URL = "https://api.open-meteo.com"` y `PATH = "/v1/forecast"` son constantes del cliente; nada proviene del usuario.
- Los parámetros son siempre estos: `latitude`, `longitude`, `current=temperature_2m,wind_speed_10m`, `temperature_unit=celsius`, `wind_speed_unit=kmh` y `timezone=GMT`. Se exige el conjunto exacto de claves y valores, no un orden en el query string. Las coordenadas se envían como `Float#to_s` del valor validado.
- La conexión por defecto es `Faraday.new(url: BASE_URL, request: { open_timeout: 2, read_timeout: 5 }, headers: { "Accept" => "application/json" })`, con el adaptador por defecto (`net_http`). No se agregan middlewares: ni `raise_error`, ni `json`, ni redirects, ni reintentos.
- **Qué significan los tiempos, con `faraday-net_http` 3.5.0:**
  - `open_timeout: 2` es el máximo para establecer la conexión TCP con Net::HTTP.
  - `read_timeout: 5` es el máximo de espera **por cada lectura** del socket. No limita la duración total de la petición.
  - No se usa `timeout`, que solo es un valor por defecto para las tres claves. `write_timeout` queda con el valor por defecto de Net::HTTP; en un GET sin cuerpo es irrelevante.
  - La resolución DNS no está acotada por estas opciones. **No se promete un tiempo total máximo.**
- El adaptador fija `max_retries = 0`, así que hay una sola petición por consulta. No sigue redirects, así que un 3xx se trata como cualquier otro estado distinto de 2xx.

### D3. Traducción de errores en el cliente

Los estados HTTP se tratan explícitamente, sin el middleware `raise_error`:
- 2xx: se parsea el cuerpo con `JSON.parse`. Si falla (`JSON::ParserError`) o el resultado no es un `Hash`, se lanza `InvalidResponse`.
- 429: `RateLimited`.
- Cualquier otro estado, incluidos 3xx, 4xx y 5xx: `HttpError`.

Las excepciones de transporte se rescatan en este orden, porque `Faraday::TimeoutError` hereda de `Faraday::ServerError`, y `ConnectionFailed` puede envolver un timeout de conexión:

```
rescue Faraday::TimeoutError                      -> OpenMeteo::Error::Timeout
rescue Faraday::ConnectionFailed => e
  e.wrapped_exception.is_a?(Net::OpenTimeout)     -> OpenMeteo::Error::Timeout
  en cualquier otro caso                          -> OpenMeteo::Error::Unavailable
rescue Faraday::SSLError                          -> OpenMeteo::Error::Unavailable
rescue Faraday::Error                             -> OpenMeteo::Error::Unavailable
```

- El tratamiento de `Net::OpenTimeout` es la consecuencia directa de lo verificado en el código del adaptador. Sin él, un timeout de conexión respondería 502 en lugar del 504 que pide la spec.
- Los errores propios llevan mensajes fijos. No se copia el `reason` del proveedor ni el mensaje de la excepción original; la excepción original queda solo como `cause` de Ruby, que nunca se serializa.

### D4. Validación del payload en el servicio

Para aceptar la respuesta deben cumplirse todas estas condiciones, comprobadas en este orden. Si alguna falla, se lanza `OpenMeteo::Error::InvalidResponse`:

1. **Estructura.** El payload es un `Hash` (el cliente ya lo garantiza, y el servicio lo vuelve a comprobar porque recibe el cliente por inyección). `payload["current"]` y `payload["current_units"]` son `Hash`. Una clave ausente, `nil`, `Array`, `String`, `Numeric`, `true` o `false` es inválida. Esta comprobación va **antes** de leer cualquier clave interna, así ningún `NoMethodError` llega a ocurrir.
2. `utc_offset_seconds == 0`, porque se pidió `timezone=GMT`.
3. `latitude` y `longitude` son números finitos dentro de los rangos geográficos. Pasan a `model_coordinates`.
4. `current_units.temperature_2m == "°C"`, `current_units.wind_speed_10m == "km/h"` y `current_units.time == "iso8601"`.
5. `current.temperature_2m` y `current.wind_speed_10m` son `Integer` o `Float` (nunca `true` o `false`) y finitos.
6. `current.time` es una fecha válida según el procedimiento estricto de abajo.

Las claves faltantes y los valores `null` se tratan como inválidos. No hay valores por defecto ni éxito parcial.

**Fecha estricta, sin normalización.** `Time.utc` normaliza (convierte `2026-02-30` en `2026-03-02` y la hora `24:00` en el día siguiente), así que el regex más `Time.utc` no alcanza:

1. `current.time` es un `String` que cumple `\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})\z`. Las capturas se convierten a enteros.
2. Se exige `1 <= mes <= 12`, `Date.valid_date?(año, mes, día)`, `0 <= hora <= 23` y `0 <= minuto <= 59`. Si algo falla, es inválida.
3. Solo con los componentes ya validados se construye `Time.utc(año, mes, día, hora, minuto)`. Como verificación final, `time.strftime("%Y-%m-%dT%H:%M")` tiene que coincidir con el texto original; si no coincide, es inválida.
4. `valid_at` se serializa con `time.utc.iso8601`, que da `"2026-10-31T15:00:00Z"`, con segundos y `Z`.

Como `Time.utc` solo recibe componentes válidos, no lanza `ArgumentError` y no hace falta rescatarlo.

**Rescates específicos.** El cliente rescata solo `JSON::ParserError` y clases de `Faraday` (D3). El servicio no rescata excepciones: valida antes de acceder. **No se agrega `rescue StandardError`** en ninguna pieza, así un error de programación sigue apareciendo como error y no se disfraza de `provider_invalid_response`.

### D5. Validación de coordenadas

Para cada campo, en este orden:
1. `nil`: `missing`.
2. Valor que no es `String` (un `Array` o un `ActionController::Parameters`): `invalid_type`.
3. Texto vacío o solo espacios (`strip.empty?`): `blank`.
4. Texto que no cumple `\A-?\d+(\.\d+)?\z`: `invalid_format`. Esto excluye `+`, espacios alrededor de un número, comas, exponentes, hexadecimales, `NaN` e `Infinity`.
5. `BigDecimal(valor)` fuera de [-90, 90] para la latitud o de [-180, 180] para la longitud: `out_of_range`. Se usa `BigDecimal` para que `90.0000000000000000001` no se redondee a `90.0`.

- Se validan ambos campos y se informan todos los errores juntos.
- Las coordenadas válidas se guardan como `Float`. Con decimales más allá de la precisión de `Float`, `requested_coordinates` muestra el valor redondeado. No hay límite de decimales en la entrada.
- Las claves repetidas siguen a Rails (gana el último valor). Los parámetros desconocidos no se leen.

### D6. Contrato JSON

**Éxito (200).** Ejemplo ilustrativo armado con la consulta real del 2026-10-31; no es una respuesta producida por el código:

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

**Error:**

```json
{ "error": { "code": "invalid_parameters", "message": "Invalid coordinates",
             "details": [ { "field": "latitude", "issue": "out_of_range" } ] } }
```

- `valid_at` se arma con `Time#utc.iso8601`, que produce el sufijo `Z`.
- Los textos de `message` van en inglés, igual que los códigos y las claves.

### D7. Traducción a HTTP en el controller

| Origen | Status | `code` | `message` |
|---|---|---|---|
| `Coordinates::Invalid` | 400 | `invalid_parameters` | `Invalid coordinates` (+ `details`) |
| `OpenMeteo::Error::Timeout` | 504 | `provider_timeout` | `Weather provider timed out` |
| `OpenMeteo::Error::RateLimited` | 503 | `provider_rate_limited` | `Weather provider rate limit reached` |
| `OpenMeteo::Error::Unavailable` | 502 | `provider_unavailable` | `Weather provider unavailable` |
| `OpenMeteo::Error::HttpError` | 502 | `provider_error` | `Weather provider returned an error` |
| `OpenMeteo::Error::InvalidResponse` | 502 | `provider_invalid_response` | `Weather provider returned an invalid response` |

El controller rescata solo `Coordinates::Invalid` y `OpenMeteo::Error`. Cualquier otra excepción sigue el tratamiento estándar de Rails, porque es un bug y no un error del proveedor.

### D8. Peticiones HTTP reales bloqueadas en la suite: WebMock

**Alcance.** WebMock intercepta peticiones HTTP hechas con las bibliotecas que adapta, entre ellas Net::HTTP, que es lo que usa `faraday-net_http`. El bloqueo cubre exactamente eso. **No** es un aislamiento de red general: no controla sockets abiertos directamente, la resolución DNS ni otras conexiones del sistema operativo. Por eso este cambio no afirma que la suite se haya probado sin Internet a nivel del sistema; solo afirma que corre con el bloqueo de WebMock habilitado y sin peticiones HTTP reales a través de esas bibliotecas.

- Se agrega `gem "webmock", "~> 3.34", group: :test`.
- En `spec/rails_helper.rb` van `require "webmock/rspec"` y `WebMock.disable_net_connect!`, explícito aunque WebMock ya lo haga por defecto. No se permite ni `localhost`: los request specs usan Rack::Test y no abren sockets.
- Las pruebas del cliente y del endpoint usan `stub_request(:get, "https://api.open-meteo.com/v1/forecast").with(query: { … })` con el conjunto **exacto** de claves y valores. Al comparar como hash, WebMock no depende del orden del query string; un parámetro de más, de menos o con otro valor rompe la prueba. Los timeouts se simulan con `to_raise(Net::OpenTimeout)` y `to_raise(Net::ReadTimeout)` sobre el adaptador real. Así se verifica la traducción de D3 contra el código verdadero de `faraday-net_http`.
- Un spec comprueba que una petición real sin stub lanza `WebMock::NetConnectNotAllowedError`. Durante la implementación se confirma que esa excepción no hereda de `StandardError`, de modo que ningún `rescue` de la aplicación la oculte. Si sí heredara, se agrega un spec que pruebe que el endpoint no la convierte en un 502.
- **Alternativa descartada:** `Faraday::Adapter::Test`. No ejercita el adaptador real, así que no habría probado el caso de `Net::OpenTimeout`.

### D9. Estrategia de pruebas

| Spec | Qué cubre |
|---|---|
| `spec/models/coordinates_spec.rb` | Formatos aceptados y rechazados, tipos, ausencia, vacío, límites y valores fuera de rango (con el caso `90.0000000000000000001`) |
| `spec/clients/open_meteo/client_spec.rb` | Claves y valores exactos de la consulta, sin importar el orden; 200 con objeto JSON; 200 con cuerpo que no es JSON y 200 con JSON que no es objeto (`[]`, `"ok"`) dan `InvalidResponse`; 3xx, 400 y 500 dan `HttpError`; 429 da `RateLimited`; `Net::ReadTimeout` y `Net::OpenTimeout` dan `Timeout`; `Errno::ECONNREFUSED` y `OpenSSL::SSL::SSLError` dan `Unavailable`; una sola petición por llamada |
| `spec/services/current_weather_fetcher_spec.rb` | Construcción de `CurrentWeather` con un cliente falso; `valid_at` `"2026-10-31T15:00:00Z"` para `"2026-10-31T15:00"`. Dan `InvalidResponse`: `current` o `current_units` ausentes, `null`, array, texto o booleano; campo faltante, `null`, número como texto o booleano; unidad distinta; `utc_offset_seconds` distinto de 0; fechas `2026-02-30T15:00`, `2026-13-01T15:00`, `2026-10-31T24:00` y `2026-10-31T15:60`, y fecha con otro formato. En ningún caso escapa `NoMethodError`, `TypeError` ni `ArgumentError` |
| `spec/requests/api/v1/weather_spec.rb` | El endpoint completo con WebMock: contrato 200, cada error con su status y `code`, que las entradas inválidas no hagan peticiones (`expect(a_request(…)).not_to have_been_made`), parámetros desconocidos y repetidos, que no se expongan textos externos, y al menos un caso de estructura inválida (`"current": null`) y uno de fecha imposible (`2026-02-30T15:00`) que responden 502 y no 500 |
| `spec/support/network_isolation_spec.rb` | Una petición HTTP con Net::HTTP sin stub queda bloqueada con `WebMock::NetConnectNotAllowedError` |

Los 5 ejemplos existentes se conservan sin cambios.

### D10. README, atribución y modificaciones

Se agrega la sección "Clima actual" con:
- El endpoint, un ejemplo de `curl` y una respuesta ilustrativa.
- La tabla de errores.
- La atribución con enlace a Open-Meteo y a CC BY 4.0.
- Las condiciones de uso no comerciales y sus límites, con la fuente y la fecha de consulta.
- La aclaración de que son datos de modelo y no observaciones.
- Las **modificaciones** aplicadas a los datos, que CC BY 4.0 obliga a indicar: se seleccionan temperatura y viento, la fecha se expresa en UTC con ISO 8601 y sufijo `Z`, y se reorganizan los campos. Los valores numéricos no se alteran.
- La comprobación manual real (D12).

### D11. Versiones: declarado frente a comprobado

| Componente | Declarado | Se comprueba con |
|---|---|---|
| `faraday ~> 2.15` (hoy 2.15.1) | Ruby `>= 3.0` | Suite en verde con Ruby 4.0.9; versión resuelta registrada; sin prereleases |
| `faraday-net_http` (hoy 3.5.0) | Ruby `>= 3.0.0`; `net-http ~> 0.5` | Suite en verde; versión resuelta y comportamiento de D3 probados con WebMock |
| `webmock ~> 3.34` (hoy 3.34.0) | Ruby `>= 2.6` | Spec de red bloqueada en verde con Ruby 4.0.9 |

Que una gem declare `>= 3.0` no prueba que funcione con Ruby 4.0.9. Si la 2.15.1 diera problemas, la alternativa es fijar `2.15.0`, registrando el motivo.

### D12. Evidencias, comprobación manual y verificación

- Rama `add-current-weather`. Evidencias en un directorio nuevo creado con `mktemp -d` dentro de `/home/pablo/clima-api-evidencias/` (es persistente). La ruta se anota en el registro.
- Instantánea previa (`sha256sum` de los archivos versionados), y al final se comprueba que solo cambiaron los archivos previstos: `Gemfile`, `Gemfile.lock`, `config/routes.rb`, `spec/rails_helper.rb` y `README.md`, además de los archivos nuevos.
- **Comprobación manual real, fuera de la suite:** con `bin/rails server`, ejecutar `curl -i "http://localhost:3000/api/v1/weather?latitude=-37.32&longitude=-59.13"` y un caso inválido. Se registran la fecha, el status, el cuerpo y que los valores coincidan en forma con el contrato. Son pocas llamadas, muy por debajo de los límites del proveedor.
- **Fallos deliberados esperados:** en el ciclo de prueba primero, cada spec nuevo se ejecuta antes de existir su código y tiene que fallar por la razón prevista (por ejemplo, una constante sin definir). Ese fallo se registra con su mensaje y se continúa. Si un fallo deliberado no ocurre, u ocurre por otra causa, se trata como fallo inesperado.
- **Fallos inesperados:** detenerse, registrar y conservar el estado, como en el cambio anterior. Sin `git clean` general.

### D13. Matriz de verificación

Niveles: **Local**, **Inspección**, **Manual real** (Open-Meteo de verdad, fuera de la suite) y **Remota** (GitHub Actions).

| ID | Verificación | Nivel |
|---|---|---|
| W1 | Consulta exitosa con contrato completo, coordenadas pedidas y del modelo, `valid_at` en UTC y `source` con `data_type: model` | Local (request spec) |
| W2 | Sin lenguaje de observación en la respuesta | Local |
| W3 | Atribución en la respuesta | Local |
| W4 | Atribución, licencia, condiciones y modificaciones en el README | Inspección |
| W5 | Formatos aceptados y rechazados, tipos, ausencia y vacío | Local |
| W6 | Rangos, límites, precisión decimal y redondeo a `Float` de `requested_coordinates` | Local |
| W7 | 400 con todos los `details` y sin petición al proveedor | Local |
| W8 | Parámetros desconocidos y repetidos | Local |
| W9 | Petición única con claves y valores exactos (sin importar el orden) y sin redirects | Local |
| W10 | Timeout de lectura y de conexión dan 504 | Local (adaptador real con WebMock) |
| W11 | 429 da 503 `provider_rate_limited` | Local |
| W12 | Conexión fallida, error TLS y HTTP de error dan 502 con su código | Local |
| W13 | Respuesta inválida del proveedor (campos, tipos, unidades) da 502 sin datos parciales | Local |
| W14 | Errores sin cuerpos externos ni mensajes internos | Local |
| W15 | Una petición HTTP con Net::HTTP sin stub queda bloqueada por WebMock | Local |
| W16 | Suite completa en verde con el bloqueo de WebMock habilitado, incluidos los 5 ejemplos previos | Local |
| W17 | `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit update` + `bin/bundler-audit` y `bin/ci` | Local |
| W18 | Comprobación manual contra Open-Meteo | Manual real |
| W19 | CI del PR en verde con el cambio | Remota |
| W20 | CI por push a `main` después del merge | Remota |
| W21 | Fechas imposibles del proveedor rechazadas sin normalizar; fecha válida en ISO 8601 UTC con segundos y `Z` | Local |
| W22 | `current` y `current_units` que no son objetos JSON (o el cuerpo que no es objeto) dan 502 y nunca 500 | Local |

## Risks / Trade-offs

- **[Open-Meteo cambia unidades, formato o campos]** → La validación estricta de D4 responde `provider_invalid_response` en lugar de datos erróneos. Es intencional: se prefiere fallar a mostrar valores mal interpretados.
- **[No hay tiempo total máximo]** → `read_timeout` limita cada lectura y no la petición completa, y el DNS no está acotado. Queda documentado y no se promete un total.
- **[Faraday 2.15.1 es reciente]** → La suite la valida con Ruby 4.0.9; la alternativa documentada es `2.15.0`.
- **[El texto de atribución es un ejemplo de la licencia, no una redacción obligatoria]** → Se usa ese ejemplo junto con los enlaces exigidos (Open-Meteo y la licencia), y el README indica las modificaciones.
- **[Límites por IP en CI compartido]** → La suite nunca llama al proveedor; solo lo hace la comprobación manual.
- **[El bloqueo de WebMock no es aislamiento de red]** → Cubre las bibliotecas que intercepta (Net::HTTP incluida), no sockets directos, DNS ni el sistema operativo. El alcance queda declarado en D8 y en la spec, y no se afirma una prueba sin Internet a nivel del sistema.
- **[`WebMock::NetConnectNotAllowedError` capturada por un `rescue` amplio]** → El cliente rescata solo clases de `Faraday`, y D8 exige comprobar la jerarquía durante la implementación.

## Migration Plan

1. Rama `add-current-weather` desde `main` (`d3b36f6`), instantánea y directorio de evidencias.
2. Implementación, pruebas y comprobación manual.
3. PR hacia `main`, CI en verde (W19), merge con `--merge` y CI por push a `main` (W20).
4. Archivar con `/opsx:archive` después de W20. No hay datos que migrar; para revertir alcanza con revertir el merge commit.

## Open Questions

Ninguna que bloquee. Las decisiones del usuario están incorporadas, y lo que se resolvió con un criterio propio (textos de `message` en inglés, `license_url` en `source`, el valor `"model"` de `data_type`) figura en D6 y puede ajustarse antes de implementar sin cambiar la estructura.

## Registro de evidencia

Se completa durante la implementación. Durante esa etapa, es la única sección de este documento que puede cambiar.

- Directorio de evidencias: `/home/pablo/clima-api-evidencias/add-current-weather.ALBYUm7H` (creado con `mktemp -d` el 2026-10-31; base `d3b36f6`, rama `add-current-weather`). Los nombres de archivo citados abajo son relativos a ese directorio. Línea de base: `bundle exec rspec`, 5 ejemplos y 0 fallos (`1.3-baseline-rspec.txt`).
- Versiones resueltas: faraday 2.15.1 · faraday-net_http 3.5.0 · net-http 0.10.0 · webmock 3.34.0 (addressable 2.9.1, crack 1.0.1, hashdiff 1.2.1, public_suffix 7.0.5) · bigdecimal 4.1.3. Sin prereleases en `Gemfile.lock` (`2.1-versions.txt`).
- Fallos deliberados esperados, registrados y continuados: 3.1 `NameError: uninitialized constant Coordinates` (`3.1-red.txt`); 4.1 `uninitialized constant OpenMeteo` (`4.1-red.txt`); 5.1 `uninitialized constant CurrentWeatherFetcher` (`5.1-red.txt`); 6.1 15 de 15 ejemplos en 404 por la ruta inexistente (`6.1-red-after-fix.txt`).
- Hallazgos y desvíos:
  - Las constantes asignadas dentro del bloque de `Data.define` (`DECIMAL_FORMAT`, `RANGES`) quedaban definidas en `Object` y no en `Coordinates`, por el ámbito léxico del bloque. Se corrigió definiendo `Coordinates = Data.define(...)` y reabriendo `class Coordinates`. Verificado antes (`true true false`) y después (`false false true`) en `3.2-constant-scope-fix.txt`.
  - En la primera corrida en rojo de 6.1, el ejemplo "does not use observation wording" pasaba sin probar nada, porque la página 404 tampoco contiene "observ". Se reforzó para exigir antes 200 y `data_type: model`; después fallaban los 15 ejemplos (`6.1-vacuous-test-fix.txt`).
  - Confirmado en ejecución con el adaptador real: `Net::OpenTimeout` llega como `Faraday::ConnectionFailed` (con `wrapped_exception` `Net::OpenTimeout`), `Net::ReadTimeout` como `Faraday::TimeoutError`, `Errno::ECONNREFUSED` como `ConnectionFailed` y `OpenSSL::SSL::SSLError` como `Faraday::SSLError`. La conexión por defecto tiene `open_timeout` 2, `read_timeout` 5 y `timeout` nil, con el adaptador `Faraday::Adapter::NetHttp` (`4.2-adapter-mapping.txt`).
  - `WebMock::NetConnectNotAllowedError` hereda directamente de `Exception`, no de `StandardError`, así que ningún `rescue` de la aplicación la oculta (`2.2-netconnect-ancestors.txt`).
  - El pedido de implementación mencionaba 22 tareas; el cambio tiene 20. Las 22 son las verificaciones W1 a W22.

| ID | Resultado | Comando o fuente | Fecha |
|---|---|---|---|
| W1 | Comprobado (local) | Request spec: contrato 200 completo, con coordenadas pedidas y del modelo, `valid_at` `2026-10-31T15:00:00Z` y `source` con `data_type: model` (`6.2-green.txt`) | 2026-10-31 |
| W2 | Comprobado (local) | Request spec: 200, `data_type: model` y ningún texto que contenga "observ" (reforzado según los hallazgos) | 2026-10-31 |
| W3 | Comprobado (local) | Request spec: `source` con `attribution`, `url`, `license` y `license_url` | 2026-10-31 |
| W4 | Comprobado (inspección) | README: endpoint, `curl`, respuesta ilustrativa, errores, atribución y licencia con enlaces, condiciones y límites con fuente y fecha, datos de modelo y modificaciones (`7.1-readme-inspection.txt`) | 2026-10-31 |
| W5 | Comprobado (local) | `coordinates_spec.rb`: formatos aceptados y rechazados, `invalid_type`, `missing` y `blank` (10 ejemplos, `3.2-green-after-fix.txt`) | 2026-10-31 |
| W6 | Comprobado (local) | `coordinates_spec.rb`: límites ±90 y ±180, `90.0000000000000000001` fuera de rango y redondeo a `Float` de `12.345678901234567890123` | 2026-10-31 |
| W7 | Comprobado (local) | Request spec: 400 con `details` de `latitude` y `longitude`, y `a_request(:get, /open-meteo/)` no realizado ante entradas inválidas | 2026-10-31 |
| W8 | Comprobado (local) | Request spec: `current` y `url` extra ignorados (petición única con la consulta exacta); `latitude=10&latitude=-37.32` usa `-37.32` | 2026-10-31 |
| W9 | Comprobado (local) | `client_spec.rb`: claves y valores exactos (hash de WebMock, sin orden); un parámetro extra no coincide con el stub; 301 no seguido; una sola petición también ante un 500 | 2026-10-31 |
| W10 | Comprobado (local) | Adaptador real con WebMock: `Net::ReadTimeout` y `Net::OpenTimeout` dan `Timeout` en el cliente y 504 `provider_timeout` en el endpoint (`4.2-green.txt`, `6.2-green.txt`) | 2026-10-31 |
| W11 | Comprobado (local) | Cliente: 429 da `RateLimited`; endpoint: 503 `provider_rate_limited` | 2026-10-31 |
| W12 | Comprobado (local) | `ECONNREFUSED` y `SSLError` dan `Unavailable` (502 `provider_unavailable`); 400, 500 y 301 dan 502 `provider_error` | 2026-10-31 |
| W13 | Comprobado (local) | Servicio: campos faltantes, `null`, texto, booleano, unidades distintas, offset distinto de 0 y coordenadas del modelo inválidas dan `InvalidResponse`; endpoint: 502 con `"temperature_2m": null` y solo la clave `error` | 2026-10-31 |
| W14 | Comprobado (local) | Request spec y cliente: las respuestas no contienen el `reason` del proveedor, `secret socket detail` ni `ECONNREFUSED` | 2026-10-31 |
| W15 | Comprobado (local) | `network_isolation_spec.rb`: `Net::HTTP.get_response` sin stub lanza `WebMock::NetConnectNotAllowedError`. Alcance: bibliotecas interceptadas por WebMock, no aislamiento de red del sistema | 2026-10-31 |
| W16 | Comprobado (local) | `bundle exec rspec`, una vez, con `WebMock.disable_net_connect!` en `rails_helper`: 55 ejemplos, 0 fallos, igual a la suma por archivo; incluye los 5 previos. No se ejecutó sin Internet a nivel del sistema (`8.1-rspec-full.txt`, `8.1-per-file.txt`) | 2026-10-31 |
| W17 | Comprobado (local) | `bin/rubocop` (32 archivos, sin ofensas), `bin/brakeman --no-pager` (0 advertencias), `bin/bundler-audit update` (`92c25ce`, 1290 avisos), `bin/bundler-audit` (sin vulnerabilidades) y `bin/ci` en verde (`8.2-*.txt`) | 2026-10-31 |
| W18 | Comprobado (manual real) | 2026-10-31 13:26 -03:00. `GET …latitude=-37.32&longitude=-59.13`: 200 con `temperature_celsius` 18.5, `wind_speed_kmh` 7.8, `valid_at` `2026-10-31T16:15:00Z` y `model_coordinates` `-37.2935, -59.08487`. `latitude=91`: 400 `out_of_range` en 0 ms. Se detuvo solo el servidor iniciado (pid 284821) (`8.3-manual-real.txt`) | 2026-10-31 |
| W19 | Pendiente (remota) | | |
| W20 | Pendiente (remota) | | |
| W21 | Comprobado (local) | Servicio: `2026-02-30T15:00`, `2026-13-01T15:00`, `2026-10-31T24:00` y `2026-10-31T15:60` dan `InvalidResponse`, sin normalizar; formatos distintos y valores que no son texto también. Endpoint: `2026-02-30T15:00` da 502, no 500. La fecha válida da `2026-10-31T15:00:00Z` | 2026-10-31 |
| W22 | Comprobado (local) | Servicio: `current` y `current_units` ausentes, `null`, `[]`, `"x"`, `true` o `1`, y un payload que no es objeto, dan `InvalidResponse`. Cliente: cuerpo `[]` o `"ok"` da `InvalidResponse`. Endpoint: `"current": null` da 502, no 500 | 2026-10-31 |
