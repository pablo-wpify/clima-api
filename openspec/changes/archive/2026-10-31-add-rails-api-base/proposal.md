# Propuesta: base Rails API para Clima API

## Why

El repositorio hoy solo contiene OpenSpec, su integración con Claude Code y `.tool-versions`. Antes de construir el endpoint de clima hace falta una aplicación Rails en modo API que arranque sin base de datos, responda por HTTP, ejecute su suite de pruebas localmente y en CI, y pueda reproducirse desde cero a partir del README. Separar esta base del endpoint permite validar la compatibilidad del stack (Ruby 4.0.9 + Rails 8.1.4 + RSpec) antes de sumar lógica de dominio.

## What Changes

- Generar una aplicación Rails 8.1.4 en modo API en la raíz del repositorio, con Ruby 4.0.9, preservando `.git/`, `.tool-versions`, `.claude/`, `openspec/` y los artefactos de este cambio. La generación real se hace solo después de revisar una simulación con `--pretend`.
- Excluir Active Record, Active Job, Action Mailer, Action Cable, Active Storage (y lo que estos arrastran: Action Mailbox, Action Text, Solid Cache/Queue/Cable), y las herramientas de deploy (Docker, Kamal, Thruster).
- Reemplazar la suite Minitest predeterminada por RSpec.
- Exponer la ruta de salud `/up` que genera Rails y cubrirla con una prueba HTTP.
- Agregar `ApplicationService` con únicamente la delegación `self.call(...)` → `new(...).call`, especificada como convención de invocación de servicios y cubierta por pruebas del reenvío de argumentos posicionales y keywords y del valor retornado.
- Mantener RuboCop, Brakeman y bundler-audit tal como los genera Rails, revisando sus comandos reales (`bin/rubocop`, `bin/brakeman`, `bin/bundler-audit`). Local y CI ejecutan las mismas comprobaciones; solo pueden diferir en opciones de presentación de la salida.
- Mantener un único valor de versión de Ruby: `.ruby-version` coincide con `.tool-versions` y el `Gemfile` referencia `.ruby-version`.
- Configurar CI de GitHub con un job que ejecuta RSpec con exactamente el mismo comando documentado para uso local, y sumar ese mismo paso a `config/ci.rb` (`bin/ci`).
- Reescribir el README con instrucciones reproducibles desde el entorno preparado (asdf con Ruby 4.0.9).

**Fuera de alcance (segundo cambio):** Faraday, el endpoint meteorológico, el cliente de Open-Meteo y el objeto `Data` de resultado. Tampoco se agregan caché, reintentos, autenticación ni deploy.

## Capabilities

### New Capabilities

- `health-check`: disponibilidad HTTP de la aplicación y su capacidad de arrancar sin base de datos.
- `development-environment`: entorno de desarrollo reproducible: versión única de Ruby declarada en el proyecto y comandos documentados para instalar, probar, analizar y levantar la aplicación.
- `continuous-integration`: verificación automática en cada push a `main` y en cada pull request, ejecutando la suite de pruebas con el mismo comando que en local, más los análisis estáticos y de seguridad.
- `service-objects`: convención para invocar los servicios de la aplicación con una sola llamada de clase que reenvía los argumentos y devuelve el resultado de la instancia.

### Modified Capabilities

Ninguna: no hay specs previas en `openspec/specs/`.

## Impact

- **Código nuevo**: estructura Rails completa (`app/`, `bin/`, `config/`, `lib/`, `log/`, `public/`, `tmp/`, `vendor/`, `Gemfile`, `Gemfile.lock`, `Rakefile`, `config.ru`), `app/services/application_service.rb`, `spec/` y `.rspec`.
- **Configuración nueva**: `.ruby-version`, `.gitignore`, `.gitattributes`, `.rubocop.yml`, `config/ci.rb`, `config/bundler-audit.yml`, `.github/workflows/ci.yml`, `.github/dependabot.yml`.
- **Dependencias**: `rails 8.1.4` y las que trae el generador, más `rspec-rails ~> 8.0` en los grupos `development` y `test`, sin prereleases. Las versiones efectivamente resueltas se registran durante la implementación. Faraday queda para el segundo cambio.
- **Archivos preexistentes**: `.tool-versions`, `.claude/` y `openspec/` no se modifican, y el historial de Git se conserva. Los artefactos de este cambio solo admiten las actualizaciones deliberadas del checklist de `tasks.md` y del registro de evidencia de `design.md`. El diseño detalla cómo comprobarlo.
- **Sistemas externos**: GitHub Actions. Hoy el repositorio no tiene remoto configurado. En este cambio la configuración del workflow se inspecciona y las verificaciones equivalentes se ejecutan en local; la ejecución en GitHub queda registrada como pendiente y no se da por comprobada.
- **Cierre**: la implementación local puede darse por terminada cuando pasan sus verificaciones locales y de inspección. La verificación desde un clon limpio (local, después del commit) y la ejecución del CI en GitHub quedan registradas explícitamente como pendientes. El cambio permanece abierto, sin archivar, hasta comprobar el CI en GitHub (ver diseño, D12).
