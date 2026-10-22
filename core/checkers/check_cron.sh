#!/bin/bash
# ============================================================
#  core/checkers/check_cron.sh — plugin: entradas de crontab
# ------------------------------------------------------------
#  QUÉ VALIDA: que el crontab de un usuario contenga una
#  línea de trabajo concreta.
#    $1 = node .. contenedor a comprobar
#    $2 = name .. la LÍNEA completa del cron tal y como debe
#                  aparecer (p. ej. "*/5 * * * * logger hola")
#    $3 = path .. usuario dueño del crontab, OPCIONAL
#                  (vacío -> "ansible", el usuario de trabajo
#                  del laboratorio)
#  SALIDA: "OK" o "FAIL <razón>" (1 línea, stdout).
#  DETALLE: grep -qF compara CADENA LITERAL — los * y / de
#  una expresión cron son metacaracteres de regex y con -F
#  no se interpretan. Y se exige la línea exacta: no vale
#  "algo parecido".
# ============================================================
local node="$1"; local job_str="$2"; local user="${3:-ansible}"
local tab
tab=$(docker exec "$node" crontab -l -u "$user" 2>/dev/null)
if [ -z "$tab" ]; then
    echo "FAIL el usuario $user no tiene crontab en $node"
elif printf '%s\n' "$tab" | grep -qF -- "$job_str"; then
    echo "OK"
else
    echo "FAIL la línea '$job_str' no está en el crontab de $user ($node)"
fi
