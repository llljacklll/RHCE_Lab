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
#  SALIDA: "OK" o "FAIL <razón>" (1 línea, stdout).
# ============================================================
local node="$1"; local group="$2"; local gid="${3:-}"
if [ -n "$gid" ]; then
    local actual
    actual=$(docker exec "$node" getent group "$group" 2>/dev/null | cut -d: -f3)
    if [ -z "$actual" ]; then
        echo "FAIL el grupo $group no existe en $node"
    elif [ "$actual" != "$gid" ]; then
        echo "FAIL $group existe pero su GID es $actual (se pedía $gid) en $node"
    else
        echo "OK"
    fi
else
    docker exec "$node" getent group "$group" >/dev/null 2>&1 && echo "OK" || echo "FAIL el grupo $group no existe en $node"
fi
