# Clima API

API Rails educativa que consulta Open-Meteo a partir de coordenadas y devuelve el clima actual (temperatura y viento) con unidades explícitas. Usa Rails 8.1.4 en modo API, sin base de datos, con RSpec y una ruta de salud.

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

La suite usa [WebMock](https://github.com/bblimke/webmock) para bloquear las peticiones HTTP reales hechas con las bibliotecas que intercepta (entre ellas Net::HTTP, que usa Faraday). Las respuestas de Open-Meteo se simulan, así que las pruebas no consultan al proveedor. Esto no es un aislamiento de red del sistema operativo.

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

Cada consulta válida hace una sola petición a una URL fija de Open-Meteo, sin reintentos ni caché. Los tiempos de espera son de 2 segundos para conectar y de 5 segundos por lectura, pero no hay un límite garantizado para el total de la petición.

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
