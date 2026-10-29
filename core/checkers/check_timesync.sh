#!/bin/bash
# ============================================================
#  core/checkers/check_timesync.sh — plugin: sincronía NTP
# ------------------------------------------------------------
#  QUÉ VALIDA: que la configuración de chrony del nodo apunte
#  al servidor NTP pedido (hueco #17 del intel: la pregunta
#  real pide el rol timesync de redhat.rhel_system_roles; el
#  RESULTADO es siempre el mismo: /etc/chrony.conf con el
#  servidor dentro).
#
#  CONTRATO con _run_check (grade.sh), igual que TODA la
#  familia de core/checkers/:
#    $1 = node .. nodo a comprobar
#    $2 = name ... hostname del servidor/pool NTP que debe
#                  aparecer (p. ej. "pool.ntp.org")
#    $3 = path ... fichero de config; OPCIONAL
#                  (vacío -> /etc/chrony.conf)
#    SALIDA: UNA línea en stdout, "OK" o "FAIL <razón>".
#
#  DETALLE: se busca el hostname como SUBCADENA para admitir
#  tanto 'server X iburst' como 'pool X iburst' (el rol del
#  sistema y lineinfile escriben formas distintas y ambas son
#  válidas en el examen).
# ============================================================
local node="$1"; local ntp="$2"; local conf="${3:-/etc/chrony.conf}"
if [ -z "$ntp" ]; then
    echo "FAIL falta el servidor NTP ('name:' en el YAML)"
elif ! docker exec "$node" test -f "$conf" 2>/dev/null; then
    echo "FAIL no existe $conf en $node (¿chrony sin configurar?)"
elif docker exec "$node" grep -q -- "$ntp" "$conf" 2>/dev/null; then
    echo "OK"
else
    echo "FAIL $conf de $node no menciona el servidor NTP $ntp"
fi
