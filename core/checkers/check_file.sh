#!/bin/bash
# ============================================================
#  core/checkers/check_file.sh — plugin: contenido de archivo
# ------------------------------------------------------------
#  QUÉ VALIDA: que un archivo del nodo contenga un patrón.
#
#  CONTRATO — posicional, idéntico a TODA la familia (así lo
#  documenta _run_check: "$1=nodo $2=name $3=path"):
#    $1 = node ...... contenedor a comprobar
#    $2 = pattern ... texto a buscar (en el YAML viaja como
#                     'name:' o su alias 'contains:')
#    $3 = path ...... ruta del fichero DENTRO del contenedor
#
#  SALIDA: "OK" o "FAIL <razón>" (1 línea, stdout). _run_check
#  (parche A1) ya pinta esa razón en el reporte: adiós al FAIL
#  mudo.
#
#  HISTORIA (bug cerrado): este plugin leía $pattern/$path por
#  "scoping dinámico" — variables que NUNCA existieron en el
#  motor: _run_check pasa (nodo, name, path) POSICIONALMENTE,
#  como todos los plugins. Efecto del contrato fantasma:
#  docker exec node1 grep -q '' '' → FAIL mudo en todo check
#  de tipo file (exam_002 task_2, exam_003 task_3).
#
#  DETALLE: grep -q trata el patrón como REGEX BRE, no como
#  cadena literal — un punto o un pipe significan lo que
#  significan en grep.
# ============================================================
local node="$1" pattern="$2" path="$3"

if [ -z "$path" ]; then
    echo "FAIL ruta vacía: falta 'path:' en el check del YAML"
elif [ -z "$pattern" ]; then
    echo "FAIL patrón vacío: falta 'name:'/'contains:' en el YAML"
elif ! docker exec "$node" test -e "$path" 2>/dev/null; then
    echo "FAIL el fichero $path no existe en $node"
elif ! docker exec "$node" grep -q -- "$pattern" "$path" 2>/dev/null; then
    echo "FAIL patrón no hallado dentro de $path ($node)"
else
    echo "OK"
fi
