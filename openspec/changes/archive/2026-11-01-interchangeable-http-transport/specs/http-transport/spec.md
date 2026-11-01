# Spec Delta

## Purpose

Define un contrato propio para las peticiones HTTP a proveedores externos, de modo que la biblioteca que las realiza pueda elegirse por inyección sin cambiar las reglas del proveedor ni el caso de uso, y sin que sus tipos y excepciones salgan del transporte.

## ADDED Requirements

### Requirement: Petición GET y respuesta completa
El transporte SHALL ofrecer una petición GET que recibe una URL absoluta, los parámetros de consulta y los encabezados, y devuelve una respuesta con el estado HTTP como número entero y el cuerpo como texto ya leído por completo. Leer la respuesta MUST NOT requerir nuevas operaciones de red.

#### Scenario: Respuesta exitosa
- **WHEN** el servidor responde HTTP 200 con un cuerpo JSON
- **THEN** la respuesta tiene estado `200` (entero) y el cuerpo completo como texto

#### Scenario: Parámetros y encabezados enviados
- **WHEN** se pide una URL con parámetros de consulta y el encabezado `Accept: application/json`
- **THEN** el servidor recibe una petición GET a esa URL con exactamente esos parámetros y ese encabezado

#### Scenario: Cuerpo vacío
- **WHEN** el servidor responde sin cuerpo
- **THEN** la respuesta tiene el cuerpo como texto vacío, no como valor nulo

### Requirement: Estados HTTP como respuestas
Cualquier estado HTTP recibido, incluidos 3xx, 4xx y 5xx, SHALL entregarse como respuesta y no como error del transporte. Interpretar el estado MUST quedar a cargo de quien usa el transporte.

#### Scenario: Error del servidor
- **WHEN** el servidor responde HTTP 500 o HTTP 429
- **THEN** el transporte devuelve una respuesta con ese estado y su cuerpo, sin lanzar un error

#### Scenario: Error del cliente
- **WHEN** el servidor responde HTTP 400 con un cuerpo de error
- **THEN** el transporte devuelve una respuesta con estado 400 y ese cuerpo

### Requirement: Un único intento, sin reintentos ni redirects
Cada petición del transporte SHALL hacer un único intento. MUST NOT reintentar ni seguir redirects, ni ante un estado de error ni ante un fallo de comunicación. Si el servidor llega a recibir la solicitud, MUST recibir una sola petición; ante un fallo de resolución o una conexión rechazada puede no haberse enviado ninguna petición HTTP.

#### Scenario: Redirect
- **WHEN** el servidor responde HTTP 301 con un encabezado `Location`
- **THEN** el transporte devuelve la respuesta 301 y no hace ninguna petición a la dirección de `Location`

#### Scenario: Error sin reintento
- **WHEN** el servidor responde HTTP 500
- **THEN** el servidor recibió una sola petición

#### Scenario: Timeout sin reintento
- **WHEN** la lectura de la respuesta supera el tiempo configurado
- **THEN** el servidor recibió una sola petición y el transporte no hizo otro intento

#### Scenario: Conexión rechazada sin reintento
- **WHEN** nadie escucha en el puerto de destino
- **THEN** el transporte informa la conexión fallida después de un único intento, sin haber enviado una petición HTTP

### Requirement: Fallos de comunicación previstos
El transporte SHALL traducir un timeout al conectar, durante el handshake TLS o al leer, incluido el cuerpo, a un error de timeout propio. Una conexión rechazada, un fallo de resolución, una conexión cortada o un error TLS MUST traducirse a un error de conexión fallida propio. Cualquier otro error es inesperado y MUST propagarse sin traducir, con su tipo original.

#### Scenario: Timeout de lectura antes de los encabezados
- **WHEN** el servidor acepta la conexión y no envía nada durante más tiempo que el límite de lectura
- **THEN** el transporte lanza su error de timeout

#### Scenario: Timeout de lectura durante el cuerpo
- **WHEN** el servidor envía los encabezados y deja de enviar el cuerpo durante más tiempo que el límite de lectura
- **THEN** el transporte lanza su error de timeout y no devuelve una respuesta parcial

#### Scenario: Conexión rechazada
- **WHEN** nadie escucha en el puerto de destino
- **THEN** el transporte lanza su error de conexión fallida

#### Scenario: Error TLS
- **WHEN** la negociación TLS falla
- **THEN** el transporte lanza su error de conexión fallida

#### Scenario: Error inesperado
- **WHEN** la biblioteca lanza un error que no corresponde a un fallo de comunicación previsto
- **THEN** ese error se propaga con su tipo original, sin convertirse en timeout ni en conexión fallida

### Requirement: Respuestas y fallos previstos con tipos propios
Las respuestas y los fallos previstos del contrato SHALL usar tipos propios del proyecto. MUST NOT devolver objetos de respuesta de la biblioteca HTTP usada ni comunicar un fallo previsto con una excepción de esa biblioteca. Los mensajes de esos errores propios MUST ser fijos y no incluir el mensaje original, que puede conservarse solo como causa para diagnóstico. Los errores inesperados no están alcanzados.

#### Scenario: Respuesta propia
- **WHEN** se inspecciona la clase de una respuesta del transporte
- **THEN** es la respuesta propia del proyecto, con independencia de la biblioteca usada

#### Scenario: Fallo previsto con tipo propio
- **WHEN** ocurre un timeout o una conexión fallida
- **THEN** el error lanzado es el error propio del transporte, no una excepción de la biblioteca

#### Scenario: Mensaje fijo
- **WHEN** una conexión rechazada produce un mensaje con detalles del socket
- **THEN** el error de conexión fallida tiene su mensaje fijo y no contiene esos detalles

### Requirement: Límites de tiempo de conexión y de lectura
El transporte usado para el proveedor SHALL configurarse con 2 segundos para establecer la conexión y 5 segundos para cada espera de lectura. Estos límites MUST NOT documentarse como una duración máxima total de la petición ni como cobertura de la resolución DNS mientras no exista evidencia de ello.

#### Scenario: Valores configurados
- **WHEN** se inspecciona el transporte predeterminado del proveedor
- **THEN** su límite de conexión es 2 segundos y su límite de lectura es 5 segundos

#### Scenario: Límites documentados
- **WHEN** se lee la documentación de los timeouts
- **THEN** explica que el límite de lectura se aplica a cada espera y no a la petición completa, y que la cobertura de DNS no está comprobada

### Requirement: Elección del transporte por inyección
El transporte SHALL elegirse inyectando una instancia en el cliente del proveedor. Sin inyección, MUST usarse el transporte basado en Faraday, elegido en un único punto explícito de construcción. La elección MUST NOT depender de parámetros de la petición HTTP ni de variables de entorno.

#### Scenario: Transporte predeterminado
- **WHEN** el cliente del proveedor se construye sin transporte
- **THEN** usa el transporte basado en Faraday

#### Scenario: Transporte inyectado
- **WHEN** el cliente del proveedor se construye con el transporte basado en HTTP.rb
- **THEN** todas sus peticiones pasan por ese transporte, sin cambios en el caso de uso ni en las reglas del proveedor

#### Scenario: Parámetro de la petición ignorado
- **WHEN** una petición a la API incluye un parámetro como `transport=http_rb`
- **THEN** el transporte usado no cambia

### Requirement: Intercambiabilidad verificada
Los transportes basados en Faraday y en HTTP.rb SHALL cumplir el mismo contrato y la API MUST responder igual con cualquiera de los dos en los escenarios verificados. La intercambiabilidad MUST afirmarse solo para ese contrato y esos escenarios, no como equivalencia general de las bibliotecas.

#### Scenario: Contrato compartido
- **WHEN** se ejecutan las pruebas del contrato del transporte con cada adaptador
- **THEN** ambos pasan las mismas pruebas

#### Scenario: Endpoint con ambos transportes
- **WHEN** se ejecutan las pruebas del contrato HTTP del endpoint de clima con cada transporte
- **THEN** los estados, los cuerpos y los códigos de error son los mismos
