#!/bin/bash
# ============================================================
#  core/checkers/check_file.sh — plugin: contenido de archivo
# ------------------------------------------------------------
#  QUÉ VALIDA: que un archivo del nodo contenga un patrón.
#
#  OJO — ESTE PLUGIN ROMPE EL MOLDE $1/$2/$3:
#    $1 = node ......... llega igual que en los demás,
#    $pattern, $path ... NO llegan como $2/$3: llegan por
#    SCOPING DINÁMICO de bash. Como _run_check carga este
#    fichero con "source" DENTRO de la cadena de llamadas de
#    grade.sh, el fragmento VE las variables locales del
#    llamador: el parser definió `path` y `pattern` al leer
#    las claves path:/contains: del YAML. Es el único plugin
#    que consume contains:, y se lo sirven digerido por
#    NOMBRE, no por posición.
#
#  SALIDA: "OK"/"FAIL" (una línea, stdout).
#  DETALLE: grep -q "$pattern" trata el contains del YAML
#  como REGEX BRE, no como cadena literal — un punto o un
#  pipe en el patrón significan lo que significan en grep.
# ============================================================
local node="$1"
docker exec "$node" grep -q "$pattern" "$path" 2>/dev/null && echo "OK" || echo "FAIL"
