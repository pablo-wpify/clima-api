# continuous-integration Specification

## Purpose

Verifica automáticamente cada cambio propuesto o integrado a la rama principal, con las mismas pruebas y comprobaciones que se ejecutan en local.

## Requirements

### Requirement: Disparadores de la integración continua
La integración continua SHALL ejecutarse en cada pull request y en cada push a la rama `main`.

#### Scenario: Disparadores declarados
- **WHEN** se inspecciona la configuración del workflow de integración continua
- **THEN** declara como disparadores los pull requests y los push a `main`

#### Scenario: Push a main
- **WHEN** se hace push de commits a `main` en el repositorio remoto
- **THEN** se ejecuta el workflow de integración continua

#### Scenario: Pull request
- **WHEN** se abre o se actualiza un pull request en el repositorio remoto
- **THEN** se ejecuta el workflow de integración continua

### Requirement: Pruebas con el comando documentado
La integración continua SHALL ejecutar la suite de pruebas con exactamente el mismo comando que el README documenta para local, usando la versión de Ruby declarada en `.ruby-version`. Un fallo de la suite MUST hacer fallar el workflow.

#### Scenario: Mismo comando que en local
- **WHEN** se compara el paso de pruebas del workflow con el comando de pruebas del README
- **THEN** ambos son idénticos, sin opciones adicionales

#### Scenario: Versión de Ruby del workflow
- **WHEN** se inspecciona cómo el workflow prepara Ruby
- **THEN** toma la versión de `.ruby-version` sin repetirla como literal

#### Scenario: Suite con fallos
- **WHEN** algún ejemplo de la suite falla durante una ejecución del workflow
- **THEN** el job de pruebas termina en estado fallido

### Requirement: Análisis estáticos y de seguridad
La integración continua SHALL ejecutar el análisis de estilo, el análisis estático de seguridad y la auditoría de vulnerabilidades conocidas en dependencias con las mismas herramientas y configuración que el README documenta para local. Las diferencias con los comandos locales MUST limitarse a opciones de presentación de la salida y MUST NOT omitir archivos, reglas ni comprobaciones.

#### Scenario: Diferencias solo de presentación
- **WHEN** se comparan los comandos de análisis del workflow con los del README
- **THEN** usan las mismas herramientas y configuración, y solo difieren en opciones de formato, paginación o verbosidad de la salida

#### Scenario: Hallazgo bloqueante
- **WHEN** un análisis encuentra un hallazgo bloqueante durante una ejecución del workflow
- **THEN** el workflow termina en estado fallido

### Requirement: Verificación local equivalente
El proyecto SHALL ofrecer un comando local que ejecute la misma secuencia de comprobaciones que la integración continua, incluida la suite de pruebas con el comando documentado.

#### Scenario: Verificación local completa
- **WHEN** se ejecuta el comando local de verificación
- **THEN** corre el análisis de estilo, los análisis de seguridad y la suite de pruebas, y termina con código 0 solo si todos pasan
