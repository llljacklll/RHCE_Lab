#!/bin/bash
# ============================================================
#  core/checkers/check_permissions.sh — plugin: permisos
# ------------------------------------------------------------
#  QUÉ VALIDA: los permisos NUMÉRICOS exactos de un archivo.
#    $1 = node .. contenedor a comprobar
#    $2 = name .. permisos esperados en forma numérica
#                  ("640": lo que debe dejar el chmod)
#    $3 = path .. ruta del archivo a inspeccionar (el único
#                  plugin donde $3 ES literalmente una ruta)
#  SALIDA: "OK" o "FAIL <razón>" (1 línea, stdout).
#  DETALLE: stat -c %a devuelve el modo octal SIN ceros de
#  relleno ni sufijos (640, no 0640 ni -rw-r-----): el YAML
#  debe pedirlo también sin cero inicial. Comparación de
#  cadena exacta.
# ============================================================
local node="$1"; local expected_perms="$2"; local path="$3"
local actual_perms
actual_perms=$(docker exec "$node" stat -c "%a" "$path" 2>/dev/null)
if [ -z "$actual_perms" ]; then
    echo "FAIL el fichero $path no existe en $node (stat sin respuesta)"
elif [ "$actual_perms" != "$expected_perms" ]; then
    echo "FAIL $path tiene permisos $actual_perms (se pedían $expected_perms) en $node"
else
    echo "OK"
fi
