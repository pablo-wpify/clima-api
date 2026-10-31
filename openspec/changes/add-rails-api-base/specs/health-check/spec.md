# Spec Delta

## Purpose

Permite a personas, orquestadores y monitores saber por HTTP si la aplicación arrancó correctamente, sin depender de una base de datos ni de servicios externos.

## ADDED Requirements

### Requirement: La aplicación arranca sin base de datos
La aplicación SHALL iniciar y atender solicitudes en los entornos de desarrollo y de prueba sin una base de datos configurada ni disponible. El proyecto MUST NOT incluir configuración de conexión a base de datos.

#### Scenario: Arranque sin configuración de base de datos
- **WHEN** se inicia la aplicación en un entorno sin ninguna base de datos instalada ni configurada
- **THEN** la aplicación termina de arrancar sin errores y queda lista para atender solicitudes

#### Scenario: Ausencia de configuración de base de datos
- **WHEN** se inspecciona la configuración del proyecto
- **THEN** no existe archivo de configuración de conexión a base de datos ni directorio de migraciones o esquema

### Requirement: Ruta de salud HTTP
La aplicación SHALL exponer `GET /up` y responder con estado HTTP 200 cuando arrancó sin excepciones. La respuesta MUST NOT depender de servicios externos ni de una base de datos.

#### Scenario: Aplicación sana
- **WHEN** un cliente envía `GET /up` a la aplicación en ejecución
- **THEN** recibe una respuesta con estado HTTP 200

#### Scenario: Salud verificada por la suite automática
- **WHEN** se ejecuta la suite de pruebas
- **THEN** incluye una prueba que envía `GET /up` y verifica el estado HTTP 200

#### Scenario: Ruta inexistente
- **WHEN** un cliente envía `GET` a una ruta que la aplicación no define
- **THEN** recibe una respuesta con estado HTTP 404
