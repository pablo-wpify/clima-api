# Tasks

Los comandos de verificación se ejecutan en `bash`, después de `nvm deactivate`. Las referencias `W*` remiten a la matriz D13.

**Fallos deliberados esperados:** en las tareas de prueba primero (3.1, 4.1, 5.1 y 6.1), el spec debe fallar antes de que exista el código, y por la razón indicada. Ese fallo se registra con su mensaje en el registro de evidencia y **se continúa**. Si no falla, o falla por otra causa, es un fallo inesperado.

**Fallos inesperados:** detenerse, registrar en el registro de evidencia de `design.md` y conservar el estado (D12).

## 1. Preparación

- [x] 1.1 Crear la rama `add-current-weather` desde `main` actualizado. Verificar que `git rev-parse --short HEAD` es `d3b36f6` (o el `main` vigente, que se registra), que el árbol solo muestra `openspec/changes/add-current-weather/` y que `ruby -v` es 4.0.9.
- [x] 1.2 Crear el directorio de evidencias con `mktemp -d /home/pablo/clima-api-evidencias/add-current-weather.XXXXXXXX`, guardar `sha256sum` de `git ls-files` y una copia de los artefactos del cambio, y anotar la ruta en el registro. Verificar que los archivos de la instantánea existen y no están vacíos.
- [x] 1.3 Ejecutar `bundle exec rspec` antes de cambiar nada. Verificar 5 ejemplos y 0 fallos, y registrarlo como línea de base.

## 2. Dependencias y bloqueo de peticiones HTTP

- [x] 2.1 Agregar `gem "faraday", "~> 2.15"` al grupo principal y `gem "webmock", "~> 3.34"` al grupo `:test`, y ejecutar `bundle install`. Verificar que `Gemfile.lock` resuelve faraday, faraday-net_http, net-http y webmock sin prereleases (comando de lectura de `Gemfile.lock` del cambio anterior), y registrar las versiones (D11).
- [x] 2.2 En `spec/rails_helper.rb`, agregar `require "webmock/rspec"` y `WebMock.disable_net_connect!`. Escribir `spec/support/network_isolation_spec.rb`, que hace una petición con Net::HTTP **sin stub** a `https://api.open-meteo.com/v1/forecast` y comprueba que lanza `WebMock::NetConnectNotAllowedError` (W15). Verificar con `bundle exec rspec spec/support` y registrar la jerarquía de esa excepción (`ancestors`) según D8. Registrar el alcance: esto prueba el bloqueo de las bibliotecas interceptadas por WebMock, no un aislamiento de red del sistema.
- [x] 2.3 Ejecutar `bundle exec rspec` con el bloqueo de WebMock habilitado desde `rails_helper`. Verificar que pasan los 5 ejemplos previos y el de petición bloqueada.

## 3. Coordenadas

- [x] 3.1 Escribir `spec/models/coordinates_spec.rb` con todos los casos de D5 y de los escenarios de formato, presencia y rango de la spec, incluidos `-0`, los límites ±90 y ±180, `90.0000000000000000001`, `latitude[]` (como `Array`), `latitude[a]` (como `ActionController::Parameters`) y el redondeo a `Float` de `12.345678901234567890123`. Ejecutarlo y registrar el fallo esperado por `Coordinates` sin definir; luego continuar.
- [x] 3.2 Implementar `app/models/coordinates.rb` (`Data.define(:latitude, :longitude)`, `.parse` y `Coordinates::Invalid` con `details`). Verificar que `bundle exec rspec spec/models/coordinates_spec.rb` pasa (W5 y W6).

## 4. Errores y cliente de Open-Meteo

- [x] 4.1 Escribir `spec/clients/open_meteo/client_spec.rb` con WebMock y las claves y valores exactos de D2, sin exigir orden en el query string: un 200 con un objeto JSON devuelve un `Hash`; un 200 con cuerpo que no es JSON y un 200 con JSON que no es objeto (`[]`, `"ok"`) dan `InvalidResponse`; 301, 400 y 500 dan `HttpError` y no se sigue el redirect; 429 da `RateLimited`; `Net::ReadTimeout` y `Net::OpenTimeout` dan `Timeout`; `Errno::ECONNREFUSED` y `OpenSSL::SSL::SSLError` dan `Unavailable`; una sola petición por llamada; ningún mensaje de error contiene el cuerpo ni el mensaje original. Ejecutarlo y registrar el fallo esperado por `OpenMeteo::Client` sin definir; luego continuar.
- [x] 4.2 Implementar `app/clients/open_meteo/error.rb` y `app/clients/open_meteo/client.rb` según D2 y D3, con conexión inyectable, `open_timeout: 2` y `read_timeout: 5`. Verificar que `bundle exec rspec spec/clients` pasa (W9, W10 y W11 a nivel de cliente; W12 y W14 parciales) y que `bin/rails runner 'p OpenMeteo::Client.new.instance_variable_get(:@connection).options.to_h.slice(:open_timeout, :read_timeout, :timeout)'` muestra `open_timeout` 2, `read_timeout` 5 y `timeout` nil.

## 5. Resultado y servicio

- [x] 5.1 Escribir `spec/services/current_weather_fetcher_spec.rb` con un cliente falso inyectado:
  - Un payload válido produce `CurrentWeather` con `model_coordinates`, y `"2026-10-31T15:00"` da `valid_at` `"2026-10-31T15:00:00Z"`.
  - **Estructura (W22):** `current` y `current_units` ausentes, `null`, `[]`, `"x"` o `true` dan `InvalidResponse`.
  - **Fecha estricta (W21):** `2026-02-30T15:00`, `2026-13-01T15:00`, `2026-10-31T24:00`, `2026-10-31T15:60` y una fecha con otro formato dan `InvalidResponse`, sin normalizarse a otro instante.
  - **Campos:** faltante, `null`, número como texto, booleano, unidad `°F`, `utc_offset_seconds` distinto de 0 y coordenadas del modelo fuera de rango dan `InvalidResponse`.
  - En ninguno de esos casos escapa `NoMethodError`, `TypeError` ni `ArgumentError`.

  Ejecutarlo y registrar el fallo esperado por `CurrentWeatherFetcher` sin definir; luego continuar.
- [x] 5.2 Implementar `app/models/current_weather.rb` y `app/services/current_weather_fetcher.rb` (`< ApplicationService`) según D1 y D4. Sin `rescue StandardError` (D4). Verificar que `bundle exec rspec spec/services` pasa, incluidos los 3 ejemplos previos de `ApplicationService` (W13, W21 y W22 a nivel de servicio).

## 6. Endpoint

- [x] 6.1 Escribir `spec/requests/api/v1/weather_spec.rb` con WebMock, cubriendo W1, W2, W3, W7, W8, W9, W10, W11, W12, W13 y W14 de punta a punta: contrato 200 completo con el ejemplo de D6 como fixture, cada error con su status y `code`, los `details` de varios campos, ninguna petición ante una entrada inválida, parámetros desconocidos y repetidos, que las respuestas de error no contengan textos del proveedor ni de excepciones, y que `"current": null` y `"time": "2026-02-30T15:00"` respondan 502 `provider_invalid_response` y no 500 (W21 y W22 de punta a punta). Ejecutarlo y registrar el fallo esperado por la ruta inexistente; luego continuar.
- [x] 6.2 Agregar la ruta en `config/routes.rb` e implementar `app/controllers/api/v1/weather_controller.rb` según D6 y D7. Verificar que `bundle exec rspec spec/requests` pasa, incluidos los 2 ejemplos previos de salud.

## 7. Documentación

- [x] 7.1 Agregar al README la sección "Clima actual" según D10: endpoint, `curl`, respuesta ilustrativa identificada como tal, tabla de errores, atribución y licencia con enlaces, condiciones de uso y límites con su fuente y fecha, datos de modelo frente a observaciones, modificaciones aplicadas y comprobación manual. Verificar por inspección (W4) que figuran todos esos elementos.

## 8. Verificación integral

- [x] 8.1 Ejecutar `bundle exec rspec` una vez, con el bloqueo de WebMock habilitado desde `rails_helper`. Verificar 0 fallos, que siguen presentes los 5 ejemplos previos y que la cantidad total coincide con la suma por archivo (W16). Registrar que la suite corrió con ese bloqueo, sin afirmar que se ejecutó sin Internet a nivel del sistema.
- [x] 8.2 Ejecutar `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit update`, `bin/bundler-audit` y `bin/ci`. Verificar que todos terminan con código 0 (W17).
- [x] 8.3 Comprobación manual real (W18): comprobar que el puerto 3000 está libre, levantar `bin/rails server` y ejecutar `curl -i "http://localhost:3000/api/v1/weather?latitude=-37.32&longitude=-59.13"` y `curl -i "http://localhost:3000/api/v1/weather?latitude=91&longitude=0"`. Verificar 200 con el contrato de D6 y 400 `invalid_parameters`, registrar la fecha y los cuerpos en las evidencias, y detener solo ese servidor.
- [x] 8.4 Comprobar la preservación (D12): los archivos versionados que no estaban previstos no cambiaron (`sha256sum -c` filtrado), y `git status` muestra solo los archivos esperados. Verificar código 0 y registrar.
- [x] 8.5 Completar el registro de evidencia con W1 a W18, W21 y W22. Dejar W19 y W20 como "Pendiente (remota)". Verificar que ninguna fila afirma una ejecución que no ocurrió.

## Workflow follow-up

- Commit en `add-current-weather`, PR hacia `main` y CI del PR en verde (W19). Registrar la URL, el SHA y los jobs.
- Merge con `--merge` y CI por push a `main` en verde (W20). Registrar.
- Archivar con `/opsx:archive add-current-weather`, sincronizando las specs `current-weather` (nueva) y `development-environment` (requisito agregado).
