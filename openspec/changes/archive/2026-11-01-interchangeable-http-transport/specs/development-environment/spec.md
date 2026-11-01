# Spec Delta

## MODIFIED Requirements

### Requirement: Suite de pruebas sin peticiones HTTP reales
Durante la suite de pruebas, las peticiones HTTP que se hagan con las bibliotecas interceptadas por la herramienta de bloqueo configurada SHALL quedar bloqueadas, salvo las simuladas explícitamente. Un intento sin simulación MUST fallar de forma visible. Esto no garantiza el aislamiento de sockets, DNS ni otras conexiones del sistema operativo fuera de esas bibliotecas.

#### Scenario: Petición sin simulación bloqueada
- **WHEN** una prueba hace una petición HTTP real con Net::HTTP a un host externo sin una respuesta simulada
- **THEN** la petición no se envía y la prueba recibe un error que identifica la conexión bloqueada

#### Scenario: Petición sin simulación con HTTP.rb bloqueada
- **WHEN** una prueba hace una petición HTTP real con HTTP.rb a un host externo sin una respuesta simulada
- **THEN** la petición no se envía y la prueba recibe un error que identifica la conexión bloqueada

#### Scenario: Suite con el bloqueo habilitado
- **WHEN** se ejecuta la suite completa con la configuración de bloqueo habilitada
- **THEN** todos los ejemplos pasan usando solo respuestas simuladas para el proveedor externo

#### Scenario: Grupo local separado
- **WHEN** se ejecuta el comando de pruebas documentado sin opciones adicionales
- **THEN** no se ejecuta ningún ejemplo del grupo de comprobación contra un servidor en `127.0.0.1`, y ese grupo solo se ejecuta con el comando separado que documenta el README

#### Scenario: Alcance del grupo local
- **WHEN** se ejecuta el grupo de comprobación contra `127.0.0.1`
- **THEN** solo se permiten conexiones a los servidores locales que el propio grupo abre y cierra, con tiempos acotados, y las demás peticiones siguen bloqueadas

#### Scenario: Comprobación real separada
- **WHEN** se quiere verificar la integración con el proveedor real
- **THEN** existe un procedimiento manual documentado, fuera de la suite, que consulta el servicio real con cada uno de los transportes disponibles
