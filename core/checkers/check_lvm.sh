#!/bin/bash
# Valida que un Logical Volume exista
local node="$1"; local lv_path="$2"
docker exec "$node" lvs "$lv_path" >/dev/null 2>&1 && echo "OK" || echo "FAIL"
