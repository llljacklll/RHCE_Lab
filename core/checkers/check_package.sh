#!/bin/bash
# Valida que un paquete RPM esté instalado
local node="$1"; local pkg="$2"
docker exec "$node" rpm -q "$pkg" >/dev/null 2>&1 && echo "OK" || echo "FAIL"
