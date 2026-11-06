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
