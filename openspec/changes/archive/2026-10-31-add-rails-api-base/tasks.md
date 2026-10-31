# Tasks

Los comandos de verificación se ejecutan en una sesión `bash`, con `CHG=openspec/changes/add-rails-api-base` y `EVID` asignada a la ruta anotada en el registro de evidencia de `design.md`. Ante cualquier fallo se aplica D9: detenerse, registrar y conservar. Las filas `V*` corresponden a la matriz D11.

## 1. Preparación del entorno y evidencias

- [x] 1.1 Crear la rama `add-rails-api-base` desde `main` limpio. Verificar que `git branch --show-current` muestra `add-rails-api-base` y que `git status --porcelain` solo lista `openspec/changes/add-rails-api-base/`.
- [x] 1.2 Ejecutar `nvm deactivate` en la terminal de trabajo. Verificar que `ruby -v` muestra 4.0.9, `rails _8.1.4_ -v` muestra `Rails 8.1.4`, y que `RBENV_VERSION` y `rvm_ruby_string` están vacías.
- [x] 1.3 Crear el directorio de evidencias único con `mktemp -d` (D3). Verificar que la ruta impresa no existía antes, está fuera del repositorio y el directorio está vacío (`ls -A "$EVID"` sin salida).
- [x] 1.4 Tomar la instantánea inicial de D3. Verificar que `head`, `branch`, `gitconfig`, `preexisting.sha256` y `change-artifacts.initial.sha256` existen y no están vacíos; que `preexisting.sha256` incluye `.tool-versions` y `openspec/config.yaml`; y que `change-artifacts.initial.sha256` lista los 8 archivos del cambio (`.openspec.yaml`, `proposal.md`, `design.md`, `tasks.md` y las cuatro specs).
- [x] 1.5 Anotar en el registro de evidencia la ruta de `$EVID` y las versiones de Ruby, Rails y Bundler. Verificar que solo cambió esa sección, con la comparación 5 de la comprobación final de D3 (código 0 y sin salida).

## 2. Simulación y generación de Rails

- [x] 2.1 Ejecutar el comando de D1 con `--pretend`, guardando la salida con `set -o pipefail` y `2>&1 | tee "$EVID/pretend.log"`, y revisarla contra la lista de D2. Verificar que no hay `conflict`, `force`, `identical` ni `skip` sobre archivos preexistentes, que aparecen los `create` esperados y que no aparecen los archivos excluidos. Anotar si aparece `storage/`.
- [x] 2.2 Tomar la instantánea previa a la generación de D3 y, a continuación, ejecutar el comando de D1 sin `--pretend`, con salida en `"$EVID/generate.log"`. Verificar que termina con código 0 y que `bundle install` se completó sin errores.
- [x] 2.3 Inmediatamente después, ejecutar la comprobación posterior a la generación de D3 y la comprobación de estado de Git sin falsos fallos. Verificar que los checksums de preexistentes y de artefactos del cambio pasan, que la lista de archivos del cambio, la configuración de Git, `HEAD` y la rama no cambiaron, que nada desapareció, que la comprobación de estado imprime `OK` y que `"$EVID/generated-paths.txt"` existe.
- [x] 2.4 Si se generó `storage/`, eliminarlo junto con sus líneas de `.gitignore`. Verificar con `test ! -e storage`.
- [x] 2.5 Comprobar la ausencia de base de datos, de componentes excluidos y de una suite paralela (V2, V13). Verificar que `test ! -e config/database.yml && test ! -e db && test ! -e test && test ! -e Dockerfile && test ! -e config/deploy.yml && test ! -e app/jobs && test ! -e app/mailers && test ! -e .node-version` termina con código 0, y que en `config/application.rb` no queda activo ningún `require` de `active_record`, `active_job`, `action_mailer`, `action_cable` ni `active_storage`.
- [x] 2.6 Comprobar el arranque sin base de datos (V1). Verificar que `bin/rails runner 'p defined?(ActiveRecord)'` imprime `nil`, y que `RAILS_ENV=test bin/rails runner 'puts :ok'` imprime `ok`.

## 3. Versión de Ruby

- [x] 3.1 Agregar `ruby file: ".ruby-version"` al `Gemfile` y ejecutar `bundle install` (V6, V7). Verificar que `diff <(awk '$1=="ruby"{print $2}' .tool-versions) .ruby-version` no reporta diferencias, que el `Gemfile` no contiene la versión como literal y que `Gemfile.lock` contiene la sección `RUBY VERSION` con `ruby 4.0.9`.
- [x] 3.2 Verificar que Bundler rechaza otro Ruby (V8). `ASDF_RUBY_VERSION=3.4.7 bundle exec ruby -e 'puts RUBY_VERSION'` debe terminar con código distinto de 0 y lanzar `Bundler::RubyVersionMismatch` con un mensaje que mencione la discrepancia con 4.0.9. Como control, `bundle exec ruby -e 'puts RUBY_VERSION'` con Ruby 4.0.9 debe imprimir `4.0.9` y terminar con código 0. No usar `ruby -v`: imprime la versión y termina sin cargar `bundler/setup`, así que Bundler no llega a validar nada (con Ruby 3.4.7 devolvió código 0). Registrar el mensaje exacto en el registro de evidencia.

## 4. RSpec

- [x] 4.1 Agregar `gem "rspec-rails", "~> 8.0"` al grupo `:development, :test`, ejecutar `bundle install` y `bin/rails generate rspec:install`. Verificar que existen `.rspec`, `spec/spec_helper.rb` y `spec/rails_helper.rb`, y que `spec/rails_helper.rb` contiene `config.use_active_record = false`.
- [x] 4.2 Ejecutar el comando de versiones de D4. Verificar que termina con código 0 (sin prereleases en `Gemfile.lock`) y registrar en el registro de evidencia las versiones resueltas de `rspec-rails` y de cada `rspec-*`.
- [x] 4.3 Ejecutar `bundle exec rspec` con la suite vacía. Verificar que termina con código 0 y reporta `0 examples, 0 failures`, lo que comprueba que RSpec carga sin base de datos.

## 5. Ruta de salud

- [x] 5.1 Agregar `spec/requests/health_check_spec.rb` con `GET /up` → 200 y `GET` a una ruta inexistente → 404 (V4, V5). Verificar que `bundle exec rspec spec/requests` pasa con 2 ejemplos y 0 fallos.
- [x] 5.2 Comprobar la salud por HTTP real (V3) con `bin/rails server` y, en otra terminal, `curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/up`. Verificar que imprime `200`. Después detener el servidor.

## 6. ApplicationService

- [x] 6.1 Agregar `spec/services/application_service_spec.rb`, con una subclase anónima definida en el spec y un ejemplo por escenario de `service-objects`: reenvío del posicional, reenvío del keyword y retorno del mismo objeto (`equal`). Verificar que `bundle exec rspec spec/services` falla porque `ApplicationService` todavía no existe.
- [x] 6.2 Crear `app/services/application_service.rb` con únicamente `def self.call(...) = new(...).call`, sin `#call` abstracto ni `NotImplementedError`, y con `new` público (V14, V15, V16). Verificar que `bundle exec rspec spec/services` pasa con 3 ejemplos y 0 fallos.

## 7. Análisis estáticos y de seguridad

- [x] 7.1 Leer `bin/rubocop`, `bin/brakeman`, `bin/bundler-audit`, `config/bundler-audit.yml`, `config/ci.rb` y `.github/workflows/ci.yml` generados, y anotar en el registro de evidencia los comandos efectivos de cada lugar (V23, primera parte). Verificar que coinciden con la tabla de D8 o que toda diferencia es solo de presentación; si no, aplicar D9.
- [x] 7.2 Ejecutar en local `bin/rubocop`, `bin/brakeman --no-pager` y `bin/bundler-audit`, con salida en `$EVID`. Verificar que los tres terminan con código 0 y registrar las versiones de rubocop, brakeman y bundler-audit. Si alguno falla, registrar la causa (incluido `--ensure-latest` o falta de red) antes de corregir.

## 8. CI

- [x] 8.1 Agregar a `config/ci.rb` el paso `step "Tests: RSpec", "bundle exec rspec"` (V25). Verificar que `bin/ci` ejecuta setup, estilo, seguridad y RSpec, y termina con código 0. Registrarlo como ejecución local.
- [x] 8.2 Agregar a `.github/workflows/ci.yml` el job `test` (checkout, `ruby/setup-ruby@v1` con `bundler-cache: true` y sin `ruby-version`, `run: bundle exec rspec`) y conservar los jobs `scan_ruby` y `lint` (V17, V20, V21, V23). Verificar por inspección:
  - `ruby -ryaml -e 'w = YAML.load_file(".github/workflows/ci.yml"); puts w["jobs"].keys.sort; p(w[true] || w["on"])'` lista `lint`, `scan_ruby` y `test`, con los disparadores `pull_request` y `push` a `main`.
  - Ningún paso `setup-ruby` declara `ruby-version`. Comprobarlo con `grep -n 'ruby-version:' .github/workflows/ci.yml` tratando su código 1 (sin coincidencias) como el resultado esperado, 0 como fallo y 2 o más como error.
  - El `run` del job `test` es idéntico al comando de pruebas del README, y los comandos de análisis cumplen la tabla de D8.
  Registrar estas filas como inspección. No marcar como comprobadas las filas remotas.

## 9. README

- [x] 9.1 Reemplazar el README generado por uno que cumpla D13. Verificar ejecutando, uno por uno y tal como están escritos, todos los comandos del README desde el árbol de trabajo (V9 en el árbol de trabajo, V10): todos terminan con éxito y `/up` responde 200. La verificación desde un clon limpio queda para el seguimiento.

## 10. Verificación integral

- [x] 10.1 Ejecutar la suite completa con `bundle exec rspec` (V11). Verificar que reporta 5 ejemplos y 0 fallos, y que no existe el directorio `test/`.
- [x] 10.2 Comprobar que la suite detecta fallos (V12), sin usar Git para restaurar archivos sin seguimiento:
  1. Inmediatamente antes de tocarlo, copiar `spec/requests/health_check_spec.rb` a `"$EVID/health_check_spec.rb.before"` y guardar su huella con `sha256sum spec/requests/health_check_spec.rb > "$EVID/health_check_spec.sha256"`.
  2. Introducir un único fallo: cambiar el estado esperado de `/up` de 200 a 201.
  3. Ejecutar `bundle exec rspec` y verificar que reporta 1 fallo y termina con código distinto de 0.
  4. Restaurar solo esa modificación copiando de vuelta `"$EVID/health_check_spec.rb.before"`. Verificar que `sha256sum -c "$EVID/health_check_spec.sha256"` da `OK` y que `cmp` contra la copia no reporta diferencias.
  5. Ejecutar de nuevo `bundle exec rspec` y verificar 5 ejemplos, 0 fallos y código 0.
- [x] 10.3 Ejecutar la comprobación final de D3 y la comprobación de estado de Git sin falsos fallos. Verificar que cada comando termina con código 0 y sin salida inesperada, y que la comprobación de estado imprime `OK`. Un código 2 o mayor se registra como error de la comprobación, no como preservación correcta.
- [x] 10.4 Confirmar el alcance. Ejecutar `grep -rniE 'faraday|open-?meteo' app config spec Gemfile` y verificar que termina con código 1 (sin coincidencias, que es lo esperado); un código 0 es un fallo de alcance y 2 o más es un error. Verificar también que no existen controllers de clima ni objetos `Data`.
- [x] 10.5 Completar el registro de evidencia para el estado 1 de D12 (implementación local terminada). Verificar tres cosas:
  - Cada fila `V*` tiene resultado, comando o fuente y fecha.
  - V9 desde un clon limpio figura como "Pendiente (clon limpio)", y V18, V19, V22, V24 y la parte de GitHub de V21 figuran como "Pendiente (remota)".
  - Ninguna fila afirma una ejecución desde un clon limpio ni en GitHub.

## Workflow follow-up

Estos pasos quedan fuera del checklist de la implementación local y siguen el orden de D12. El cambio permanece abierto hasta completar el último.

- **Commit:** revisar los cambios y hacer commit en la rama `add-rails-api-base` cuando la persona responsable lo apruebe.
- **Clon limpio (local, sin GitHub):** clonar el repositorio local en un directorio nuevo creado con `mktemp -d`, hacer checkout de `add-rails-api-base` y seguir el README tal como está escrito. Registrar el resultado de V9 en el registro de evidencia, reemplazando "Pendiente (clon limpio)".
- **CI en GitHub (remoto):** configurar el remoto, hacer push, abrir un pull request y confirmar en GitHub que los jobs `scan_ruby`, `lint` y `test` pasan con Ruby 4.0.9, tanto para el push a `main` como para el pull request. Registrar la URL del run, el commit y el resultado de V18, V19, V21, V22 y V24, reemplazando "Pendiente (remota)". Si algún job falla, aplicar D9.
- **Archivo:** archivar con `/opsx:archive` solo cuando el CI en GitHub esté comprobado y registrado (D12) y se hayan satisfecho los requisitos de revisión. Hasta entonces, el cambio sigue abierto.
