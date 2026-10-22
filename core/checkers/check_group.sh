#!/bin/bash
# ============================================================
#  core/checkers/check_group.sh — plugin: grupos del SO
# ------------------------------------------------------------
#  QUÉ VALIDA: que un grupo exista en el nodo, con GID exacto
#  opcional — el espejo de check_user para grupos.
#    $1 = node .. contenedor a comprobar
#    $2 = name .. nombre del grupo
#    $3 = path .. GID esperado, OPCIONAL
#  POR QUÉ getent Y NO /etc/group: getent consulta por NSS,
#  que es lo mismo que ve el sistema al resolver grupos (hoy
#  locales; mañana LDAP si un examen lo pide). El GID se saca
#  con cut -d: -f3 para la variante estricta.
#  SALIDA: "OK"/"FAIL" (una línea, stdout).
# ============================================================
local node="$1"; local group="$2"; local gid="${3:-}"
if [ -n "$gid" ]; then
    [ "$(docker exec "$node" getent group "$group" 2>/dev/null | cut -d: -f3)" = "$gid" ] && echo "OK" || echo "FAIL"
else
    docker exec "$node" getent group "$group" >/dev/null 2>&1 && echo "OK" || echo "FAIL"
fi
