# Spec Delta

## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Petición al proveedor controlada por la aplicación
Cada consulta válida SHALL hacer un único intento de petición a `https://api.open-meteo.com/v1/forecast`, con parámetros definidos por la aplicación: las coordenadas validadas, las variables `temperature_2m` y `wind_speed_10m`, las unidades Celsius y km/h, y la zona horaria GMT. Si la solicitud llega al proveedor, MUST recibirse una sola petición; un fallo previo de DNS o de conexión puede impedir que se envíe. MUST NOT seguir redirects, reintentar ni usar caché.

#### Scenario: Parámetros enviados
- **WHEN** se consulta con coordenadas válidas
- **THEN** el proveedor recibe una sola petición cuyas claves y valores son exactamente `latitude`, `longitude`, `current=temperature_2m,wind_speed_10m`, `temperature_unit=celsius`, `wind_speed_unit=kmh` y `timezone=GMT`, sin ningún otro parámetro y sin importar el orden en que aparezcan

#### Scenario: Redirect del proveedor
- **WHEN** el proveedor responde con un redirect (HTTP 3xx)
- **THEN** no se sigue y la respuesta es HTTP 502 con `code` `provider_error`
