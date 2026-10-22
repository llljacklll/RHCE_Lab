#!/bin/bash
# ============================================================
#  core/checkers/check_service.sh — plugin: servicios systemd
# ------------------------------------------------------------
#  QUÉ VALIDA: que una unidad systemd esté ACTIVA en el nodo.
#    $1 = node .. contenedor a comprobar
#    $2 = name .. unidad (p. ej. "httpd", "sshd")
#    $3 = path .. sin uso en este plugin
#  DETALLE: is-active --quiet decide SOLO por el código de
#  salida (0 = activa) y no imprime nada. Es el ESTADO actual:
#  un servicio "enabled" pero caído cantará FAIL aquí, y al
#  revés — la Fase 1 de test.sh usa is-enabled justo para
#  comprobar lo complementario.
#  SALIDA: "OK"/"FAIL" (una línea, stdout).
# ============================================================
local node="$1"; local svc="$2"
docker exec "$node" systemctl is-active --quiet "$svc" 2>/dev/null && echo "OK" || echo "FAIL"
