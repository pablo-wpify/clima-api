# development-environment Specification

## Purpose

Garantiza que otra persona pueda reproducir el entorno de Clima API desde cero, con una única versión de Ruby declarada y comandos documentados que funcionan tal como están escritos.

## Requirements

### Requirement: Versión única de Ruby
El proyecto SHALL declarar la versión de Ruby 4.0.9 de forma coherente en todos los archivos que la expresan. La resolución de dependencias MUST rechazar una versión de Ruby distinta de la declarada.

#### Scenario: Archivos de versión coherentes
- **WHEN** se comparan la versión de Ruby de `.tool-versions` y la de `.ruby-version`
- **THEN** ambas indican `4.0.9`

#### Scenario: Dependencias atadas a la versión declarada
- **WHEN** se inspecciona la definición de dependencias del proyecto
- **THEN** la versión de Ruby se toma de `.ruby-version` y no se repite como literal

#### Scenario: Ruby distinto del declarado
- **WHEN** se intenta resolver o cargar las dependencias con una versión de Ruby distinta de 4.0.9
- **THEN** la operación falla con un mensaje que indica la discrepancia de versión

### Requirement: Instrucciones reproducibles
El README SHALL documentar los prerrequisitos y los comandos para instalar dependencias, ejecutar la suite de pruebas, ejecutar los análisis estáticos y de seguridad, levantar el servidor y comprobar la ruta de salud. Cada comando documentado MUST funcionar tal como está escrito desde el entorno preparado.

#### Scenario: Recorrido desde un clon limpio
- **WHEN** una persona con el gestor de versiones del proyecto y Ruby 4.0.9 instalados sigue el README desde un clon limpio
- **THEN** cada comando documentado termina con éxito y la ruta de salud responde con estado HTTP 200

#### Scenario: Comando de pruebas documentado
- **WHEN** se ejecuta el comando de pruebas tal como figura en el README
- **THEN** la suite corre al menos un ejemplo y termina sin fallos

### Requirement: Suite de pruebas efectiva
El proyecto SHALL tener una única suite de pruebas automática, ejecutable con un solo comando, que reporte la cantidad de ejemplos ejecutados y termine con código distinto de cero cuando algún ejemplo falla.

#### Scenario: Suite en verde
- **WHEN** se ejecuta el comando de pruebas sin cambios en el código
- **THEN** reporta más de cero ejemplos, cero fallos y termina con código 0

#### Scenario: Un fallo se detecta
- **WHEN** un ejemplo de la suite falla
- **THEN** el comando de pruebas termina con código distinto de 0

#### Scenario: Sin suite paralela
- **WHEN** se inspecciona el repositorio
- **THEN** no existe una segunda suite de pruebas generada por defecto que no se ejecute con el comando documentado
