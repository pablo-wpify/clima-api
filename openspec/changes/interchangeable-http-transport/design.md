# Diseño: transporte HTTP intercambiable y resultado del caso de uso del clima

## Context

Motivación: ver `proposal.md` (Why). Comportamiento exigido: `specs/http-transport/spec.md`, `specs/current-weather/spec.md` y `specs/development-environment/spec.md`.

**Estado de partida:**
- `main` en `b8ec1c9`, árbol limpio. Specs vigentes: `continuous-integration`, `current-weather`, `development-environment`, `health-check` y `service-objects`.
- Suite de 55 ejemplos; CI con `scan_ruby`, `lint` y `test`.
- `OpenMeteo::Client` construye una conexión Faraday (`open_timeout` 2, `read_timeout` 5, `Accept: application/json`) inyectable por `connection:` y traduce `Faraday::TimeoutError`, `Faraday::ConnectionFailed` (con `Net::OpenTimeout` envuelto), `Faraday::SSLError` y cualquier `Faraday::Error` a `OpenMeteo::Error::*`.
- `CurrentWeatherFetcher` lanza `OpenMeteo::Error::InvalidResponse`; el controller traduce `OpenMeteo::Error` con `rescue_from` y una tabla de clase a estado y código.
- `openspec/config.yaml` dice "Faraday para HTTP".

**Datos verificados el 2026-11-01** por inspección de fuentes y metadatos oficiales; HTTP.rb no se instaló ni se ejecutó. Evidencias en `/home/pablo/clima-api-evidencias/explore-transport.RvzPjcqH/`.

| Tema | Hecho | Fuente |
|---|---|---|
| Versión | `http` 6.0.4 (2026-07-14), Ruby `>= 3.2`; depende de `http-cookie ~> 1.0` y `llhttp ~> 0.6.1` | RubyGems API |
| Extensión nativa | `llhttp` compila C (`ext/llhttp/extconf.rb`); hay 0.6.2 (2026-06-28) | gema `llhttp` 0.6.1 |
| CI de HTTP.rb | Matriz `ruby-3.2`, `3.3`, `3.4`, `4.0`; no prueba 4.0.9 en particular | `.github/workflows/test.yml`, v6.0.4 |
| Seguridad | 6.0.4 corrige `GHSA-r98x-p6m8-xcrv` (`base_uri`/`persistent` con entradas `//host`) | `CHANGELOG.md` v6.0.4 |
| Timeouts | Sin timeouts por defecto (`Timeout::Null`). `HTTP.timeout(connect:, read:)` usa `PerOperation`: `connect` para TCP (nativo en Ruby >= 3.4) y handshake TLS; `read` por cada espera de lectura | `options.rb`, `timeout/null.rb`, `timeout/per_operation.rb` |
| Errores | `ConnectTimeoutError < TimeoutError < Error`; `ConnectionError` (y `SocketReadError`) para `IOError`, `SocketError`, `SystemCallError`; el timeout del handshake TLS lanza `TimeoutError`; `OpenSSL::SSL::SSLError` no se envuelve | `errors.rb`, `connection.rb`, `connection/internals.rb`, `timeout/*` |
| Lectura perezosa | El cuerpo se lee después de los encabezados, al pedirlo | `connection.rb#readpartial` |
| Redirects y reintentos | `follow: nil` y `retriable: nil` por defecto | `client.rb`, `options.rb` |
| WebMock + HTTP.rb | WebMock reemplaza `HTTP::Client#perform`, por encima de la traducción de errores; `to_raise(X)` lanza `X` tal cual; `to_timeout` lanza `HTTP::TimeoutError`; la respuesta simulada se construye sin pasar por el parser `llhttp` | webmock 3.34.0, `http_rb/*.rb` |
| Faraday | `faraday-net_http` 3.5.0 pone `max_retries = 0`; Net::HTTP reintentaría una vez los GET por defecto. `open_timeout` cubre TCP y handshake TLS | `net_http.rb:195`; net-http 0.10.0 `:1160`, `:2530`, `:1760` |
| WebMock + Faraday | WebMock intercepta en Net::HTTP, debajo de `faraday-net_http`: `to_raise(Net::OpenTimeout)` atraviesa la traducción real | webmock 3.34.0; suite actual (W10) |

## Goals / Non-Goals

**Goals:**
- Un límite claro entre comunicación (transporte), reglas del proveedor (cliente), validación y resultado (servicio) y HTTP público (controller), cada uno con una sola razón para cambiar.
- Que las respuestas y los fallos previstos no expongan tipos de Faraday ni de HTTP.rb, y que el cliente, el servicio y el controller no dependan de conexiones, respuestas ni excepciones de esas bibliotecas.
- Afirmar la intercambiabilidad solo con pruebas que la respalden, distinguiendo simulación, inspección de fuentes y comprobación real.

**Non-Goals:**
- Un cliente HTTP genérico: solo GET, sin cuerpo de petición, sin streaming, sin conexiones persistentes, sin redirects ni reintentos.
- Elegir el transporte en tiempo de ejecución, por configuración o por petición.
- Un tipo de resultado común para todos los servicios ni cambios en `ApplicationService`.
- Un límite de duración total de la petición.

## Decisions

### D1. Piezas y responsabilidades

```
Api::V1::WeatherController   params -> Coordinates.parse (400 como hoy)
   |                         CurrentWeatherResult -> JSON y estado HTTP
CurrentWeatherFetcher        valida el payload; OpenMeteo::Error -> CurrentWeatherResult.failure
   |
OpenMeteo::Client            URL, query, Accept; 2xx / 429 / otros; JSON objeto
   |                         HttpTransport::Timeout -> Error::Timeout
   |                         HttpTransport::ConnectionFailed -> Error::Unavailable
HttpTransport                get(url, params:, headers:) -> Response
   |-- FaradayTransport      Faraday + faraday-net_http
   `-- HttpRbTransport       HTTP.rb
```

Archivos: `app/clients/http_transport/{response,error,faraday_transport,http_rb_transport}.rb` (Zeitwerk crea el módulo `HttpTransport` desde el directorio) y `app/models/current_weather_result.rb`, junto a `CurrentWeather`.

### D2. Contrato del transporte

- `get(url, params:, headers:)`: `url` absoluta (String), `params` y `headers` como Hash de String a String. Solo GET.
- Devuelve `HttpTransport::Response = Data.define(:status, :body)`. El constructor exige `status` Integer entre 100 y 599 y `body` String; un cuerpo ausente se entrega como `""`.
- El cuerpo se lee por completo dentro del adaptador y dentro de su manejo de errores, antes de devolver la respuesta. Esto importa en HTTP.rb, que lee el cuerpo de forma perezosa.
- Fallos previstos: `HttpTransport::Error < StandardError`, con `Timeout` y `ConnectionFailed`, de mensaje fijo (mismo patrón que `OpenMeteo::Error`). La excepción original queda solo como `cause`.
- Errores inesperados: se propagan sin envolver y conservan su tipo original, aunque sea de la biblioteca. La prohibición de exponer tipos de biblioteca se refiere a las respuestas y a los fallos previstos del contrato, no a lo imprevisto.
- Los timeouts se reciben como argumentos obligatorios del constructor (`open_timeout:`, `read_timeout:`), sin valores por defecto escondidos en el adaptador. Ambos adaptadores exponen esos valores con `attr_reader` para poder comprobar la composición.
- Alternativas descartadas: un transporte como función (contrato y errores menos visibles) y el adaptador `faraday-http` (no encapsula cada biblioteca por separado y su traducción no fue inspeccionada).

### D3. Traducción por adaptador

Solo se traducen los fallos de comunicación previstos. Cualquier otra excepción se propaga sin envolver, con su tipo original.

| Situación | FaradayTransport rescata | HttpRbTransport rescata | Resultado |
|---|---|---|---|
| Timeout de lectura | `Faraday::TimeoutError` | `HTTP::TimeoutError` (no `ConnectTimeoutError`) | `Timeout` |
| Timeout de conexión o handshake TLS | `Faraday::ConnectionFailed` cuyo `wrapped_exception` es `Net::OpenTimeout` | `HTTP::ConnectTimeoutError`; `HTTP::TimeoutError` en el handshake | `Timeout` |
| Conexión rechazada, DNS, conexión cortada | resto de `Faraday::ConnectionFailed` | `HTTP::ConnectionError` (incluye `SocketReadError` y `SocketWriteError`) | `ConnectionFailed` |
| Error TLS | `Faraday::SSLError` | `OpenSSL::SSL::SSLError` | `ConnectionFailed` |

- **Cambio respecto de hoy:** el cliente actual traduce cualquier `Faraday::Error` a `Unavailable`. Sin middleware de errores ni de parseo, Faraday no lanza otras subclases en este uso, así que se acota a las de la tabla; otra subclase pasará a propagarse como error inesperado.
- `HttpRbTransport` usa `HTTP.timeout(connect:, read:)`, sin `follow` ni `retriable`, y lee el cuerpo con `response.to_s`; el estado se toma de `response.code`, que es Integer (`response.status` es un objeto).
- `FaradayTransport` construye `Faraday.new(request: { open_timeout:, read_timeout: })` sin middleware y sin URL base; `response.body.to_s`.

### D4. Cliente del proveedor y composición

- `OpenMeteo::Client.new(transport: self.class.default_transport)`. `default_transport` es el único punto de construcción: `HttpTransport::FaradayTransport.new(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)`, con las constantes actuales (2 y 5). Elegir HTTP.rb en producción significa cambiar esa línea; en las pruebas, inyectar la instancia.
- `CurrentWeatherFetcher` conserva `client: OpenMeteo::Client.new` como valor por defecto y no cambia por el transporte.
- El cliente sigue armando la URL (`https://api.open-meteo.com/v1/forecast`), la consulta y `Accept: application/json`; clasifica 2xx, 429 y el resto; exige un objeto JSON. Se elimina `attr_reader :connection` y toda referencia a Faraday.
- Alternativas descartadas: configuración de Rails o variables de entorno (selección dinámica innecesaria), contenedor de dependencias y elegir el transporte en el controller (pondría una decisión de infraestructura en la capa HTTP).

### D5. Resultado del caso de uso

- `CurrentWeatherResult = Data.define(:data, :error_code, :error_message)`, reabierto con `class CurrentWeatherResult` para declarar constantes, porque las constantes dentro del bloque de `Data.define` se filtran a `Object` (hallazgo del capítulo 2).
- `ERROR_CODES = %w[provider_timeout provider_rate_limited provider_unavailable provider_error provider_invalid_response].freeze`.
- `initialize(data:, error_code:, error_message:)` acepta solo dos formas y lanza `ArgumentError` con cualquier otra:
  - éxito: `data.is_a?(CurrentWeather)`, `error_code` y `error_message` `nil`;
  - fallo: `data` `nil`, `error_code` en `ERROR_CODES` y `error_message` String con contenido no vacío.
- `success?` devuelve `error_code.nil?` (siempre `true` o `false`). No se guarda un campo `success`.
- Fábricas `CurrentWeatherResult.success(weather)` y `.failure(code:, message:)`.
- Se comprueba que `with` y la construcción posicional pasan por las mismas validaciones.
- **Inmutabilidad superficial:** las invariantes se validan al construir. Como todo `Data`, el resultado impide reasignar sus miembros, pero los objetos que contiene no se congelan: los strings de `error_code` y `error_message` podrían modificarse después. En este cambio no se agrega congelación profunda ni se modifica el contrato.

### D6. Conversión a resultado en el servicio

- `CurrentWeatherFetcher#call` envuelve todo su trabajo en `rescue OpenMeteo::Error => e` y devuelve `CurrentWeatherResult.failure(code: CODES.fetch(e.class), message: e.message)`.
- `CODES` mapea cada subclase de `OpenMeteo::Error` a su código público. `fetch` hace que una subclase nueva sin código falle de forma visible (`KeyError`).
- Los mensajes son los fijos de `OpenMeteo::Error`, los mismos que la API devuelve hoy.
- Sin `rescue StandardError`: un `NoMethodError` u otro error inesperado se propaga.
- Alternativa descartada: códigos como símbolos internos mapeados en el controller (decisión: conservar los strings públicos).

### D7. Controller

- `show`: parsea coordenadas (sin cambios), llama al servicio y, si `result.success?`, serializa `result.data` como hoy; si no, `render status: STATUS_BY_CODE.fetch(result.error_code), json: { error: { code: result.error_code, message: result.error_message } }`.
- `STATUS_BY_CODE`: `provider_timeout` 504, `provider_rate_limited` 503 y los otros tres 502.
- Se quita `rescue_from OpenMeteo::Error`; se mantiene `rescue_from Coordinates::Invalid`.

### D8. Dependencias

- `gem "http", "~> 6.0", ">= 6.0.4"` en el grupo principal, junto a Faraday. Se exige 6.0.4 o superior por la corrección de seguridad, aunque el proyecto no use `base_uri` ni `persistent`.
- Declarado frente a comprobado: la compatibilidad con Ruby 4.0.9 y la compilación de `llhttp` se comprueban instalando en local (con el compilador registrado) y en el CI del PR. Que la gema declare `>= 3.2` no basta.
- README: prerrequisito de un compilador de C y `make` para `llhttp`.

### D9. Pruebas

- **Contrato compartido** (`spec/support/http_transport_contract.rb`, cargado explícitamente por cada spec de adaptador): estado y cuerpo; cuerpo vacío como `""`; 301, 400, 429 y 500 como respuestas; 301 sin petición al `Location`; una sola petición recibida también ante 500 y ante un timeout; un único intento ante conexión rechazada; query y `Accept` exactos; tipos propios para respuestas y fallos previstos.
- **Qué cuenta WebMock como petición:** registra cada intento, aunque un `to_raise` simule que ningún servidor recibió nada. En los fallos de conexión, "una vez" en WebMock significa un único intento, no una petición HTTP enviada; la recepción real solo se observa en el grupo local (D10).
- **Simulación según la biblioteca**, con un `let` por adaptador que define cómo provocar cada fallo:
  - Faraday: `to_raise(Net::ReadTimeout)`, `to_raise(Net::OpenTimeout)`, `to_raise(Errno::ECONNREFUSED)` y `to_raise(OpenSSL::SSL::SSLError)`. Atraviesan la traducción real de `faraday-net_http`.
  - HTTP.rb: `to_raise(HTTP::TimeoutError)`, `to_raise(HTTP::ConnectTimeoutError)`, `to_raise(HTTP::ConnectionError)` y `to_raise(OpenSSL::SSL::SSLError)`. **Solo prueban el mapeo del adaptador**: que HTTP.rb produzca esas excepciones en cada situación real se respalda con la inspección de fuentes y con el grupo local (D10).
  - Errores inesperados: `to_raise(ArgumentError)` en ambos se propaga sin traducir y con su clase original.
- **Cliente** con un transporte falso (objeto propio con `get`): sin WebMock ni bibliotecas HTTP.
- **Servicio** con un cliente falso: resultados en lugar de `raise_error`; un error inesperado se propaga.
- **Endpoint**: las expectativas del contrato HTTP de `spec/requests/api/v1/weather_spec.rb` (estados, cuerpos, códigos, `details`, ausencia de petición ante entrada inválida) **no cambian**. Lo que sí se adapta son las simulaciones, porque cambia el límite del transporte:
  - Mientras Faraday es el único transporte (grupo 4 de tareas), las request specs existentes se ejecutan sin cambios: sus `to_raise(Net::…)` siguen siendo válidos porque WebMock intercepta debajo de `faraday-net_http`.
  - Al agregar HTTP.rb (grupo 5), las expectativas pasan a ejemplos compartidos y cada transporte aporta su simulación de fallos: Faraday conserva `Net::…`; HTTP.rb usa las excepciones de HTTP.rb (D9). **No se exige** que las simulaciones basadas en `Net::…` funcionen con HTTP.rb: con WebMock lanzarían `Net::…` tal cual por encima del adaptador, algo que HTTP.rb real no hace.
  - El transporte se inyecta con `allow(OpenMeteo::Client).to receive(:default_transport)` devolviendo la instancia.
  - Que las expectativas no cambiaron se comprueba comparando, antes y después, las líneas `expect` y los valores esperados (no las simulaciones).
- **Bloqueo**: `network_isolation_spec.rb` agrega una petición HTTP.rb sin stub que debe lanzar `WebMock::NetConnectNotAllowedError`, para comprobar que el adaptador de WebMock para HTTP.rb quedó activo.

### D10. Grupo local contra 127.0.0.1

- `spec/loopback/http_transport_loopback_spec.rb`, con la etiqueta `loopback: true`, excluida por defecto con `config.filter_run_excluding loopback: true`. Se ejecuta con `bundle exec rspec --tag loopback spec/loopback`. Se comprueba que el comando documentado ejecuta 0 ejemplos de este grupo y que el comando separado los ejecuta.
- **Servidor y disponibilidad.** `TCPServer.new("127.0.0.1", 0)` se crea en el hilo del ejemplo, así que ya escucha antes de lanzar el hilo que atiende. Ese hilo publica en una `Thread::Queue` que está listo y, después, cada conexión aceptada. El ejemplo espera la señal de disponibilidad con `pop(timeout: 1)` antes de hacer la petición; si no llega, falla con un mensaje explícito, sin hacer la petición.
- **Permiso de red.** WebMock permite solo `127.0.0.1:<puerto>` durante cada ejemplo (`WebMock.disable_net_connect!(allow: "127.0.0.1:#{port}")`) y restaura `WebMock.disable_net_connect!` en un `ensure`.
- **Tiempos.** `open_timeout: 1` y `read_timeout: 0.5`. La duración se mide con `Process.clock_gettime(Process::CLOCK_MONOTONIC)`, no con `Time.now`. Se exige que el timeout ocurra después de al menos 0,4 s y antes de 2 s.
- **Resguardo y limpieza acotada.** Un `around` aborta el ejemplo a los 5 s. La limpieza está en `ensure` y no puede bloquearse aunque venza el resguardo: cerrar los sockets aceptados y el servidor (operaciones que no esperan), `Thread#kill` y `join(1)`. Si `join(1)` devuelve `nil`, el ejemplo falla informando el hilo que quedó vivo.
- **Comprobación de limpieza.** Se verifica sobre los recursos creados por el propio ejemplo, que se guardan en variables: el servidor está cerrado (`closed?`), cada socket aceptado está cerrado y el hilo ya no vive (`alive?` falso). Como evidencia adicional, `ss -ltnp` filtrado por el puerto registrado y el PID del proceso de pruebas no muestra un servidor escuchando. No se compara el estado global de `ss` antes y después.
- **Escenarios, para cada adaptador:**
  1. el servidor acepta y no envía nada: `Timeout`;
  2. el servidor envía encabezados con `Content-Length: 100` y 10 bytes de cuerpo, y se detiene: `Timeout`, sin respuesta parcial;
  3. conexión a un puerto cerrado: `ConnectionFailed`. El puerto se obtiene abriendo un `TCPServer` en el puerto 0, leyendo el número y cerrándolo. **Hay una carrera pequeña:** entre el cierre y la conexión, otro proceso podría ocupar ese puerto, y entonces el resultado no sería una conexión rechazada. Se conserva esta estrategia; no se adopta otra técnica de reserva del puerto en este cambio. Si aparece evidencia de interferencia en ese puerto (por ejemplo, otro proceso aceptando la conexión), se registra como **problema del montaje de prueba**, no como fallo del transporte, y sin reintentar automáticamente.
- Estos ejemplos sí usan el parser `llhttp` de HTTP.rb sobre bytes reales.
- **Alcance del contador de peticiones:** el hilo del servidor atiende una conexión y queda bloqueado en ella, así que otras conexiones podrían quedar pendientes sin aceptar y no se contarían. El contador no demuestra por sí solo la ausencia de reintentos; esa garantía se apoya además en las pruebas simuladas (WebMock registra un solo intento) y en la configuración inspeccionada (`max_retries = 0` en faraday-net_http; HTTP.rb sin `retriable`).
- **Límites registrados:** no demuestran el timeout de conexión (requiere un destino que no responda al SYN, dependiente de la red), ni el timeout o los errores del handshake TLS, ni la cobertura de DNS. Esos casos quedan respaldados solo por la inspección de fuentes y la simulación del mapeo.

### D11. Comprobación real

- Fuera de la suite, con `bin/rails runner`, una consulta a Open-Meteo con cada transporte para `-37.32, -59.13`:
  - con `CurrentWeatherFetcher` y el transporte inyectado en `OpenMeteo::Client`, para el resultado del caso de uso;
  - con una sesión de integración (`ActionDispatch::Integration::Session`) sobre `/api/v1/weather`, reemplazando `OpenMeteo::Client.default_transport` solo dentro de ese proceso, para obtener la respuesta pública completa con cada transporte.
- **Qué se verifica, con cada transporte, contra el contrato vigente:** HTTP 200; exactamente las claves del contrato; `temperature_celsius` y `wind_speed_kmh` numéricos; `requested_coordinates` y `model_coordinates` con `latitude` y `longitude` numéricas en rango; `valid_at` en ISO 8601 UTC con segundos y `Z`, que representa un instante válido; `source` con `provider` `Open-Meteo`, `data_type` `model`, atribución y licencia. Las unidades quedan verificadas porque el servicio rechaza otras.
- **Qué no se exige:** valores meteorológicos ni `valid_at` iguales entre las dos consultas, ni un minuto particular. Las diferencias de datos entre consultas se registran, sin considerarlas automáticamente un fallo de intercambiabilidad.
- Además, `curl` al endpoint con el transporte predeterminado (200 y 400), como en el cambio anterior.
- El procedimiento queda en el README.

### D12. Evidencias, preservación y fallos

- Directorio nuevo con `mktemp -d /home/pablo/clima-api-evidencias/interchangeable-http-transport.XXXXXXXX`; nunca se sobrescriben evidencias anteriores.
- Instantánea `sha256sum` de `git ls-files` al empezar; al final, los archivos no previstos no cambiaron.
- **Fallos deliberados esperados:** en las tareas de prueba primero, el spec debe fallar antes del código y por la razón indicada; se registra y se continúa. Un fallo distinto, o la ausencia de fallo, es un fallo inesperado: detenerse, registrar y conservar el estado.

### D13. Matriz de verificación

| ID | Qué se verifica | Tipo |
|---|---|---|
| T1 | `Gemfile.lock` resuelve `http` >= 6.0.4, `llhttp`, `http-cookie` y dependencias, sin prereleases; versiones registradas | Local |
| T2 | Con Ruby 4.0.9 en local, tres hechos registrados por separado: (a) **instalación**: `bundle install` muestra `Installing llhttp … with native extensions`, que acredita el paso de instalación de extensiones y no basta por sí sola para afirmar compilación; (b) **compilación observada**: solo si se conserva la salida del compilador o el registro de construcción de la extensión (`gem_make.out` y, si existe, `mkmf.log` en el directorio de extensiones de `llhttp`); (c) **carga**: `require "http"` funciona. Si solo constan instalación y carga, se describe exactamente eso; si se reutilizó una compilación previa, la compilación queda "No observada" | Local |
| T3 | Peticiones sin stub con Net::HTTP y con HTTP.rb bloqueadas por WebMock | Local |
| T4 | Contrato compartido en verde con `FaradayTransport` (en las simulaciones, WebMock cuenta intentos) | Local (simulado) |
| T5 | Contrato compartido en verde con `HttpRbTransport` | Local (simulado) |
| T6 | Mapeo de fallos de Faraday a través de `faraday-net_http` real | Local (simulado bajo el adaptador) |
| T7 | Mapeo de fallos de HTTP.rb (solo mapeo) | Local (simulado sobre el adaptador) |
| T8 | Errores inesperados se propagan con su tipo original en adaptadores, cliente y servicio | Local |
| T9 | Cliente con transporte falso: URL, query, `Accept`, estados, JSON y traducción de errores | Local |
| T10 | Invariantes de `CurrentWeatherResult` y `success?` booleano | Local |
| T11 | Servicio con cliente falso: éxito, cinco fallos con código y mensaje exactos, validaciones como `provider_invalid_response` | Local |
| T12 | Contrato HTTP del endpoint con Faraday, con las expectativas sin cambios | Local (request spec) |
| T13 | Contrato HTTP del endpoint con HTTP.rb, con las mismas expectativas y simulaciones propias de HTTP.rb | Local (request spec) |
| T14 | Composición: transporte predeterminado Faraday con 2 s y 5 s; parámetro HTTP extra no cambia el transporte | Local |
| T15 | Grupo `loopback` excluido del comando documentado y ejecutable con el separado | Local |
| T16 | Timeout de lectura sin respuesta, con ambos adaptadores, en 127.0.0.1, medido con reloj monotónico | Local real (loopback) |
| T17 | Timeout de lectura con cuerpo demorado tras los encabezados, con ambos adaptadores, medido con reloj monotónico | Local real (loopback) |
| T18 | Conexión rechazada en 127.0.0.1, con ambos adaptadores (con la carrera de reserva del puerto registrada) | Local real (loopback) |
| T19 | Suite completa en verde con el bloqueo; total igual a la suma por archivo; los 55 escenarios previos siguen cubiertos | Local |
| T20 | `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit update` + `bin/bundler-audit` y `bin/ci` | Local |
| T21 | Consulta real a Open-Meteo con cada transporte contra el contrato vigente (D11), diferencias de datos registradas, y `curl` al endpoint | Manual real |
| T22 | Preservación de archivos no previstos y `git status` esperado | Local |
| T23 | README (prerrequisitos, arquitectura, timeouts y límites, comprobación real, comando del grupo local) y `openspec/config.yaml` actualizados | Inspección |
| T24 | CI del PR en verde: instalación y carga de las dependencias y suite con Ruby 4.0.9 (versión leída en el log de `setup-ruby`) | Remota |
| T25 | CI por push a `main` después del merge | Remota |
| T26 | `llhttp` en el runner, con el log del paso `setup-ruby` de la primera ejecución del PR. Se registra uno de tres estados: **compilación observada** solo si el log contiene la salida del compilador o del registro de construcción; **instalación observada, compilación no observada** si solo aparece `Installing llhttp … with native extensions`; **no observada (caché)** si el bundle se restauró de caché. No se modifica el CI ni se vacían cachés para forzar esta evidencia, y el CI en verde no basta para marcarla comprobada | Remota |
| T27 | Encapsulamiento: el cliente, el servicio y el controller no dependen de conexiones, respuestas ni excepciones de Faraday o HTTP.rb; las clases de los adaptadores solo aparecen en el punto de composición, las pruebas y la documentación | Inspección + local |

## Risks / Trade-offs

- [Pruebas simuladas de HTTP.rb que parecen probar más de lo que prueban] → D9 documenta que solo prueban el mapeo; el grupo local (D10) y la consulta real (D11) usan HTTP.rb de verdad.
- [La extensión nativa `llhttp` no compila en algún entorno] → T2 en local y T24 en CI antes de afirmar compatibilidad; prerrequisito en el README.
- [Codificación del cuerpo: HTTP.rb usa el `charset` de la respuesta y Faraday entrega bytes de Net::HTTP] → el cliente parsea con `JSON.parse`, que convierte a UTF-8; T21 compara las unidades `°C` y `km/h` con ambos.
- [Codificación de la coma en `current=temperature_2m,wind_speed_10m` distinta entre bibliotecas] → WebMock compara la consulta decodificada; T21 confirma que Open-Meteo acepta la forma de cada biblioteca.
- [Acotar la traducción de Faraday a las clases de la tabla] → otra subclase de `Faraday::Error` pasaría a ser un 500 visible en lugar de un 502; es el comportamiento buscado para lo imprevisto.
- [Timeouts que no son un límite total] → documentado; una petición puede tardar más de 7 s si el servidor envía datos lentamente.
- [Grupo local inestable por tiempos] → sincronización explícita de disponibilidad, reloj monotónico, márgenes amplios (0,5 s de límite contra 2 s de tolerancia), resguardo de 5 s y limpieza acotada en `ensure`.
- [Carrera al reservar y liberar el puerto de la conexión rechazada] → ventana pequeña reconocida; la interferencia observada se registra como problema del montaje de prueba, no del transporte, sin reintento automático.
- [La caché de `bundler-cache` puede ocultar la compilación de `llhttp` en CI, y el log por defecto no muestra la salida del compilador] → T26 distingue compilación observada, instalación observada y no observada; es probable que en CI solo se pueda afirmar la instalación. No se cambia el CI para obtener más evidencia.
- [`--tag loopback` no anule la exclusión configurada] → T15 lo comprueba; si falla, es un fallo inesperado y se detiene para decidir.
- [Dos bibliotecas HTTP en producción] → más superficie de dependencias y auditoría; `bundler-audit` cubre ambas (T20).

## Migration Plan

Sin datos ni API pública que migrar. Se integra con un PR y merge con historia preservada, como en los cambios anteriores. Reversión: revertir el merge; la API vuelve al cliente Faraday con excepciones.

## Open Questions

Ninguna que cambie specs, enfoque o tareas.

## Registro de evidencia

Directorio de evidencias: `/home/pablo/clima-api-evidencias/interchangeable-http-transport.ecuM9c9A/` (creado en 1.2; pedido literal del apply en `00-pedido-literal.md`).

| ID | Estado | Evidencia | Fecha |
|---|---|---|---|
| T1 | Comprobado (local) | `Gemfile.lock`: http 6.0.4, llhttp 0.6.2, http-cookie 1.1.6, domain_name 0.7.20261007; sin prereleases (`2.4-T1-versiones.txt`) | 2026-11-01 |
| T2 | Comprobado (local): instalación, compilación observada y carga | (a) `Installing llhttp 0.6.2 with native extensions` (`2.1-bundle-install.txt`); (b) `gem_make.out` conservado: `compiling http.c`, `api.c`, `llhttp.c`, `llhttp_ext.c` y `linking shared-object llhttp_ext.so`, en el directorio temporal `.gem.20261101-…` de esta instalación, más `mkmf.log` con las pruebas de `gcc` (`2.4-T2-build/`); no había `llhttp` instalado antes; (c) `require "http"`: HTTP 6.0.4, Ruby 4.0.9, `LLHttp::Parser` definido; (d) gcc 11.4.0, GNU Make 4.3 (`2.4-T2-carga-compilador.txt`) | 2026-11-01 |
| T3 | Comprobado (local) | Net::HTTP y HTTP.rb sin stub lanzan `WebMock::NetConnectNotAllowedError` (`2.3-network-isolation.txt`). Alcance: bibliotecas interceptadas por WebMock, no aislamiento de red del sistema | 2026-11-01 |
| T4 | Comprobado (local, simulado) | `FaradayTransport`: 12 ejemplos del contrato compartido más 2 de configuración; en las simulaciones de fallo, WebMock cuenta intentos (`3.6-transport.txt`, `8.1-rspec-full.txt`) | 2026-11-01 |
| T5 | Comprobado (local, simulado) | `HttpRbTransport`: 12 ejemplos del contrato compartido más 1 de configuración (`3.6-transport.txt`) | 2026-11-01 |
| T6 | Comprobado (local, simulado bajo el adaptador) | `Net::ReadTimeout` y `Net::OpenTimeout` dan `Timeout`; `Errno::ECONNREFUSED` y `OpenSSL::SSL::SSLError` dan `ConnectionFailed`, a través de `faraday-net_http` real | 2026-11-01 |
| T7 | Comprobado (local): solo mapeo | `HTTP::TimeoutError`, `HTTP::ConnectTimeoutError` dan `Timeout`; `HTTP::ConnectionError` y `OpenSSL::SSL::SSLError` dan `ConnectionFailed`. Simulados por encima de la traducción de HTTP.rb; que HTTP.rb los lance en situaciones reales se respalda con la inspección de fuentes y con T16–T18 | 2026-11-01 |
| T8 | Comprobado (local) | `ArgumentError` se propaga con su clase en ambos adaptadores; `RuntimeError` del transporte se propaga en el cliente; `NoMethodError` del cliente se propaga en el servicio | 2026-11-01 |
| T9 | Comprobado (local) | Cliente con transporte falso: URL, query y `Accept` exactos, una llamada, 2xx, JSON inválido o no objeto, 301/400/500, 429, Timeout, ConnectionFailed y mensajes fijos (11 ejemplos) | 2026-11-01 |
| T10 | Comprobado (local) | `CurrentWeatherResult`: 10 ejemplos; `success?` exactamente `true`/`false`; rechazo de combinaciones inválidas, también por construcción posicional y `with`; `ERROR_CODES` no se filtra a `Object` (`5.2-constants.txt`) | 2026-11-01 |
| T11 | Comprobado (local) | Servicio con `instance_double`: éxito; los 5 fallos previstos con código y mensaje exactos; validaciones como `provider_invalid_response`; `NoMethodError` se propaga (17 ejemplos) | 2026-11-01 |
| T12 | Comprobado (local, request spec) | Contrato HTTP con Faraday: 15 ejemplos, expectativas sin cambios (`5.4-conclusion.txt`, `5.7-models-services-requests.txt`) | 2026-11-01 |
| T13 | Comprobado (local, request spec) | Contrato HTTP con HTTP.rb: los mismos 15 ejemplos y expectativas, con simulaciones de HTTP.rb | 2026-11-01 |
| T14 | Comprobado (local) | `default_transport` es `FaradayTransport` con 2 y 5; Faraday sin timeout total; `transport=http_rb` en la consulta no cambia el transporte | 2026-11-01 |
| T15 | Comprobado (local) | `--tag loopback` anula la exclusión ("Run options: include {loopback: true}"); el comando documentado ejecuta 0 ejemplos del grupo (`6.3-T15.txt`) | 2026-11-01 |
| T16 | Comprobado (local real, loopback) | Sin respuesta: Faraday 0,509 s y HTTP.rb 0,505 s con lectura de 0,5 s, reloj monotónico; el servidor recibió 1 petición (`6.3-loopback.txt`). El contador no prueba por sí solo la ausencia de reintentos (ver D10) | 2026-11-01 |
| T17 | Comprobado (local real, loopback) | Cuerpo detenido tras los encabezados: Faraday 0,503 s y HTTP.rb 0,504 s; sin respuesta parcial; 1 petición. Hallazgo corregido: HTTP.rb dejaba el socket del cliente en `CLOSE-WAIT` (`6.1-loopback-intento2.txt`); se usa la forma con bloque de `get` | 2026-11-01 |
| T18 | Comprobado (local real, loopback) | Puerto cerrado: `ConnectionFailed` con ambos (0,001 s). Puerto reservado y liberado; sin interferencia observada. Límites: sin evidencia del timeout de conexión, del handshake TLS ni de DNS | 2026-11-01 |
| T19 | Comprobado (local) | `bundle exec rspec`: 117 ejemplos, 0 fallos, igual a la suma por archivo; los 55 escenarios de la línea de base cubiertos o reemplazados (`8.1-correspondencia.md`) | 2026-11-01 |
| T20 | Comprobado (local) | `bin/rubocop` (45 archivos, sin ofensas), `bin/brakeman --no-pager` (0 advertencias), `bin/bundler-audit update` (92c25ce, 1290 avisos), `bin/bundler-audit` (sin vulnerabilidades, incluye http y llhttp) y `bin/ci` en verde | 2026-11-01 |
| T21 | Comprobado (manual real) | 9 consultas reales reconstruidas desde los registros en `pr-transport.b0jQxpGq/02-consultas-reales-reconstruidas.md` (4 del primer intento, 4 de la repetición y 1 del `curl`). 2026-11-01 10:42 -03:00: con Faraday y con HTTP.rb, resultado exitoso y respuesta 200 con el contrato vigente (claves, tipos, coordenadas, `valid_at` `2026-11-01T13:30:00Z`, `source`); sin diferencias de datos entre las consultas (`7.2-contrato-verificado.txt`). `curl`: 200 y 400 `invalid_parameters` (`7.2-curl.txt`) | 2026-11-01 |
| T22 | Comprobado (local) | 84 archivos no previstos sin cambios; `git status` con 12 modificados y 7 rutas nuevas esperadas (`8.3-*.txt`) | 2026-11-01 |
| T23 | Comprobado (inspección) | README: prerrequisito, bloqueo con HTTP.rb, grupo local, único intento, tiempos de espera, comprobación con cada transporte y arquitectura; tabla de errores y respuesta ilustrativa sin cambios. `openspec/config.yaml`: solo la línea "Stack" (`8.3-T23-inspeccion.txt`) | 2026-11-01 |
| T27 | Comprobado (inspección + local) | Cliente, servicio y controller sin dependencias de Faraday ni HTTP.rb; la única referencia a un adaptador está en `default_transport` (`5.7-T27-encapsulamiento.md`) | 2026-11-01 |
| T24 | Pendiente (remota) | — | — |
| T25 | Pendiente (remota) | — | — |
| T26 | Pendiente (remota) | No se marca hasta revisar el log del runner | — |

**Desvíos y hallazgos de la implementación** (detalle en `notas-registro.md` del directorio de evidencias):
- D1: `HttpTransport::Timeout` y `HttpTransport::ConnectionFailed` están en `timeout.rb` y `connection_failed.rb`, además de `error.rb`. Zeitwerk no exige un archivo por clase, pero deriva de cada archivo **una** constante esperada (`error.rb` → `HttpTransport::Error`) y solo esa queda registrada para carga automática. Si las otras dos fueran constantes hermanas definidas en `error.rb`, una referencia a `HttpTransport::Timeout` funcionaría solo si `error.rb` ya se hubiera cargado por otra vía. Ese orden puede diferir entre local (`config.eager_load` falso en test) y CI (`ENV["CI"]` lo activa). `OpenMeteo` evita el problema anidando las subclases dentro de `Error`; aquí las clases son hermanas en el espacio de nombres, por la spec, y por eso van en archivos propios. La decisión fue preventiva: no se reprodujo un fallo. Evidencia: `cpath_expected_at` de cada archivo y `bin/rails zeitwerk:check` ("All is good!") en `pr-transport.b0jQxpGq/01-zeitwerk-evidencia.txt`.
- D2/D3: `HttpRbTransport` usa la forma con bloque de `get`, que cierra la conexión aunque falle la lectura del cuerpo. El grupo local mostró que sin ella un timeout en el cuerpo dejaba el socket del cliente en `CLOSE-WAIT`.
- D9: se agregó a la spec de `FaradayTransport` la aserción de que Faraday no tiene timeout total, que en la línea de base estaba en la spec del cliente.
- D10: la primera versión del grupo local tenía un error de montaje (manejadores definidos a nivel de grupo); se corrigió antes de registrar resultados.
- D11: el comando de comprobación real del README convertía a texto los números del resultado; se corrigió y se repitió la comprobación una vez por transporte.
- Intercambiabilidad: se afirma solo bajo el contrato de `http-transport` y los escenarios T4–T7, T12, T13 y T16–T21. No se afirma equivalencia general de las bibliotecas.
