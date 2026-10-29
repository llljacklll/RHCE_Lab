#!/bin/bash
# ============================================================
#  core/checkers/check_repo.sh — plugin: repositorio dnf/yum
# ------------------------------------------------------------
#  QUÉ VALIDA: que un repositorio dnf esté configurado Y
#  habilitado en el nodo (hueco #2 del intel EX294: "crea el
#  repo con este baseurl" fue pregunta real).
#
#  CONTRATO con _run_check (grade.sh), igual que TODA la
#  familia de core/checkers/:
#    $1 = node .. nodo donde comprobar el repo
#    $2 = name ... el ID del repo (p. ej. "docker-ce-stable")
#    $3 = path ... sin uso (reservado)
#    SALIDA: UNA línea en stdout, "OK" o "FAIL <razón>".
#
#  HONESTIDAD: se pregunta a DNF, no a los .repo del disco.
#  Un repo con enabled=1 pero baseurl roto NO aparece en
#  'dnf repolist --enabled' y aquí canta FAIL: un repo que
#  dnf no puede usar no está configurado de verdad. El coste
#  es descargar metadatos en la primera pasada (segundos);
#  es el precio de verificar estado real y no apariencia.
# ============================================================
local node="$1"; local repo="$2"
local out
if [ -z "$repo" ]; then
    echo "FAIL falta el id del repo ('name:' en el YAML)"
elif out=$(docker exec "$node" dnf -q repolist --enabled 2>/dev/null) \
     && printf '%s\n' "$out" | grep -qw "$repo"; then
    echo "OK"
else
    echo "FAIL el repo '$repo' no está habilitado en $node (dnf repolist)"
fi
