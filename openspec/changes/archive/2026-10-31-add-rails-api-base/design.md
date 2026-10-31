# Diseño: base Rails API para Clima API

## Context

Ver `proposal.md` (Why). El estado de partida y las restricciones que condicionan el enfoque son estas:

- El repositorio tiene un solo commit en `main` y no tiene remoto configurado. Contiene `.git/`, `.tool-versions` (`ruby 4.0.9`, `nodejs 24.8.0`), `.claude/` (comandos y skills de OpenSpec) y `openspec/`. Los artefactos de este cambio (`openspec/changes/add-rails-api-base/`) existen pero no están versionados.
- El entorno local tiene Ruby 4.0.9 vía asdf, `rails` y `railties` 8.1.4 instalados, Bundler 4.0.20 y `rspec-rails` 8.0.4 ya instalado como gem. No existe `~/.railsrc`, así que el generador no recibe opciones ocultas.
- `nvm` aparece antes que asdf en el `PATH`. En cada terminal hay que correr `nvm deactivate` antes de trabajar.
- La shell interactiva es zsh. Los bloques de comandos de este diseño usan sintaxis de bash (`set -o pipefail`, `PIPESTATUS`), así que se ejecutan dentro de una sesión `bash`.
- Hay que revisar las plantillas de railties 8.1.4 para entender cómo se comporta el generador en un directorio con contenido. Lo relevante es esto:
  - Ninguna plantilla genera rutas que coincidan con los archivos preexistentes.
  - `git init` se ejecuta sobre el repositorio existente, salvo con `--pretend`. Como `init.defaultbranch` no está configurado, ejecuta `git init -b main`, que en un repositorio existente solo reinicializa la configuración y avisa que ignora `-b`.
  - `.ruby-version` se escribe con `Gem.ruby_version` (`4.0.9`), salvo que estén definidas `RBENV_VERSION` o `rvm_ruby_string`.
  - El `Gemfile` generado no incluye directiva `ruby`.
  - `.node-version` solo se genera si la app usa Node. Con `--api` no se genera.
  - `--skip-test` elimina el job `test` de `.github/workflows/ci.yml` y el paso `bin/rails test` de `config/ci.rb`.
  - `--skip-active-record` implica `--skip-active-storage` y `--skip-solid`. `--skip-active-job` implica `--skip-action-mailer` y `--skip-active-storage`. `--skip-active-storage` implica `--skip-action-mailbox` y `--skip-action-text`.
  - Los comandos de análisis que generan las plantillas se detallan en D8.

## Goals / Non-Goals

**Goals:**
- Generar la app de forma determinista y revisable: primero la simulación, después la generación real, y por último la comprobación de que lo preexistente y los artefactos del cambio quedaron intactos.
- Que la suite RSpec sea la única suite, y que local, `bin/ci` y GitHub Actions la ejecuten con el mismo comando.
- Diferenciar lo que las gems declaran soportar de la compatibilidad comprobada en este entorno.
- Diferenciar, para cada escenario de las specs, si se comprueba por inspección de configuración, por ejecución local o por ejecución remota en GitHub, y no dar por comprobado lo que no se ejecutó.

**Non-Goals:**
- Endpoint de clima, Faraday, cliente de Open-Meteo y objeto `Data`. Corresponden al segundo cambio.
- Imagen de contenedor, deploy, caché, reintentos, autenticación y jobs en segundo plano.
- Ejecutar el workflow en GitHub dentro de la implementación. No hay remoto todavía; esa ejecución es condición para archivar el cambio (D12), no para cerrar la implementación local.

## Decisions

### D1. Comando de generación

```
rails _8.1.4_ new . \
  --api \
  --skip-active-record \
  --skip-active-job \
  --skip-action-mailer \
  --skip-action-cable \
  --skip-active-storage \
  --skip-test \
  --skip-docker \
  --skip-kamal \
  --skip-thruster \
  --skip
```

| Opción | Motivo |
|---|---|
| `_8.1.4_` | Fija la versión de railties aunque haya otras instaladas. |
| `.` | Genera en la raíz del repositorio. El nombre de la app (`ClimaApi`) se infiere del directorio `clima-api`. |
| `--api` | Usa el stack reducido para API, sin vistas, assets ni JavaScript. |
| `--skip-active-record` | No genera base de datos (`config/database.yml`, `db/`). Implica también no usar Active Storage ni Solid. |
| `--skip-active-job` | No hay trabajo en segundo plano. |
| `--skip-action-mailer`, `--skip-action-cable` | No se usan. Mailer ya queda implicado por `--skip-active-job`, pero se declara explícito para documentar la intención. |
| `--skip-active-storage` | No se almacenan archivos. Ya queda implicado, pero se declara explícito por la misma razón. |
| `--skip-test` | Saca Minitest y su directorio `test/`. Lo reemplaza RSpec (D4). |
| `--skip-docker`, `--skip-kamal`, `--skip-thruster` | Las herramientas de deploy quedan fuera de alcance. |
| `--skip` | Saltea cualquier archivo que ya exista en vez de pisarlo o preguntar. Es una red de seguridad. |

**No se usan:**
- `--force`, porque pisaría archivos.
- `--skip-git`, porque además omitiría `.gitignore` y `.gitattributes`.
- `--skip-ci`, porque se quiere el workflow de GitHub.
- `--skip-rubocop`, `--skip-brakeman` y `--skip-bundler-audit`, porque se mantienen los tres análisis.
- `--minimal`, porque oculta qué se omite.

`bundle install` se deja como lo ejecuta el generador. Así la base generada se valida antes de sumar RSpec.

**Alternativa descartada:** generar en un directorio temporal y copiar al repositorio. Evita el `git init` sobre el repositorio, pero agrega un paso manual de copia propenso a omisiones, y el `git init` es inocuo.

### D2. Simulación previa obligatoria

Antes de la generación real se ejecuta el mismo comando con `--pretend`, guardando la salida en `"$EVID/pretend.log"` (D3). Con esa opción el generador no escribe archivos ni ejecuta `git init`. La salida se revisa contra esta lista:

- No aparecen líneas `conflict`, `force`, `identical` ni `skip` para `.tool-versions`, `.claude/`, `openspec/` ni `.git/`.
- Aparecen `create` para `.ruby-version`, `Gemfile`, `.gitignore`, `.github/workflows/ci.yml`, `config/ci.rb`, `bin/rubocop`, `bin/brakeman` y `bin/bundler-audit`.
- No aparecen `config/database.yml`, `db/`, `test/`, `Dockerfile`, `config/deploy.yml`, `.kamal/`, `config/storage.yml`, `config/cable.yml`, `app/jobs/`, `app/mailers/` ni `.node-version`.
- Si aparece `storage/`, se anota. Rails lo genera cuando la base configurada por defecto es sqlite3, aun con Active Storage omitido (`skip_storage?` exige ambas condiciones). En ese caso se elimina después de generar, junto con sus líneas de `.gitignore`, porque el proyecto no almacena archivos.

Si la simulación muestra algo fuera de esta lista, se aplica D9: detenerse, registrar y no generar.

### D3. Evidencias y preservación

**Directorio de evidencias.** Cada ejecución usa un directorio nuevo y único, fuera del repositorio, creado con `mktemp`. Nunca se reutiliza un nombre fijo:

```
EVID="$(mktemp -d "${TMPDIR:-/tmp}/clima-api-add-rails-api-base.XXXXXXXX")"
echo "$EVID"
```

La ruta se anota en el registro de evidencia (al final de este documento). Como la variable no sobrevive entre terminales, cada sesión nueva la vuelve a asignar desde esa ruta anotada (`EVID=<ruta registrada>`) en lugar de crear otro directorio.

**Qué se preserva:**
- Archivos versionados en `HEAD` bajo `.tool-versions`, `.claude/` y `openspec/`, el historial (`HEAD`, rama) y la configuración local de Git.
- Los artefactos de este cambio, aunque no estén versionados: `.openspec.yaml`, `proposal.md`, `design.md`, `tasks.md` y `specs/**`.

**Cambios permitidos durante la implementación** (solo en los artefactos del cambio):
- `tasks.md`: únicamente el estado de las casillas (`- [ ]` a `- [x]`).
- `design.md`: únicamente la sección final `## Registro de evidencia`.

Ningún otro artefacto se modifica, y no se agregan ni se borran archivos dentro del directorio del cambio. La generación de Rails no puede modificar ninguno, ni siquiera de las formas permitidas.

**Instantánea inicial** (tarea 1.4, antes de cualquier cambio en el árbol):

```
CHG=openspec/changes/add-rails-api-base
git rev-parse HEAD        > "$EVID/head"
git branch --show-current > "$EVID/branch"
git config --list --local > "$EVID/gitconfig"
git ls-files -z -- .tool-versions .claude openspec | xargs -0 sha256sum > "$EVID/preexisting.sha256"
cp -a "$CHG" "$EVID/change-artifacts.initial"
(cd "$CHG" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$EVID/change-artifacts.initial.sha256"
```

**Instantánea inmediatamente previa a la generación real** (tarea 2.2):

```
(cd "$CHG" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$EVID/change-artifacts.pre-generate.sha256"
(cd "$CHG" && find . -type f | sort) > "$EVID/change-artifacts.pre-generate.list"
find . -path ./.git -prune -o -print | sort > "$EVID/paths.before"
```

**Comprobación inmediatamente posterior a la generación** (tarea 2.3). Cualquier diferencia acá la causó el generador:

```
sha256sum --quiet -c "$EVID/preexisting.sha256"                                    # sin salida, código 0
(cd "$CHG" && sha256sum --quiet -c "$EVID/change-artifacts.pre-generate.sha256")   # sin salida, código 0
diff "$EVID/change-artifacts.pre-generate.list" <(cd "$CHG" && find . -type f | sort)   # sin salida, código 0
diff "$EVID/gitconfig" <(git config --list --local)                                # sin salida, código 0
test "$(git rev-parse HEAD)" = "$(cat "$EVID/head")"                               # código 0
test "$(git branch --show-current)" = "$(cat "$EVID/branch")"                      # código 0
find . -path ./.git -prune -o -print | sort > "$EVID/paths.after"
comm -13 "$EVID/paths.before" "$EVID/paths.after" > "$EVID/generated-paths.txt"    # rutas creadas por esta ejecución
comm -23 "$EVID/paths.before" "$EVID/paths.after"                                  # sin salida: no desapareció nada
```

**Comprobación de estado de Git sin falsos fallos.** `grep -v` devuelve 1 cuando no queda ninguna línea, que acá es el resultado esperado. Se distinguen los tres casos de forma explícita:

```
if status="$(git status --porcelain --untracked-files=all -- .tool-versions .claude openspec)"; then
  printf '%s\n' "$status" | grep -v -e '^$' -e '^?? openspec/changes/add-rails-api-base/'
  rc=$?
  case "$rc" in
    1) echo "OK: sin cambios fuera de los artefactos del cambio" ;;
    0) echo "FALLO: cambios inesperados (listados arriba)" ;;
    *) echo "ERROR: grep terminó con código $rc" ;;
  esac
else
  echo "ERROR: git status falló"
fi
```

El mismo criterio vale para `diff` (0 iguales, 1 diferentes, 2 o más error) y para cualquier búsqueda cuyo resultado esperado sea "sin coincidencias" (tarea 10.4).

**Comprobación final** (tarea 10.3), que admite solo los cambios permitidos:

```
# 1. Preexistentes, historial y configuración: igual que en la tarea 2.3.
# 2. Artefactos que no admiten cambios:
(cd "$CHG" && sha256sum --quiet -c <(grep -v -e ' \./tasks\.md$' -e ' \./design\.md$' "$EVID/change-artifacts.initial.sha256"))
# 3. Mismo conjunto de archivos en el cambio:
diff <(cd "$EVID/change-artifacts.initial" && find . -type f | sort) <(cd "$CHG" && find . -type f | sort)
# 4. tasks.md: solo cambió el estado de las casillas.
norm() { sed -E 's/^([[:space:]]*- )\[[ xX]\]/\1[ ]/' "$1"; }
diff <(norm "$EVID/change-artifacts.initial/tasks.md") <(norm "$CHG/tasks.md")
# 5. design.md: todo lo anterior al registro de evidencia sigue igual.
pre_registro() { sed '/^## Registro de evidencia$/,$d' "$1"; }
diff <(pre_registro "$EVID/change-artifacts.initial/design.md") <(pre_registro "$CHG/design.md")
```

Cada comando debe terminar con código 0 y sin salida. Un código 1 de `diff` o de `sha256sum` es un fallo de preservación; un código 2 o mayor es un error de la comprobación misma, y se registra como tal.

### D4. RSpec como única suite

- Se agrega `gem "rspec-rails", "~> 8.0"` a los grupos `:development, :test` y se ejecuta `bin/rails generate rspec:install`. Eso genera `.rspec`, `spec/spec_helper.rb` y `spec/rails_helper.rb`.
- La plantilla de `rspec-rails` detecta la ausencia de Active Record y genera `config.use_active_record = false`, sin `maintain_test_schema!` ni fixtures. No hace falta editarla.
- El criterio de versión es usar versiones estables compatibles, no una versión menor concreta. Después de instalar, se registran las versiones efectivamente resueltas de `rspec-rails` y de cada `rspec-*`, y se comprueba que `Gemfile.lock` no contiene ninguna prerelease:

  ```
  bundle exec ruby -e 'lock = Bundler::LockfileParser.new(Bundler.read_file("Gemfile.lock"))
    lock.specs.select { |s| s.name.start_with?("rspec") }.each { |s| puts "#{s.name} #{s.version}" }
    pre = lock.specs.select { |s| s.version.prerelease? }
    abort("Prereleases: #{pre.map(&:full_name).join(", ")}") unless pre.empty?'
  ```

  La compatibilidad queda comprobada cuando, además, la suite corre en verde (D10).
- El comando canónico es `bundle exec rspec`. Se usa idéntico en el README, en `config/ci.rb` y en el workflow. Se elige `bundle exec rspec` en vez de un binstub `bin/rspec` porque `rspec:install` no genera binstub y así no se agrega un archivo más.
- Ubicación de las pruebas: `spec/requests/health_check_spec.rb` y `spec/services/application_service_spec.rb`.

### D5. Versión de Ruby

- `.ruby-version` debe contener `4.0.9`, igual que `.tool-versions`. El generador lo escribe así. Antes de generar se verifica que `ruby -v` muestre 4.0.9 y que `RBENV_VERSION` y `rvm_ruby_string` no estén definidas.
- `Gemfile`: se agrega `ruby file: ".ruby-version"`. Con eso Bundler rechaza otro Ruby y `Gemfile.lock` registra la versión en la sección `RUBY VERSION`.
- El workflow de CI usa `ruby/setup-ruby@v1` sin `ruby-version`, porque por defecto lee `.ruby-version`.
- `.tool-versions` no se toca. asdf lo prioriza localmente, y `.ruby-version` es la fuente para Bundler y CI.

**Alternativa descartada:** borrar `.ruby-version` y usar solo `.tool-versions`. `setup-ruby` puede leer `.tool-versions`, pero la directiva `ruby file:` de Bundler y la caché del job `lint` generado esperan `.ruby-version`.

### D6. `ApplicationService`

El contrato observable está en `specs/service-objects/spec.md`. Va en `app/services/application_service.rb`, que Zeitwerk carga automáticamente, y su única responsabilidad es esta delegación:

```
class ApplicationService
  def self.call(...) = new(...).call
end
```

- `new` sigue siendo público.
- No hay `#call` abstracto ni `NotImplementedError`, ni otras restricciones sobre las subclases. Una subclase sin `#call` falla con el `NoMethodError` normal de Ruby.
- La prueba define una subclase anónima dentro del spec, que recibe un argumento posicional y uno keyword. Tiene un ejemplo por escenario de la spec:
  1. El posicional llega a la instancia.
  2. El keyword llega a la instancia.
  3. `.call` devuelve el mismo objeto que retorna `#call` de la instancia (se compara por identidad, con `equal`).

### D7. Ruta de salud

Se usa la ruta `get "up" => "rails/health#show"` que genera Rails, sin controller propio. Responde 200 si la app arrancó y 500 si hubo una excepción al arrancar. Se verifica de dos maneras:
- Un request spec con `GET /up` que espera 200.
- Una comprobación manual con el servidor levantado: `bin/rails server`, y en otra terminal `curl -i http://localhost:3000/up`.

### D8. Comandos de análisis, CI y verificación local

El comando de pruebas es idéntico en los tres lugares. Los análisis usan las mismas herramientas y la misma configuración del repositorio (`.rubocop.yml`, `config/bundler-audit.yml`, configuración por defecto de Brakeman), pero pueden diferir en opciones de presentación. Según las plantillas de railties 8.1.4:

| Comprobación | README (local) | `bin/ci` (`config/ci.rb`) | GitHub Actions (`ci.yml`) | Diferencias admitidas |
|---|---|---|---|---|
| Pruebas | `bundle exec rspec` | `bundle exec rspec` | `bundle exec rspec` | Ninguna. |
| Estilo | `bin/rubocop` | `bin/rubocop` | `bin/rubocop -f github` | `-f github` solo cambia el formato de salida a anotaciones de GitHub. |
| Seguridad estática | `bin/brakeman --no-pager` | `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` | `bin/brakeman --no-pager` | `--no-pager` y `--quiet` son de presentación. `--exit-on-warn` y `--exit-on-error` repiten los valores por defecto de Brakeman 8.1.0 (`brakeman --help`), así que no cambian las comprobaciones. `bin/brakeman` agrega `--ensure-latest` en los tres casos. |
| Auditoría de dependencias | `bin/bundler-audit` | `bin/bundler-audit` | `bin/bundler-audit` | Ninguna. El binstub agrega `--config config/bundler-audit.yml`. |

Durante la implementación se leen los archivos efectivamente generados y se confirma esta tabla. Si aparece una diferencia que no sea de presentación, se alinea el comando del README con el de CI, nunca al revés quitando comprobaciones.

**Cambios sobre lo generado:**
- `.github/workflows/ci.yml` conserva los jobs `scan_ruby` y `lint`, y se le agrega un job `test` con checkout, `ruby/setup-ruby@v1` con `bundler-cache: true` (sin `ruby-version`), y `run: bundle exec rspec`.
- Los disparadores generados se mantienen: `pull_request`, y `push` a `main` (`user_default_branch` resuelve a `main`).
- En `config/ci.rb` se agrega `step "Tests: RSpec", "bundle exec rspec"` después de los análisis de seguridad.

**Qué se comprueba en este cambio y qué no:** la configuración del workflow se inspecciona (jobs, disparadores, comandos, origen de la versión de Ruby) y su equivalente local (`bin/ci` y los comandos del README) se ejecuta. La ejecución del workflow en GitHub no ocurre en este cambio y se registra como pendiente (D11, D12).

### D9. Manejo de fallos

Si una tarea falla o su verificación no da el resultado esperado:

1. Detenerse. No continuar con la tarea siguiente ni intentar otra variante del comando sin revisar.
2. Registrar en el registro de evidencia la tarea, el comando, el código de salida y la ruta del log en `$EVID`. Los comandos largos se ejecutan con `set -o pipefail` y `2>&1 | tee "$EVID/<tarea>.log"` para conservar la salida completa.
3. Conservar todo: la rama de trabajo, los archivos generados y el directorio de evidencias. No se borra la rama ni se revierten archivos automáticamente.
4. Diagnosticar y continuar desde la tarea que falló una vez resuelta la causa.

**Limpieza, solo si después se decide hacerla de forma explícita:**
- Se parte exclusivamente de `"$EVID/generated-paths.txt"`, que lista lo que creó esta ejecución.
- Antes de borrar, se revisa la lista y se descarta cualquier ruta que figure en `"$EVID/preexisting.sha256"`, que esté bajo `.git/`, `.claude/` u `openspec/`, o que coincida con `.tool-versions`.
- Se eliminan solo las rutas que quedan en la lista revisada, una por una o por lista explícita.
- No se usa `git clean` general ni comandos que borren por patrón el árbol de trabajo.
- Después se repiten las comprobaciones de preservación de D3.

### D10. Compatibilidad declarada frente a comprobada

| Componente | Declarado (fuente) | Cómo se comprueba en este cambio |
|---|---|---|
| `rspec-rails ~> 8.0` | 8.0.4: `required_ruby_version >= 3.0.0`; `railties`, `actionpack` y `activesupport >= 7.2`; `rspec-*` `>= 3.13, < 5` (RubyGems). El README de la gem solo menciona Rails 8.0 y 7.2. | Se registran las versiones resueltas, se comprueba que no hay prereleases (D4) y la suite corre en verde con Ruby 4.0.9 y Rails 8.1.4. |
| `rails 8.1.4` en Ruby 4.0.9 | Instalado y funcionando en el entorno local. | Arranque sin base de datos, `/up` con 200 y suite en verde. |
| Herramientas de análisis | Versiones que resuelva Bundler. | Se registran y los tres análisis terminan con código 0 en local. |
| Ruby 4.0.9 en GitHub Actions | Sin verificar si `ruby/setup-ruby` ofrece binarios 4.0.9 para `ubuntu-latest`. | No se comprueba en este cambio: requiere remoto y push (D12). |

Que una gem declare `>= 3.0` no prueba que funcione con Ruby 4. Los resultados reales se anotan en el registro de evidencia.

### D11. Matriz de verificación

Cada escenario de las specs tiene un nivel de verificación:
- **Inspección:** se lee la configuración o el árbol de archivos.
- **Local:** se ejecuta un comando en esta máquina, sobre el árbol de trabajo.
- **Clon limpio:** se ejecuta en esta máquina, pero sobre un clon nuevo del repositorio local, así que necesita que exista un commit. No depende de GitHub. Hasta hacerse queda como "Pendiente (clon limpio)".
- **Remota:** requiere una ejecución real del workflow en GitHub, con remoto y push. Hasta hacerse queda como "Pendiente (remota)" y no se marca como comprobada.

| ID | Spec: escenario | Nivel | Tarea |
|---|---|---|---|
| V1 | health-check: Arranque sin configuración de base de datos | Local | 2.6 |
| V2 | health-check: Ausencia de configuración de base de datos | Inspección | 2.5 |
| V3 | health-check: Aplicación sana | Local | 5.2 |
| V4 | health-check: Salud verificada por la suite automática | Local | 5.1 |
| V5 | health-check: Ruta inexistente | Local | 5.1 |
| V6 | development-environment: Archivos de versión coherentes | Inspección | 3.1 |
| V7 | development-environment: Dependencias atadas a la versión declarada | Inspección | 3.1 |
| V8 | development-environment: Ruby distinto del declarado | Local | 3.2 |
| V9 | development-environment: Recorrido desde un clon limpio | Local sobre el árbol de trabajo; Clon limpio: Comprobado (clon limpio, ver registro) | 9.1; Seguimiento |
| V10 | development-environment: Comando de pruebas documentado | Local | 9.1 |
| V11 | development-environment: Suite en verde | Local | 10.1 |
| V12 | development-environment: Un fallo se detecta | Local | 10.2 |
| V13 | development-environment: Sin suite paralela | Inspección | 2.5 |
| V14 | service-objects: Reenvío de argumentos posicionales | Local | 6.2 |
| V15 | service-objects: Reenvío de argumentos keyword | Local | 6.2 |
| V16 | service-objects: Retorno del resultado de la instancia | Local | 6.2 |
| V17 | continuous-integration: Disparadores declarados | Inspección | 8.2 |
| V18 | continuous-integration: Push a main | Remota: Comprobado (remota, ver registro) | Seguimiento |
| V19 | continuous-integration: Pull request | Remota: Comprobado (remota, ver registro) | Seguimiento |
| V20 | continuous-integration: Mismo comando que en local | Inspección | 8.2 |
| V21 | continuous-integration: Versión de Ruby del workflow | Inspección; resolución real de 4.0.9 en GitHub: Comprobado (remota, ver registro) | 8.2; Seguimiento |
| V22 | continuous-integration: Suite con fallos | Remota: Comprobado (remota, ver registro); equivalente local en V12 | Seguimiento |
| V23 | continuous-integration: Diferencias solo de presentación | Inspección | 7.1, 8.2 |
| V24 | continuous-integration: Hallazgo bloqueante | Remota: Comprobado (remota, ver registro); los análisis locales terminan con código 0 en 7.2 | Seguimiento |
| V25 | continuous-integration: Verificación local completa | Local | 8.1 |

### D12. Cierre de la implementación y archivo del cambio

El cambio pasa por tres estados, y ninguno se da por alcanzado sin su evidencia registrada:

1. **Implementación local terminada.** Todas las tareas de `tasks.md` están marcadas, pasaron sus verificaciones locales y de inspección, y cada fila del registro de evidencia tiene resultado. Las verificaciones que todavía no se pueden hacer quedan explícitas:
   - V9 desde un clon limpio: "Pendiente (clon limpio)".
   - V18, V19, V22, V24 y la parte de GitHub de V21: "Pendiente (remota)".
2. **Verificación desde un clon limpio.** Se hace en local después del commit (ver "Workflow follow-up" en `tasks.md`) y no depende de GitHub. Completa V9.
3. **Verificación remota.** Requiere remoto, push y un pull request. Se registran la URL del run, el commit y el resultado de los jobs `scan_ruby`, `lint` y `test` para un push a `main` y para un pull request. Completa V18, V19, V21, V22 y V24.

**El cambio permanece abierto, sin archivar,** hasta que el CI esté comprobado en GitHub (estado 3). Archivar incorpora la spec `continuous-integration` como comportamiento vigente del proyecto, y eso no debe pasar con sus escenarios remotos sin comprobar. Mientras tanto, ningún artefacto ni registro presenta la ejecución remota como realizada.

### D13. README

El README generado se reemplaza por uno que documente, en este orden:

1. Prerrequisitos: asdf con Ruby 4.0.9, y `nvm deactivate` si nvm está activo.
2. `bundle install`.
3. `bundle exec rspec`.
4. Los comandos locales de análisis de la tabla D8: `bin/rubocop`, `bin/brakeman --no-pager` y `bin/bundler-audit`.
5. `bin/ci`.
6. `bin/rails server` y `curl -i http://localhost:3000/up`.

Debe indicar también que la app no usa base de datos, que la primera ejecución de `bin/bundler-audit` necesita red y que el endpoint de clima llega en un cambio posterior. Cada comando tiene que funcionar tal como está escrito desde el entorno preparado (spec `development-environment`).

## Risks / Trade-offs

- **[`rspec-rails` 8.0.x no declara soporte explícito para Rails 8.1]** → Mitigación: la suite tiene que correr en verde. Si falla por incompatibilidad, se aplica D9 y se evalúa la versión de `rspec-rails` antes de seguir.
- **[`git init` sobre el repositorio existente]** → Es inocuo, pero puede reescribir claves de `.git/config`. Mitigación: se compara `git config --list --local` antes y después, y se conservan `HEAD` y la rama (D3).
- **[`bin/brakeman` usa `--ensure-latest`]** → Una nueva versión de Brakeman hace fallar el análisis local y el de CI hasta actualizar la gem. Mitigación: se mantiene el comando generado, Dependabot propone la actualización y el README explica el error.
- **[`bin/bundler-audit` necesita la base de avisos]** → La primera ejecución descarga la base y requiere red. Mitigación: documentarlo en el README.
- **[Ruby 4.0.9 no disponible en `setup-ruby`]** → El workflow fallaría en el primer push. Mitigación: queda como verificación remota pendiente y bloquea el archivo del cambio (D12), no la implementación local.
- **[`storage/` generado pese a omitir Active Storage]** → Mitigación: se detecta en la simulación (D2) y se elimina.
- **[El generador corre `bundle install` con red]** → Si falla la red, la generación queda a medias. Mitigación: D9, que detiene, registra y conserva el estado para continuar.
- **[El directorio de evidencias está en un temporal]** → Puede perderse al reiniciar la máquina. Mitigación: los resultados se resumen en el registro de evidencia de este documento. Si se pierde antes de la comprobación final, se registra y se repite la instantánea, sin dar por buena la comparación anterior.

## Migration Plan

1. Trabajar en la rama `add-rails-api-base`, creada desde `main` limpio.
2. Crear el directorio de evidencias, tomar la instantánea inicial (D3), simular (D2) y generar.
3. Ante cualquier fallo, aplicar D9: detenerse, registrar y conservar. No hay reversión automática.
4. No hay deploy ni datos que migrar.

## Open Questions

- Ubicación y nombre del remoto de GitHub. No cambia los archivos de este cambio, pero define cuándo pueden completarse las verificaciones remotas y, con ellas, el archivo del cambio (D12). No afecta a la verificación desde un clon limpio, que es local.

## Registro de evidencia

Esta sección se completa durante la implementación. Es la única parte de este documento que puede cambiar en esa etapa (D3).

- Directorio de evidencias: `/home/pablo/clima-api-evidencias/clima-api-add-rails-api-base.4919UiDi`. Es la copia persistente del directorio original `/tmp/clima-api-add-rails-api-base.4919UiDi`, creado con `mktemp -d` el 2026-10-31 sobre la base `d255446` (hoy `54f471b`; ver "Reescritura del email de los commits") y la rama `add-rails-api-base`; `diff -r` entre ambos no mostró diferencias (70 archivos). Los nombres de archivo citados abajo son relativos a ese directorio. Las evidencias de la revisión previa al commit están en `/home/pablo/clima-api-evidencias/precommit.S5SHAQaL/`, y las del clon limpio en `/home/pablo/clima-api-evidencias/cleanclone.8h92Mohc/evidencias/`.
- Versiones resueltas: Ruby 4.0.9 (asdf) · Rails 8.1.4 · Bundler 4.0.20 · rspec-rails 8.0.4 · rspec-core 3.13.6 · rspec-expectations 3.13.5 · rspec-mocks 3.13.8 · rspec-support 3.13.7 · rubocop 1.92.2 · rubocop-rails-omakase 1.1.0 · brakeman 8.1.0 · bundler-audit 0.9.3 · puma 8.0.2 · bootsnap 1.26.1. Sin prereleases en `Gemfile.lock` (`4.2-versions.txt`).
- Comandos de análisis efectivamente generados (D8): coinciden con la tabla. README: `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`. `bin/ci`: `bin/rubocop`, `bin/bundler-audit`, `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`, `bundle exec rspec`. `ci.yml`: `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/rubocop -f github`, `bundle exec rspec`. `bin/brakeman` agrega `--ensure-latest`, `bin/rubocop` agrega `--config .rubocop.yml` y `bin/bundler-audit` agrega `--config config/bundler-audit.yml` (`7.1-generated-commands.txt`).
- Hallazgos y desvíos (D9):
  - `.ruby-version` generado con `ruby-4.0.9` (prefijo `ruby-`), no `4.0.9` como suponía el contexto. Se normalizó a `4.0.9` según D5; el original está en `ruby-version.generated`.
  - El comando de 3.2 (`bundle exec ruby -v`) no valida la versión: `ruby -v` termina sin cargar `bundler/setup` y devolvió código 0 con Ruby 3.4.7. Se verificó con `bundle exec ruby -e 'puts RUBY_VERSION'`, que lanza `Bundler::RubyVersionMismatch` desde `Definition#validate_ruby!` (código 1), y con `bundle check` (código 18), con control en 4.0.9 (código 0) (`3.2-ruby-mismatch.txt`, `3.2-diagnostico.txt`). Durante la implementación el texto de la tarea no se modificó (D3); se corrigió después con `/opsx:update` (ver "Actualizaciones de planificación posteriores").
  - `.rspec` solo carga `spec_helper`; la corrida vacía de 4.3 se repitió con `--require rails_helper` para cargar Rails sin base de datos (`4.3-rspec-empty-rails_helper.txt`).
  - La casilla 2.2 se marcó antes de la comprobación posterior a la generación; en 2.3 `tasks.md` se comparó normalizando casillas, sin diferencias (`post-generate-check.txt`).
  - El generador creó `config/master.key`; está ignorado por `.gitignore` (`/config/*.key`) y no se leyó ni se registró su contenido.
  - En la implementación, `bin/bundler-audit` usó la base de avisos local del 2026-10-17 (commit `fa22952`), porque el binstub no la actualiza. El 2026-10-31 a las 10:06 (-03:00) se actualizó con `bin/bundler-audit update` al commit `542ff6e`, del 2026-10-30, con 1285 avisos. La auditoría repetida con `bin/bundler-audit` terminó con `No vulnerabilities found`, código 0 (`precommit-bundler-audit-update.txt`). La base sigue siendo local: CI la descarga en cada ejecución, y en local hay que repetir `bin/bundler-audit update` antes de auditar.
  - `actionlint` no está instalado; el workflow se inspeccionó con el parser YAML de Ruby, no con un linter de GitHub Actions.
- Actualizaciones de planificación posteriores a la implementación (pedidas de forma explícita, fuera de la regla de D3 que rige la implementación):
  - 2026-10-31, `/opsx:update`: el texto de la tarea 3.2 reemplaza `bundle exec ruby -v` por `bundle exec ruby -e 'puts RUBY_VERSION'`, el comando que produjo `Bundler::RubyVersionMismatch`, y suma el control con Ruby 4.0.9. La casilla sigue marcada porque la verificación se hizo con ese comando. Los artefactos previos a esta actualización están en `change-artifacts.before-precommit-update/`. Por este cambio de texto, la comparación 4 de la comprobación final de D3 debe hacerse contra esa copia y no contra `change-artifacts.initial/`.
- Reescritura del email de los commits (2026-10-31, antes de publicar en `pablo-wpify/clima-api`): los tres commits locales se reescribieron cambiando solo el email de autor y de committer, de un email personal al noreply `283251664+pablo-wpify@users.noreply.github.com`. Se conservaron el nombre, las fechas, los mensajes (idénticos byte a byte) y el contenido. Cambian los hashes porque cambian los emails y, en cadena, los `parent`:

  | Commit original | Equivalente reescrito | Árbol (idéntico en ambos) |
  |---|---|---|
  | `d255446` chore: initialize OpenSpec and pin project runtimes | `54f471b` | `aabe736` |
  | `b972437` feat: add Rails API base with RSpec and CI | `1cb3ce8` | `5ce8b45` |
  | `40f7c04` docs: record clean clone verification and durable evidence | `7209226` | `0046bf0` |

  En cada par `git diff` entre commits sale vacío. Las verificaciones registradas acá se ejecutaron sobre los hashes originales; la reescritura no repitió ninguna prueba. Como el árbol es idéntico, lo verificado sobre `b972437` vale para el contenido de `1cb3ce8`. Respaldo previo (bundle verificado), mapa de hashes y verificación por par en `/home/pablo/clima-api-evidencias/rewrite.KagSBAj9/`.

| ID | Resultado | Comando o fuente | Fecha |
|---|---|---|---|
| V1 | Comprobado (local) | `bin/rails runner 'p defined?(ActiveRecord)'` → `nil`; `RAILS_ENV=test bin/rails runner 'puts :ok'` → `ok` (`2.6-runner-*.txt`) | 2026-10-31 |
| V2 | Comprobado (inspección) | Sin `config/database.yml` ni `db/`; `active_record/railtie` comentado (`application.rb.head.txt`) | 2026-10-31 |
| V3 | Comprobado (local) | `bin/rails server` + `curl` a `/up` → `200` y `HTTP/1.1 200 OK` (`5.2-curl.txt`, `9.1-readme-walkthrough.txt`) | 2026-10-31 |
| V4 | Comprobado (local) | `bundle exec rspec spec/requests` → 2 ejemplos, 0 fallos (`5.1-rspec-requests.txt`) | 2026-10-31 |
| V5 | Comprobado (local) | Mismo spec: ruta inexistente → 404 (`5.1-rspec-requests.txt`) | 2026-10-31 |
| V6 | Comprobado (inspección) | `diff` entre `.tool-versions` y `.ruby-version` sin diferencias, tras normalizar el prefijo `ruby-` | 2026-10-31 |
| V7 | Comprobado (inspección) | `Gemfile` con `ruby file: ".ruby-version"` y sin literal; `Gemfile.lock` con `RUBY VERSION ruby 4.0.9` | 2026-10-31 |
| V8 | Comprobado (local) | Ruby 3.4.7: `Your Ruby version is 3.4.7, but your Gemfile specified 4.0.9` (`Bundler::RubyVersionMismatch`, código 1; `bundle check` código 18). Ver hallazgos | 2026-10-31 |
| V9 | Árbol de trabajo: Comprobado (local), todos los comandos del README con código 0 (`9.1-readme-walkthrough.txt`) · Clon limpio: Comprobado (local) sobre el commit `b972437` (equivalente reescrito: `1cb3ce8`, mismo árbol `5ce8b45`; la verificación no se repitió tras la reescritura), clonado de la rama `add-rails-api-base` del repositorio local, sin copiar `master.key`, `.env` ni archivos ignorados. Con Ruby 4.0.9 (asdf, `.tool-versions`), terminaron con código 0: `bundle install` (92 gems), `bundle exec rspec` (5 ejemplos, 0 fallos), `bin/rubocop` (21 archivos, sin ofensas), `bin/brakeman --no-pager` (0 advertencias, 0 errores), `bin/bundler-audit update` (commit `542ff6e`, 1285 avisos), `bin/bundler-audit` (sin vulnerabilidades) y `bin/ci` (sus cinco pasos en verde). `curl -i http://localhost:3000/up` respondió `HTTP/1.1 200 OK` y el log del servidor registra `Completed 200 OK`; el código de salida de `curl` no se registró por separado. Se detuvo solo el servidor iniciado (pid 126311) y el puerto quedó libre. `bundle install` reutilizó las gems ya instaladas en ese Ruby, así que no prueba una descarga desde cero. Sin `master.key`, Rails generó `tmp/local_secret.txt` para desarrollo (ignorado) | README; evidencias persistentes en `/home/pablo/clima-api-evidencias/cleanclone.8h92Mohc/evidencias/` | 2026-10-31 |
| V10 | Comprobado (local) | `bundle exec rspec` tal como figura en el README → 5 ejemplos, 0 fallos | 2026-10-31 |
| V11 | Comprobado (local) | `bundle exec rspec` → 5 ejemplos, 0 fallos, código 0 (`10.1-rspec-full.txt`) | 2026-10-31 |
| V12 | Comprobado (local) | 200→201 en `health_check_spec.rb`: 1 fallo, código 1; restaurado desde copia (`sha256sum -c` OK, `cmp` sin diferencias); nueva corrida 5/0, código 0 (`10.2-*.txt`) | 2026-10-31 |
| V13 | Comprobado (inspección) | No existe `test/`; `rails/test_unit/railtie` comentado | 2026-10-31 |
| V14 | Comprobado (local) | `bundle exec rspec spec/services` → 3 ejemplos, 0 fallos (`6.2-rspec-services-green.txt`); antes de implementar falló con `NameError` (`6.1-rspec-services-red.txt`) | 2026-10-31 |
| V15 | Comprobado (local) | Mismo spec, ejemplo de keyword | 2026-10-31 |
| V16 | Comprobado (local) | Mismo spec, retorno por identidad (`equal`) | 2026-10-31 |
| V17 | Comprobado (inspección) | `ci.yml`: `pull_request` y `push` a `main` (`8.2-ci-inspection.txt`) | 2026-10-31 |
| V18 | Comprobado (remota) | Merge del PR #1 con `--merge` (merge commit `04c57c6`, 2026-10-31 14:25:20 UTC; https://github.com/pablo-wpify/clima-api/pull/1). El push resultante a `main` disparó el run 41210054592 (https://github.com/pablo-wpify/clima-api/actions/runs/41210054592): evento `push`, rama `main`, SHA `04c57c6`; `scan_ruby`, `lint` y `test` en `success`. Los tres jobs instalaron Ruby 4.0.9 desde `.ruby-version`; Brakeman 0 advertencias; bundler-audit sin vulnerabilidades (base `542ff6e`); RSpec 5 ejemplos, 0 fallos. Antes del merge, `main` (`54f471b`) no contenía el workflow (log y resumen en `/home/pablo/clima-api-evidencias/github.R4Ufr39U/`) | 2026-10-31 |
| V19 | Comprobado (remota) | PR #1 `add-rails-api-base` → `main` (https://github.com/pablo-wpify/clima-api/pull/1). Run 41208887614, evento `pull_request`, SHA `1b36b7e`: `scan_ruby`, `lint` y `test` en `success`; RSpec 5 ejemplos, 0 fallos; Brakeman 0 advertencias; bundler-audit sin vulnerabilidades (base `542ff6e`) (https://github.com/pablo-wpify/clima-api/actions/runs/41208887614; log `pr1-run-41208887614.log` en `/home/pablo/clima-api-evidencias/github.R4Ufr39U/`) | 2026-10-31 |
| V20 | Comprobado (inspección) | `run` del job `test`, README y `config/ci.rb`: `bundle exec rspec` en los tres (`8.2-ci-inspection.txt`) | 2026-10-31 |
| V21 | Inspección: Comprobado, ningún `setup-ruby` declara `ruby-version` (`grep` código 1) · GitHub: Comprobado (remota). En el run 41208887614, los tres jobs registran `Using 4.0.9 as input from file .ruby-version` e instalan `ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-linux]` con `ruby/setup-ruby@v1` (SHA `de492cf`) en `ubuntu-24.04` | `8.2-ci-inspection.txt`; `pr1-run-41208887614.log` | 2026-10-31 |
| V22 | Comprobado (remota) | PR temporal #2, rama `ci-check/v22-failing-spec` → `add-rails-api-base` (https://github.com/pablo-wpify/clima-api/pull/2), commit `ec438f3` con un spec que falla a propósito (`expect(1 + 1).to eq(3)`). Run 41209025906 (https://github.com/pablo-wpify/clima-api/actions/runs/41209025906): `test` en `failure` por ese ejemplo (`expected: 3, got: 2`, 6 ejemplos, 1 fallo, código 1), con Ruby 4.0.9 instalado; `lint` y `scan_ruby` en `success`, así que no hubo problema de infraestructura. El PR se cerró sin merge y la rama se eliminó (local y remota); parche y log en `/home/pablo/clima-api-evidencias/github.R4Ufr39U/` | 2026-10-31 |
| V23 | Comprobado (inspección) | Diferencias solo de presentación según D8 (`7.1-generated-commands.txt`) | 2026-10-31 |
| V24 | Comprobado (remota) | PR temporal #3, rama `ci-check/v24-brakeman-finding` → `add-rails-api-base` (https://github.com/pablo-wpify/clima-api/pull/3), commit `99d22ee` con un controller aislado, sin ruta, que contiene `eval(params[:code])`; el código nunca se ejecutó. Run 41209049110 (https://github.com/pablo-wpify/clima-api/actions/runs/41209049110): `scan_ruby` en `failure` porque Brakeman reportó 1 advertencia (`Dangerous Eval`, check `Evaluation`, confianza alta, `ci_check_v24_controller.rb:7`, código 3); `lint` y `test` en `success`. El PR se cerró sin merge y la rama se eliminó (local y remota); parche y log en `/home/pablo/clima-api-evidencias/github.R4Ufr39U/` | 2026-10-31 |
| V25 | Comprobado (local) | `bin/ci` → setup, estilo, auditoría, Brakeman y RSpec en verde, código 0 (`8.1-bin-ci.txt`) | 2026-10-31 |
