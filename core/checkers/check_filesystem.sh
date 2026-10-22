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
#  SALIDA: "OK" o "FAIL <razón>" (1 línea, stdout).
#  DETALLE: blkid -o value -s TYPE imprime SOLO el tipo, sin
#  etiquetas ("xfs"): perfecto para comparar con un = de
#  cadena. Disco crudo sin filesystem -> no imprime nada ->
#  cadena vacía != tipo esperado -> FAIL honesto.
# ============================================================
local node="$1"; local dev="$2"; local fstype="${3:-ext4}"
local actual
actual=$(docker exec "$node" blkid -o value -s TYPE "$dev" 2>/dev/null)
if [ -z "$actual" ]; then
    echo "FAIL el dispositivo $dev no tiene filesystem en $node (blkid sin TYPE)"
elif [ "$actual" != "$fstype" ]; then
    echo "FAIL $dev es de tipo $actual (se pedía $fstype) en $node"
else
    echo "OK"
fi
