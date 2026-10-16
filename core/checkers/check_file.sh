#!/bin/bash
# Valida que un archivo contenga un texto
local node="$1"; loc
docker exec "$node" grep -q "$pattern" "$path" 2>/dev/null && echo "OK" || echo "FAIL"
