#!/bin/bash
# ============================================================
#  core/checkers/check_lvm.sh — plugin: Logical Volumes
# ------------------------------------------------------------
#  QUÉ VALIDA: que un Logical Volume exista en el nodo.
#    $1 = node .. contenedor a comprobar
#    $2 = name .. ruta del LV (p. ej. /dev/vg_node1/lv_datos;
#                  con __NODE__ en el YAML llega ya expandido
#                  al nodo que toca en cada pasada)
#    $3 = path .. sin uso en este plugin
#  SALIDA: "OK"/"FAIL" (una línea, stdout).
#  DETALLE: lvs <ruta> consulta los metadatos LVM, no el
#  kernel: existir como LV basta, no hace falta que esté
#  montado ni activo.
# ============================================================
local node="$1"; local lv_path="$2"
docker exec "$node" lvs "$lv_path" >/dev/null 2>&1 && echo "OK" || echo "FAIL"
