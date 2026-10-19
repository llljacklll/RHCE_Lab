#!/bin/bash
# Valida que un grupo exista (GID opcional via $3)
local node="$1"; local group="$2"; local gid="${3:-}"
if [ -n "$gid" ]; then
    [ "$(docker exec "$node" getent group "$group" 2>/dev/null | cut -d: -f3)" = "$gid" ] && echo "OK" || echo "FAIL"
else
    docker exec "$node" getent group "$group" >/dev/null 2>&1 && echo "OK" || echo "FAIL"
fi
