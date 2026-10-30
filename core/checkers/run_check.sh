#!/bin/bash
# ============================================================
#  core/checkers/run_check.sh — wrapper standalone de checkers
# ------------------------------------------------------------
#  Los plugins de core/checkers/ estan escritos para el
#  contrato de _run_check (grade.sh): se SOURCEAN dentro de
#  una funcion, y por eso usan 'local' en su cabecera. Con
#  'bash check_x.sh' directo ese 'local' revienta.
#  Este wrapper replica el contrato: sourcea el plugin dentro
#  de una funcion y le pasa los argumentos tal cual.
#
#  USO: run_check.sh <plugin> [args del checker...]
#    run_check.sh galaxy control 'collection:community.crypto'
#    run_check.sh repo node1 'docker-ce-stable'
#    SALIDA: la linea OK / FAIL del plugin.
# ============================================================
main() {
    local plugin="$1"
    shift
    source "$(dirname "$0")/check_${plugin}.sh" "$@"
}
main "$@"
