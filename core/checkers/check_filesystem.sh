#!/bin/bash
# Valida que un dispositivo tenga filesystem (tipo via $3, defecto ext4)
local node="$1"; local dev="$2"; local fstype="${3:-ext4}"
[ "$(docker exec "$node" blkid -o value -s TYPE "$dev" 2>/dev/null)" = "$fstype" ] && echo "OK" || echo "FAIL"
