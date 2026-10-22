#!/bin/bash
# ============================================================
#  core/checkers/check_mount.sh — plugin: montajes activos
# ------------------------------------------------------------
#  QUÉ VALIDA: que un punto de montaje esté ACTIVO, con opción
#  a exigir el origen exacto.
#    $1 = node .. contenedor a comprobar
#    $2 = name .. punto de montaje (p. ej. /mnt/datos)
#    $3 = path .. origen esperado, OPCIONAL: acepta las dos
#                  grafías del mismo dispositivo (/dev/vg/lv y
#                  la canónica /dev/mapper/vg-lv)
#  SALIDA: "OK" o "FAIL <razón>" (1 línea, stdout).
#  POR QUÉ LAS DOS GRAFÍAS: el kernel muestra el origen como
#  /dev/mapper/vg-lv (nombre device-mapper) mientras el
#  alumno — y el YAML — escriben /dev/vg/lv. La conversión
#  con sed (quitar /dev/, cambiar / por -) pasa de una a la
#  otra y la comparación admite AMBAS. Sin origen ($3 vacío):
#  montado = OK, da igual desde qué dispositivo.
# ============================================================
local node="$1"; local mpoint="$2"; local src="${3:-}"
local out
out=$(docker exec "$node" findmnt -n -o SOURCE "$mpoint" 2>/dev/null)
if [ -z "$out" ]; then
    echo "FAIL $mpoint no está montado en $node (findmnt sin origen)"
elif [ -n "$src" ]; then
    local dm="/dev/mapper/$(echo "$src" | sed 's|^/dev/||; s|/|-|')"
    if [ "$out" = "$src" ] || [ "$out" = "$dm" ]; then
        echo "OK"
    else
        echo "FAIL $mpoint está montado desde $out (se pedía $src) en $node"
    fi
else
    echo "OK"
fi
