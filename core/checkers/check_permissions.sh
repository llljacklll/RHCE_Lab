#!/bin/bash
# Valida permisos numéricos de un archivo
local node="$1"; local expected_perms="$2"; local path="$3"
local actual_perms; actual_perms=$(docker exec "$node" stat -c "%a" "$path" 2>/dev/null)
[ "$actual_perms" = "$expected_perms" ] && echo "OK" || echo "FAIL"
