#!/bin/bash
# Valida contexto SELinux (Simulado para Docker)
local node="$1"; local expected_ctx="$2"; local path="$3"
local actual_ctx; actual_ctx=$(docker exec "$node" getfattr -n security.selinux -e hex "$path" 2>/dev/null | tail -1 | cut -d'"' -f 2 | xxd -r -p 2>/dev/null)
if [[ "$actual_ctx" == *"$expected_ctx"* ]]; then echo "OK"; else if d
