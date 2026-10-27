#!/bin/bash
# ============================================================
#  core/lint_pool.sh — LINT ANTI-HUÉRFANOS del banco de tareas
# ------------------------------------------------------------
#  QUÉ ES: la puerta 5/5 de la CI (.github/workflows/ci.yml)
#  y comando suelto útil en local. SOLO LECTURA: no escribe
#  nada del repo, no toca docker ni los nodos.
#
#  EL PROBLEMA QUE CAZA: el banco es un contrato de TRES
#  piezas alineadas 1:1 por task_id:
#    (1) scenarios/task_pool.yml   -> las tareas (la fuente)
#    (2) soluciones/<task_id>.yml  -> la solución de cada una
#    (3) soluciones/README.md      -> una fila por tarea
#  Un lote que añade/renombra/borra en una pieza sin tocar las
#  otras deja HUÉRFANOS: tarea sin solución (el alumno se
#  queda sin referencia), solución fantasma (fichero muerto
#  que el grade jamás pedirá) o fila del README ausente o
#  sobrante (el índice miente). Eso se auditaba a mano; ahora
#  lo acusa la máquina en cada push.
#
#  QUÉ NO MIRA: lo ya cubierto por las puertas 1-4 (sintaxis
#  .sh, YAML, heredocs python, tipos vs core/checkers/).
#
#  CONTRATO: exit 0 = todo alineado; exit 1 = algún huérfano
#  (la CI debe romper). Diagnóstico línea a línea en [FAIL].
# ============================================================

cd "$(dirname "$0")/.." || { echo "no encuentro la raiz del repo"; exit 1; }

POOL=scenarios/task_pool.yml
SOL=soluciones
README=soluciones/README.md
fail=0

for f in "$POOL" "$README"; do
    [ -f "$f" ] || { echo "[FAIL] falta $f"; exit 1; }
done
[ -d "$SOL" ] || { echo "[FAIL] falta $SOL/"; exit 1; }

# --- G1: ids del pool (misma fuente de verdad que la CI 2/5)
ids=$(python3 - <<'PYLP'
import yaml
docs = [d for d in yaml.safe_load_all(open('scenarios/task_pool.yml')) if isinstance(d, dict)]
tasks = docs[-1]['tasks']
assert len(tasks) == len({t['id'] for t in tasks}), 'ids duplicados en el pool'
for t in tasks:
    print(t['id'])
PYLP
) || { echo "[FAIL] pool ilegible"; exit 1; }

pool_ids=$(printf '%s\n' "$ids" | sort)
pool_n=$(printf '%s\n' "$ids" | grep -c .)

# --- ids de soluciones en disco (por nombre de fichero)
sol_ids=$(ls "$SOL"/*.yml 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.yml$//' | sort)
sol_n=$(printf '%s\n' "$sol_ids" | grep -c .)

# --- filas del mapa del README: 1a columna de la tabla bajo
#     '## Mapa de tareas'; se coleccióna DESPUÉS de la línea
#     separadora |---| (salta la cabecera) y para en '## '.
row_ids=$(awk -F '|' '/^## Mapa de tareas/{h=1; next} h && /^\|-*\|/{m=1; next} h && /^## /{exit} m && /^\|/ {gsub(/ /, "", $2); print $2}' "$README" | sort)
row_n=$(printf '%s\n' "$row_ids" | grep -c .)

echo "pool: $pool_n tareas | soluciones: $sol_n | README: $row_n filas"

# --- G2: toda tarea con su solución
for t in $pool_ids; do
    [ -f "$SOL/$t.yml" ] || { echo "[FAIL] huerfano: $t sin soluciones/$t.yml"; fail=1; }
done
[ "$fail" -eq 0 ] && echo "[OK ] todas las tareas tienen solucion"

# --- G3: ninguna solución fantasma
for s in $sol_ids; do
    printf '%s\n' "$ids" | grep -qx "$s" || { echo "[FAIL] fantasma: soluciones/$s.yml no esta en el pool"; fail=1; }
done
[ "$fail" -eq 0 ] && echo "[OK ] ninguna solucion fantasma"

# --- G4: README en sync con el pool (igualdad de conjuntos)
if [ "$pool_ids" = "$row_ids" ]; then
    echo "[OK ] README alineado con el pool ($row_n filas)"
else
    for t in $pool_ids; do
        printf '%s\n' "$row_ids" | grep -qx "$t" || echo "[FAIL] README sin fila: $t"
    done
    for r in $row_ids; do
        printf '%s\n' "$ids" | grep -qx "$r" || echo "[FAIL] README con fila sobrante: $r"
    done
    fail=1
fi

# --- veredicto (contrato 0/1 para la CI)
if [ "$fail" -eq 0 ]; then
    echo "== LINT ANTI-HUERFANOS: VERDE =="
    exit 0
fi
echo "== LINT ANTI-HUERFANOS: ROJO =="
exit 1
