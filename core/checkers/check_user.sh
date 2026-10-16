#!/bin/bash
# Valida que un usuario exista en el SO
local node="$1"; local user="$2"
docker exec "$node" id -u "$user" >/dev/null 2>&1 && echo "OK" || echo "FAIL"
