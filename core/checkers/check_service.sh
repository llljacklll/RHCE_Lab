#!/bin/bash
# Valida que un servicio systemd esté active
local node="$1"; local svc="$2"
docker exec "$node" systemctl is-active --quiet "$svc" 2>/dev/null && echo "OK" || echo "FAIL"
