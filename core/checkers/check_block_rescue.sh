#!/bin/bash
# ============================================================
#  Checker block/rescue/always — NUEVO (v1.3.0)
# ------------------------------------------------------------
#  La tarea: el alumno crea /home/ansible/block_rescue.yml en
#  el nodo control y lo ejecuta contra los nodos gestionados:
#    block  : instala un paquete que NO existe (falla a propósito)
#    rescue : instala el paquete $name (el "plan B")
#    always : crea el marcador $path en cada nodo
#
#  Contrato con _run_check (source con 3 args, itera LAB_NODES):
#    $1 = node   nodo managed a validar
#    $2 = name   paquete que el rescue debe instalar (p.ej. tree)
#    $3 = path   marcador que el always debe crear (p.ej. /tmp/block_ok)
#
#  Valida en CADA nodo el ESTADO, no el proceso (no se deja
#  engañar por un playbook bonito que no se ejecutó):
#    1) el playbook existe en el control y usa block/rescue/always
#    2) el paquete $name está instalado en $node  (rescue funcionó)
#    3) el marcador $path existe en $node         (always funcionó)
#
#  Prístino => FAIL garantizado (no hay playbook => honesto).
# ============================================================
local node="$1" pkg="$2" marker="$3"
local pb="/home/ansible/block_rescue.yml"

# --- localizar el contenedor control (nombre según compose)
local ctrl="${CONTROL_NODE:-}"
[ -z "$ctrl" ] && ctrl=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i control | head -1)
if [ -z "$ctrl" ]; then
    echo "[checker] no encuentro el contenedor control (CONTROL_NODE sin definir?)" >&2
    echo "FAIL"
    return 1
fi

# --- 1) estructura del playbook en el control
docker exec "$ctrl" grep -Eq '^[[:space:]]*-?[[:space:]]*block:'  "$pb" 2>/dev/null || { echo "FAIL"; return 1; }
docker exec "$ctrl" grep -Eq '^[[:space:]]*rescue:'               "$pb" 2>/dev/null || { echo "FAIL"; return 1; }
docker exec "$ctrl" grep -Eq '^[[:space:]]*always:'               "$pb" 2>/dev/null || { echo "FAIL"; return 1; }

# --- 2) el rescue dejó resultado: paquete instalado en el nodo
docker exec "$node" rpm -q "$pkg" >/dev/null 2>&1 || { echo "FAIL"; return 1; }

# --- 3) el always dejó resultado: marcador presente en el nodo
docker exec "$node" test -e "$marker" 2>/dev/null || { echo "FAIL"; return 1; }

echo "OK"
