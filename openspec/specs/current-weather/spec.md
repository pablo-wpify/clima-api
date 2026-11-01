# current-weather Specification

## Purpose

Permite consultar por HTTP el clima actual de un punto geográfico, con unidades explícitas, fecha en UTC, la procedencia de los datos y un contrato de errores propio que no expone detalles del proveedor.

## Requirements

### Requirement: Consulta de clima actual por coordenadas
El sistema SHALL responder `GET /api/v1/weather` con `latitude` y `longitude` válidas con HTTP 200 y un JSON con `requested_coordinates`, `model_coordinates`, `temperature_celsius`, `wind_speed_kmh`, `valid_at` y `source`. Los valores de temperatura y viento MUST ser números.

#### Scenario: Consulta exitosa
- **WHEN** un cliente pide `GET /api/v1/weather?latitude=-37.32&longitude=-59.13` y el proveedor responde con datos completos y válidos
- **THEN** recibe HTTP 200 con `temperature_celsius` y `wind_speed_kmh` numéricos, `valid_at`, `requested_coordinates`, `model_coordinates` y `source`

#### Scenario: Unidades fijas
- **WHEN** la consulta es exitosa
- **THEN** la temperatura se expresa en grados Celsius y la velocidad del viento en kilómetros por hora, tal como indican los nombres de los campos

### Requirement: Coordenadas pedidas y coordenadas del modelo
La respuesta SHALL incluir `requested_coordinates` con la latitud y la longitud validadas, convertidas a número de punto flotante (`Float`), y `model_coordinates` con la latitud y la longitud del punto de grilla que informa el proveedor. Cada objeto MUST tener exactamente las claves `latitude` y `longitude`. La conversión a `Float` puede redondear valores con más precisión de la que ese tipo representa.

#### Scenario: Coordenadas distintas
- **WHEN** se piden las coordenadas `-37.32, -59.13` y el proveedor informa el punto `-37.2935, -59.08487`
- **THEN** `requested_coordinates` es `{"latitude": -37.32, "longitude": -59.13}` y `model_coordinates` es `{"latitude": -37.2935, "longitude": -59.08487}`

#### Scenario: Redondeo de la coordenada pedida
- **WHEN** se pide `latitude=12.345678901234567890123`
- **THEN** la coordenada se acepta y `requested_coordinates.latitude` es el `Float` más cercano a ese valor, no el texto original

### Requirement: Fecha del dato en UTC
`valid_at` SHALL indicar el momento para el que el proveedor declara válido el dato. Se expresa en UTC, en ISO 8601 con segundos y sufijo `Z`.

#### Scenario: Fecha expresada en UTC
- **WHEN** el proveedor informa que el dato es válido a las 15:00 UTC del 31 de octubre de 2026
- **THEN** `valid_at` es `"2026-10-31T15:00:00Z"`

### Requirement: Fecha del proveedor estricta, sin normalización
La fecha del proveedor SHALL tener exactamente el formato `AAAA-MM-DDTHH:MM` y representar un instante real del calendario, con mes de 01 a 12, un día que exista en ese mes y año, hora de 00 a 23 y minuto de 00 a 59. Una fecha imposible MUST tratarse como respuesta inválida del proveedor y MUST NOT corregirse ni trasladarse a otro instante.

#### Scenario: Fecha válida
- **WHEN** el proveedor informa `"time": "2026-10-31T15:00"`
- **THEN** `valid_at` es `"2026-10-31T15:00:00Z"`

#### Scenario: Día inexistente
- **WHEN** el proveedor informa `"time": "2026-02-30T15:00"`
- **THEN** la respuesta es HTTP 502 con `code` `provider_invalid_response`, y no `valid_at` `"2026-03-02T15:00:00Z"`

#### Scenario: Mes 13
- **WHEN** el proveedor informa `"time": "2026-13-01T15:00"`
- **THEN** la respuesta es HTTP 502 con `code` `provider_invalid_response`

#### Scenario: Hora 24
- **WHEN** el proveedor informa `"time": "2026-10-31T24:00"`
- **THEN** la respuesta es HTTP 502 con `code` `provider_invalid_response`, y no `valid_at` `"2026-11-01T00:00:00Z"`

#### Scenario: Minuto 60
- **WHEN** el proveedor informa `"time": "2026-10-31T15:60"`
- **THEN** la respuesta es HTTP 502 con `code` `provider_invalid_response`

### Requirement: Procedencia y naturaleza de los datos
`source` SHALL identificar al proveedor y declarar que los valores son datos de modelo meteorológico y no mediciones observadas. La respuesta MUST NOT usar campos ni textos que presenten los valores como observaciones.

#### Scenario: Datos de modelo declarados
- **WHEN** la consulta es exitosa
- **THEN** `source.provider` es `"Open-Meteo"` y `source.data_type` es `"model"`

#### Scenario: Sin lenguaje de observación
- **WHEN** se inspeccionan los nombres de campo de la respuesta exitosa
- **THEN** ninguno se refiere a una medición observada (por ejemplo, `observed_at` u `observation`)

### Requirement: Atribución de Open-Meteo
Toda respuesta exitosa SHALL incluir, dentro de `source`, el texto de atribución, el enlace a Open-Meteo, el nombre de la licencia CC BY 4.0 y el enlace a esa licencia. El README MUST documentar la misma atribución, la licencia, las condiciones de uso y las modificaciones que la API aplica a los datos.

#### Scenario: Atribución en la respuesta
- **WHEN** la consulta es exitosa
- **THEN** `source` incluye `attribution`, `url`, `license` y `license_url` con los valores definidos para Open-Meteo y CC BY 4.0

#### Scenario: Atribución en el README
- **WHEN** se lee la sección del endpoint de clima en el README
- **THEN** figuran la atribución con enlace a Open-Meteo, la licencia CC BY 4.0 con su enlace, las condiciones de uso no comercial y las modificaciones aplicadas a los datos

### Requirement: Formato aceptado de coordenadas
Cada coordenada SHALL ser texto con un número decimal: un signo `-` opcional, uno o más dígitos y, opcionalmente, un punto seguido de uno o más dígitos, sin límite de decimales. MUST rechazarse cualquier otro formato, incluidos `+`, espacios, comas, exponentes, hexadecimales, `NaN` e `Infinity`, y también los valores que no sean texto.

#### Scenario: Formatos aceptados
- **WHEN** `latitude` y `longitude` valen `-37.32`, `0`, `-0`, `45` o `12.345678901234`
- **THEN** la coordenada se considera bien formada

#### Scenario: Formatos rechazados
- **WHEN** una coordenada vale `abc`, `1,5`, `+10`, ` 10`, `10 `, `1.`, `.5`, `1e2`, `0x10`, `NaN` o `Infinity`
- **THEN** la respuesta es HTTP 400 con `code` `invalid_parameters` y el campo marcado con `invalid_format`

#### Scenario: Arrays y objetos
- **WHEN** una coordenada llega como array (`latitude[]=1`) o como objeto (`latitude[a]=1`)
- **THEN** la respuesta es HTTP 400 con el campo marcado con `invalid_type`

### Requirement: Presencia y rango de coordenadas
`latitude` y `longitude` SHALL ser obligatorias. La latitud MUST estar entre -90 y 90 y la longitud entre -180 y 180, con los límites incluidos. El rango se evalúa sobre el valor decimal exacto escrito, sin redondear.

#### Scenario: Coordenada ausente o vacía
- **WHEN** falta `latitude`, o vale una cadena vacía o solo espacios
- **THEN** la respuesta es HTTP 400 con el campo marcado con `missing` o `blank` según el caso

#### Scenario: Límites válidos
- **WHEN** la latitud vale `90` o `-90` y la longitud `180` o `-180`
- **THEN** las coordenadas se aceptan

#### Scenario: Fuera de rango
- **WHEN** la latitud vale `90.0000000000000000001` o `-91`, o la longitud vale `180.5`
- **THEN** la respuesta es HTTP 400 con el campo marcado con `out_of_range`

### Requirement: Respuesta ante entrada inválida
Ante coordenadas inválidas, el sistema SHALL responder HTTP 400 con `error.code` `invalid_parameters`, un `error.message` y `error.details` con un elemento por cada campo inválido (`field` e `issue`). MUST NOT consultar al proveedor.

#### Scenario: Varios campos inválidos
- **WHEN** falta `latitude` y `longitude` vale `abc`
- **THEN** `error.details` contiene `{"field": "latitude", "issue": "missing"}` y `{"field": "longitude", "issue": "invalid_format"}`

#### Scenario: Sin consulta al proveedor
- **WHEN** la entrada es inválida
- **THEN** no se realiza ninguna petición a Open-Meteo

### Requirement: Parámetros desconocidos y repetidos
El sistema SHALL ignorar los parámetros de consulta distintos de `latitude` y `longitude`, sin reenviarlos al proveedor. Cuando una coordenada se repite, MUST usar el valor que entrega Rails, es decir, el último.

#### Scenario: Parámetro desconocido
- **WHEN** la consulta incluye además `current=precipitation` o `url=https://example.com`
- **THEN** la respuesta es la misma que sin ese parámetro y la petición al proveedor no lo contiene

#### Scenario: Clave repetida
- **WHEN** la consulta es `latitude=10&latitude=-37.32&longitude=-59.13`
- **THEN** se usa `-37.32` como latitud

### Requirement: Petición al proveedor controlada por la aplicación
Cada consulta válida SHALL hacer un único intento de petición a `https://api.open-meteo.com/v1/forecast`, con parámetros definidos por la aplicación: las coordenadas validadas, las variables `temperature_2m` y `wind_speed_10m`, las unidades Celsius y km/h, y la zona horaria GMT. Si la solicitud llega al proveedor, MUST recibirse una sola petición; un fallo previo de DNS o de conexión puede impedir que se envíe. MUST NOT seguir redirects, reintentar ni usar caché.

#### Scenario: Parámetros enviados
- **WHEN** se consulta con coordenadas válidas
- **THEN** el proveedor recibe una sola petición cuyas claves y valores son exactamente `latitude`, `longitude`, `current=temperature_2m,wind_speed_10m`, `temperature_unit=celsius`, `wind_speed_unit=kmh` y `timezone=GMT`, sin ningún otro parámetro y sin importar el orden en que aparezcan

#### Scenario: Redirect del proveedor
- **WHEN** el proveedor responde con un redirect (HTTP 3xx)
- **THEN** no se sigue y la respuesta es HTTP 502 con `code` `provider_error`

### Requirement: Timeout del proveedor
Si el proveedor no responde dentro del tiempo configurado, ya sea al conectar o al leer, el sistema SHALL responder HTTP 504 con `error.code` `provider_timeout`.

#### Scenario: Timeout al leer
- **WHEN** la lectura de la respuesta del proveedor supera el tiempo configurado
- **THEN** la respuesta es HTTP 504 con `code` `provider_timeout`

#### Scenario: Timeout al conectar
- **WHEN** la conexión con el proveedor supera el tiempo configurado
- **THEN** la respuesta es HTTP 504 con `code` `provider_timeout`

### Requirement: Límite de uso del proveedor
Si el proveedor responde HTTP 429, el sistema SHALL responder HTTP 503 con `error.code` `provider_rate_limited`.

#### Scenario: Proveedor limitado
- **WHEN** el proveedor responde HTTP 429
- **THEN** la respuesta es HTTP 503 con `code` `provider_rate_limited`

### Requirement: Otros fallos del proveedor
El sistema SHALL responder HTTP 502 cuando falla el proveedor por otras causas, con un `error.code` que identifique la causa: `provider_unavailable` (conexión fallida o error TLS), `provider_error` (HTTP distinto de 2xx y de 429) o `provider_invalid_response` (respuesta inválida).

#### Scenario: Conexión fallida
- **WHEN** no se puede establecer la conexión con el proveedor por un motivo distinto del timeout
- **THEN** la respuesta es HTTP 502 con `code` `provider_unavailable`

#### Scenario: Error HTTP del proveedor
- **WHEN** el proveedor responde HTTP 400 o HTTP 500
- **THEN** la respuesta es HTTP 502 con `code` `provider_error`

### Requirement: Estructura del payload del proveedor
El cuerpo JSON del proveedor SHALL ser un objeto, y `current` y `current_units` MUST ser objetos JSON. Si alguno falta, es `null`, un array, un texto, un número o un booleano, el sistema MUST responder HTTP 502 con `provider_invalid_response`, nunca con un error interno (HTTP 500).

#### Scenario: current ausente o null
- **WHEN** el cuerpo del proveedor no tiene `current`, o tiene `"current": null`
- **THEN** la respuesta es HTTP 502 con `code` `provider_invalid_response`

#### Scenario: current con tipo incorrecto
- **WHEN** `current` llega como array (`[]`), texto (`"x"`) o booleano (`true`)
- **THEN** la respuesta es HTTP 502 con `code` `provider_invalid_response`

#### Scenario: current_units ausente o con tipo incorrecto
- **WHEN** `current_units` falta o llega como `null`, array, texto o booleano
- **THEN** la respuesta es HTTP 502 con `code` `provider_invalid_response`

#### Scenario: Cuerpo JSON que no es un objeto
- **WHEN** el proveedor responde HTTP 200 con un array JSON (`[]`) o un texto JSON (`"ok"`)
- **THEN** la respuesta es HTTP 502 con `code` `provider_invalid_response`

### Requirement: Respuesta inválida del proveedor sin éxito parcial
El sistema SHALL tratar como inválida una respuesta 2xx del proveedor cuyo cuerpo no sea JSON o cuyos campos requeridos falten, sean `null`, tengan un tipo incorrecto, no sean finitos, tengan unidades distintas de `°C` y `km/h` o una fecha ilegible o fuera de UTC. En esos casos MUST responder HTTP 502 con `provider_invalid_response`, sin datos parciales.

#### Scenario: Campo ausente o null
- **WHEN** falta `wind_speed_10m` o llega `"temperature_2m": null`
- **THEN** la respuesta es HTTP 502 con `code` `provider_invalid_response` y sin `temperature_celsius` ni `wind_speed_kmh`

#### Scenario: Tipo o unidad incorrectos
- **WHEN** `temperature_2m` llega como texto `"17.6"`, o `current_units.temperature_2m` es `"°F"`
- **THEN** la respuesta es HTTP 502 con `code` `provider_invalid_response`

#### Scenario: Cuerpo que no es JSON
- **WHEN** el proveedor responde HTTP 200 con un cuerpo que no es JSON
- **THEN** la respuesta es HTTP 502 con `code` `provider_invalid_response`

### Requirement: Errores sin detalles internos ni externos
Toda respuesta de error SHALL tener la forma `{"error": {"code": …, "message": …}}`, con `details` solo para la entrada inválida. MUST NOT incluir el cuerpo de la respuesta del proveedor, sus mensajes de error, mensajes de excepciones, clases internas ni trazas.

#### Scenario: Mensaje del proveedor no expuesto
- **WHEN** el proveedor responde HTTP 400 con `{"error": true, "reason": "Latitude must be in range"}`
- **THEN** la respuesta de la API no contiene el texto de `reason` ni el cuerpo del proveedor

#### Scenario: Excepción no expuesta
- **WHEN** la conexión falla con una excepción de red
- **THEN** la respuesta de la API no contiene el mensaje ni el nombre de clase de esa excepción

### Requirement: Resultado del caso de uso de clima actual
La consulta del clima actual SHALL devolver un resultado que indica con un booleano si tuvo éxito. En el éxito, el resultado MUST contener los datos meteorológicos y ningún error. En un fallo previsto del proveedor, MUST contener uno de los códigos públicos de error del proveedor y su mensaje público, sin datos.

#### Scenario: Éxito
- **WHEN** el proveedor responde con datos completos y válidos
- **THEN** el resultado indica éxito con el valor `true`, contiene los datos meteorológicos y no tiene código ni mensaje de error

#### Scenario: Fallo previsto
- **WHEN** el proveedor no responde dentro del tiempo configurado
- **THEN** el resultado indica éxito con el valor `false`, no contiene datos y tiene el código `provider_timeout` y el mensaje público de ese error

#### Scenario: Códigos y mensajes conservados
- **WHEN** el fallo previsto es un timeout, un límite de uso, una conexión fallida, un error HTTP o una respuesta inválida
- **THEN** el código es `provider_timeout`, `provider_rate_limited`, `provider_unavailable`, `provider_error` o `provider_invalid_response`, respectivamente, con el mismo mensaje que la API devuelve hoy para ese código

### Requirement: Resultado sin estados contradictorios
El resultado SHALL rechazar al construirse cualquier combinación distinta de un éxito con datos meteorológicos y sin error, o de un fallo sin datos, con un código conocido y un mensaje no vacío. El indicador de éxito MUST derivarse del contenido y no guardarse como un dato independiente.

#### Scenario: Éxito con código de error
- **WHEN** se intenta construir un resultado con datos meteorológicos y un código de error
- **THEN** la construcción falla con un error de programación

#### Scenario: Fallo sin mensaje o con código desconocido
- **WHEN** se intenta construir un fallo con mensaje vacío o con un código que no es uno de los cinco códigos públicos del proveedor
- **THEN** la construcción falla con un error de programación

#### Scenario: Éxito sin datos meteorológicos
- **WHEN** se intenta construir un éxito sin datos o con un objeto que no son datos meteorológicos
- **THEN** la construcción falla con un error de programación

### Requirement: Solo los fallos previstos se convierten en resultado
La consulta del clima SHALL convertir en resultado de fallo únicamente los fallos previstos del proveedor: timeout, límite de uso, conexión fallida, error HTTP y respuesta inválida. Cualquier otro error MUST propagarse sin convertirse en un resultado. La validación de las coordenadas de entrada MUST mantener su respuesta HTTP 400 actual y ocurrir antes de consultar.

#### Scenario: Error de programación
- **WHEN** durante la consulta ocurre un error que no es un fallo previsto del proveedor
- **THEN** ese error se propaga y no se devuelve un resultado de fallo

#### Scenario: Coordenadas inválidas
- **WHEN** la petición a la API tiene coordenadas inválidas
- **THEN** la respuesta sigue siendo HTTP 400 `invalid_parameters` con sus `details` y no se consulta al proveedor
