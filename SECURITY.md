# Política de seguridad

## Alcance

RHCE_Lab es un entorno de práctica autocontenido. Las credenciales
débiles que verás (usuario `ansible` con contraseña `ansible`, valores
de vault de ejemplo como `app_secret=VaultEx294` o `ops_secret=RekeyEx294`)
son PARTE DEL DISEÑO: viven solo dentro de contenedores desechables en
tu propia MV y no deben reutilizarse en ningún sistema real.

## Cómo reportar

Usa el reporte privado de vulnerabilidades de GitHub
(Security -> Report a vulnerability). No abras issues públicas
describiendo problemas de seguridad.

## Excepción de escaneo de secretos (gitleaks 8.30.1)

| Campo | Valor |
|---|---|
| Regla | generic-api-key |
| Archivo | webui/static/xterm.min.js |
| Commit del hallazgo | f778191d (historial reescrito) |
| Identificación | sha256:f0aea0f75f48559013ae6643c2479dd737d26da42d5524e6d2b70915ae6523c7 |
| Versión | (no visible en el banner; identificada por sha256) |
| Justificación | Falso positivo: JS comprimido de xterm.js (terminal web), vendored para que el panel funcione sin internet. No contiene credenciales funcionales. |

La excepción está acotada a ESTE fichero: no es una exclusión genérica de
archivos JavaScript. Cualquier hallazgo nuevo fuera de esta ficha se
trata como un secreto real.
