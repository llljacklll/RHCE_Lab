#!/bin/bash
# ============================================================
#  core/checkers/check_user.sh — plugin: usuarios del SO
# ------------------------------------------------------------
#  QUÉ VALIDA: que un usuario exista en el nodo, con opción
#  a exigir su UID exacto.
#    $1 = node . contenedor a comprobar
#    $2 = name . nombre de usuario (p. ej. "devops1")
#    $3 = path . UID esperado, OPCIONAL: si llega y no
#          coincide -> FAIL (crearlo "a mano" con otro UID no
#          puntúa); si no llega, basta con que exista.
#  SALIDA: "OK"/"FAIL" (una línea, stdout).
#  DETALLE: id -u imprime el UID numérico y se compara como
#  cadena exacta — sin aritmética: fallar es fallar.
# ============================================================
local node="$1"; local user="$2"; local uid="${3:-}"
if [ -n "$uid" ]; then
    [ "$(docker exec "$node" id -u "$user" 2>/dev/null)" = "$uid" ] && echo "OK" || echo "FAIL"
else
    docker exec "$node" id -u "$user" >/dev/null 2>&1 && echo "OK" || echo "FAIL"
fi
