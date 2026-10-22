#!/bin/bash
# ============================================================
#  core/checkers/check_service.sh — plugin: servicios systemd
# ------------------------------------------------------------
#  QUÉ VALIDA: que una unidad systemd esté ACTIVA en el nodo.
#    $1 = node .. contenedor a comprobar
#    $2 = name .. unidad (p. ej. "httpd", "sshd")
#    $3 = path .. sin uso en este plugin
#  SALIDA: "OK" o "FAIL <razón>" (1 línea, stdout).
#  DETALLE: systemctl is-active imprime el estado (active/
#  inactive/failed...) y su rc es 0 SOLO si está activa:
#  mismo criterio que is-active --quiet, pero la palabra
#  impresa alimenta la razón del FAIL. Es el ESTADO actual:
#  un servicio "enabled" pero caído cantará FAIL aquí, y al
#  revés — la Fase 1 de test.sh usa is-enabled justo para
#  comprobar lo complementario.
# ============================================================
local node="$1"; local svc="$2"
local state
state=$(docker exec "$node" systemctl is-active "$svc" 2>/dev/null)
if [ "$state" = "active" ]; then
    echo "OK"
else
    echo "FAIL el servicio $svc no está activo en $node (estado: ${state:-desconocido})"
fi
