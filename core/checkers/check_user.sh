#!/bin/bash
# Valida que un usuario exista en el SO (UID opcional via $3)
local node="$1"; local user="$2"; local uid="${3:-}"
if [ -n "$uid" ]; then
    [ "$(docker exec "$node" id -u "$user" 2>/dev/null)" = "$uid" ] && echo "OK" || echo "FAIL"
else
    docker exec "$node" id -u "$user" >/dev/null 2>&1 && echo "OK" || echo "FAIL"
fi
