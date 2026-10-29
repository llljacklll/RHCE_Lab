#!/bin/bash
# ============================================================
#  core/checkers/check_symlink.sh — plugin: enlaces simbólicos
# ------------------------------------------------------------
#  QUÉ VALIDA: que exista el enlace simbólico pedido y que
#  apunte al destino correcto (el EX294 pide symlinks con
#  'ansible.builtin.file: state=link').
#
#  CONTRATO con _run_check (grade.sh), igual que TODA la
#  familia de core/checkers/:
#    $1 = node .. nodo a comprobar
#    $2 = name ... destino esperado del enlace (src)
#    $3 = path ... ruta del enlace (dest)
#    SALIDA: UNA línea en stdout, "OK" o "FAIL <razón>".
#
#  DETALLES:
#   - test -L y no test -e: un fichero regular en esa ruta
#     debe cantar FAIL, no colarse como enlace.
#   - Se acepta el destino tal cual (readlink) o resuelto
#     (readlink -f): cubre enlaces absolutos y relativos,
#     ambos válidos en el examen.
# ============================================================
local node="$1"; local target="$2"; local link="$3"
local got resolved
if [ -z "$link" ] || [ -z "$target" ]; then
    echo "FAIL faltan 'name:' (destino) o 'path:' (enlace) en el YAML"
elif ! docker exec "$node" test -L "$link" 2>/dev/null; then
    echo "FAIL $link no existe o no es un enlace simbólico en $node"
else
    got=$(docker exec "$node" readlink "$link" 2>/dev/null)
    resolved=$(docker exec "$node" readlink -f "$link" 2>/dev/null)
    if [ "$got" = "$target" ] || [ "$resolved" = "$target" ]; then
        echo "OK"
    else
        echo "FAIL $link apunta a '$got' (se esperaba $target)"
    fi
fi
