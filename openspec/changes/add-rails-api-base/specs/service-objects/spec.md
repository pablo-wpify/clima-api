# Spec Delta

## Purpose

Define una única forma de invocar los servicios de la aplicación: una llamada de clase que construye el servicio con los argumentos recibidos y devuelve su resultado sin alterarlo.

## ADDED Requirements

### Requirement: Invocación de un servicio con una sola llamada
Todo servicio que herede de `ApplicationService` SHALL poder invocarse con `.call`. Esa llamada MUST construir una instancia con exactamente los argumentos recibidos y devolver, sin transformarlo, el resultado de `#call` de esa instancia.

#### Scenario: Reenvío de argumentos posicionales
- **WHEN** se invoca `.call` de un servicio con un argumento posicional
- **THEN** la instancia construida recibe ese mismo argumento en la misma posición

#### Scenario: Reenvío de argumentos keyword
- **WHEN** se invoca `.call` de un servicio con un argumento keyword
- **THEN** la instancia construida recibe ese mismo argumento con el mismo nombre y valor

#### Scenario: Retorno del resultado de la instancia
- **WHEN** `#call` de la instancia devuelve un objeto
- **THEN** `.call` de la clase devuelve ese mismo objeto
