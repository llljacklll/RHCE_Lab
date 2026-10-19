#!/bin/bash
# Valida que un punto de montaje este activo (origen opcional via $3,
# acepta forma /dev/vg/lv y su canonica /dev/mapper/vg-lv)
local node="$1"; local mpoint="$2"; local src="${3:-}"
local out
out=$(docker exec "$node" findmnt -n -o SOURCE "$mpoint" 2>/dev/null)
if [ -z "$out" ]; then
    echo "FAIL"
elif [ -n "$src" ]; then
    local dm="/dev/mapper/$(echo "$src" | sed 's|^/dev/||; s|/|-|')"
    if [ "$out" = "$src" ] || [ "$out" = "$dm" ]; then echo "OK"; else echo "FAIL"; fi
else
    echo "OK"
fi
