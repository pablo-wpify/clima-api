# Clima API

API Rails educativa que, en un cambio posterior, consultará Open-Meteo a partir de coordenadas y devolverá temperatura y viento con unidades explícitas. Esta versión contiene solo la base: Rails 8.1.4 en modo API, sin base de datos, con RSpec y una ruta de salud.

El endpoint de clima todavía no existe; llega en un cambio posterior.

## Prerrequisitos

- [asdf](https://asdf-vm.com/) con Ruby 4.0.9 instalado. La versión está fijada en `.tool-versions` y `.ruby-version`, y el `Gemfile` la toma de `.ruby-version`.
- Si usás nvm y aparece antes que asdf en el `PATH`, desactivalo en la terminal de trabajo:

  ```sh
  nvm deactivate
  ```

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
