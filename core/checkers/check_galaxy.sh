#!/bin/bash
# ============================================================
#  core/checkers/check_galaxy.sh — plugin: colecciones y roles
# ------------------------------------------------------------
#  QUÉ VALIDA: que una colección o un rol de galaxy esté
#  instalado en CONTROL (hueco #4 del intel: pidieron modulos
#  de redhat.rhel_system_roles SIN dar el .tar.gz; hay que
#  vivir de 'ansible-galaxy ... list').
#
#  CONTRATO con _run_check (grade.sh), igual que TODA la
#  familia de core/checkers/:
#    $1 = node .. sin uso: el material galaxy vive en control.
#    $2 = name ... "collection:ns.nombre" o "role:nombre".
#    $3 = path ... version EXACTA exigida; OPCIONAL.
#    SALIDA: UNA línea en stdout, "OK" o "FAIL <razón>".
#
#  DETALLE: se lista con el HOME del usuario ansible Y de root
#  ('ansible-galaxy install' sin become escribe en
#  /home/ansible/.ansible y con become en /root/.ansible):
#  ambas son instalaciones válidas y no se discrimina.
# ============================================================
local spec="$2"; local ver="$3"
local kind item found
kind="${spec%%:*}"
item="${spec#*:}"
if [ -z "$spec" ] || [ "$spec" = "$kind" ]; then
    echo "FAIL name debe ser 'collection:ns.nombre' o 'role:nombre'"
elif [ "$kind" = "collection" ]; then
    found=$(docker exec control sh -c 'for h in /home/ansible /root; \
        do HOME="$h" ansible-galaxy collection list 2>/dev/null; done')
    if ! printf '%s\n' "$found" | grep -qE "^${item//./\\.}[[:space:]]"; then
        echo "FAIL la colección $item no está instalada en control"
    elif [ -n "$ver" ] && ! printf '%s\n' "$found" \
            | grep -E "^${item//./\\.}[[:space:]].*${ver}" >/dev/null; then
        echo "FAIL $item está instalada pero no en la versión $ver"
    else
        echo "OK"
    fi
elif [ "$kind" = "role" ]; then
    found=$(docker exec control sh -c 'for h in /home/ansible /root; \
        do HOME="$h" ansible-galaxy role list 2>/dev/null; done')
    if printf '%s\n' "$found" | grep -qE "^- ${item//./\\.},"; then
        echo "OK"
    else
        echo "FAIL el rol $item no está instalado en control"
    fi
else
    echo "FAIL tipo galaxy desconocido: $kind (usa collection: o role:)"
fi
