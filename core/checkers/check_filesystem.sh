#!/bin/bash
# ============================================================
#  core/checkers/check_filesystem.sh — plugin: filesystems
# ------------------------------------------------------------
#  QUÉ VALIDA: que un dispositivo tenga filesystem, y que sea
#  del tipo pedido.
#    $1 = node .. contenedor a comprobar
#    $2 = name .. dispositivo (p. ej. /dev/sdb o el nombre
#                  que le dé el examen al disco)
#    $3 = path .. tipo esperado, OPCIONAL (vacío -> ext4)
#  SALIDA: "OK"/"FAIL" (una línea, stdout).
#  DETALLE: blkid -o value -s TYPE imprime SOLO el tipo, sin
#  etiquetas ("xfs"): perfecto para comparar con un = de
#  cadena. Disco crudo sin filesystem -> no imprime nada ->
#  cadena vacía != tipo esperado -> FAIL honesto.
# ============================================================
local node="$1"; local dev="$2"; local fstype="${3:-ext4}"
[ "$(docker exec "$node" blkid -o value -s TYPE "$dev" 2>/dev/null)" = "$fstype" ] && echo "OK" || echo "FAIL"
