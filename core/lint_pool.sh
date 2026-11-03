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

# --- 15B: G5/G6/G7 — contrato de activos didácticos ---------
#  Ampliación aprobada por el dictamen de auditoría de la saga
#  15B (fases 2 y 3). G1-G4 quedan intactos; se añaden:
#   G5  cabeceras canónicas de soluciones/<task_id>.yml:
#       L1 banner '#'+'=' x76 (78 chars); L2 título estricto
#       'SOLUCION MODELO -- <id> [dificultad: X]' con id ==
#       basename y X coherente con el prefijo (hard_ -> hard,
#       med_/medium_ -> medium, rand_ -> easy); L3 separador
#       '#'+'-' x76; 'TAREA' anclada en las 12 primeras líneas
#       (se admite la variante anotada 'TAREA (...):'); L1-L3
#       ASCII puro y fichero completo UTF-8 válido.
#   G6  esquema del pool con la MISMA carga que G1
#       (safe_load_all -> último doc dict -> tasks): claves
#       {id, difficulty, description, checks}; difficulty en
#       {easy,medium,hard} y coherente con el prefijo del id;
#       todo check con 'type' que tenga checker en
#       core/checkers/check_<type>.sh y 'name' no vacío
#       (grade.sh descuenta EN SILENCIO los checks sin esos
#       campos); todo task_id dentro de checks -> id existente;
#       __NODE__ solo en valores de claves name/path de tareas
#       cuyo id contenga 'lvm' (búsqueda RECURSIVA en todos los
#       valores, incluidos los anidados). Pool malformado ->
#       [FAIL] explícito, nunca banco vacío ni falso verde.
#   G7  plays de soluciones con objetos YAML reales: cada play
#       declara 'hosts' dentro de la allowlist
#       {all, localhost, node1,node2,node3} y 'become' presente
#       como booleano YAML real (true/false, no cadena);
#       ficheros sin CR y sin bytes de control salvo \n y \t.
#  LINT_POOL_ROOT (env, opcional): raíz alternativa para
#  ejecutar este gate sobre un árbol de prueba (batería de
#  fixtures). Por defecto, la raíz del repo: el comportamiento
#  histórico de G1-G4 no cambia.
# ============================================================

ROOT="${LINT_POOL_ROOT:-}"
if [ -n "$ROOT" ]; then
    cd "$ROOT" || { echo "[FAIL] LINT_POOL_ROOT inaccesible: $ROOT"; exit 1; }
else
    cd "$(dirname "$0")/.." || { echo "no encuentro la raiz del repo"; exit 1; }
fi

POOL=scenarios/task_pool.yml
SOL=soluciones
README=soluciones/README.md
fail=0

for f in "$POOL" "$README"; do
    [ -f "$f" ] || { echo "[FAIL] falta $f"; exit 1; }
done
[ -d "$SOL" ] || { echo "[FAIL] falta $SOL/"; exit 1; }

# --- V-2 (14C-b): G1 y siguientes leen el pool con Python+PyYAML.
# Sin PyYAML los gates de abajo darian falsos OK/FAIL: cortar aqui con
# mensaje claro (lint_pool corre tambien standalone, sin utils.sh).
if ! python3 -c "import yaml" >/dev/null 2>&1; then
    echo "[FAIL] PyYAML no disponible para lint_pool (instala: bash scripts/vm_bootstrap.sh)"; exit 1
fi

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

# --- G5 (15B): cabeceras canónicas de soluciones (contrato D)
g5_out=$(python3 - <<'PYG5'
import glob, os, re, sys
fails = []
def add(m): fails.append("[FAIL] G5 %s" % m)
L1 = re.compile(r'^# ={76}$')
L2 = re.compile(r'^#  SOLUCION MODELO -- ([a-z0-9_]+) +\[dificultad: (easy|medium|hard)\]$')
L3 = re.compile(r'^# -{76}$')
TA = re.compile(r'^#  TAREA(?: \([^)]*\))?:')
PREF = (('hard_', 'hard'), ('med_', 'medium'), ('medium_', 'medium'), ('rand_', 'easy'))
def dif_pref(fid):
    for p, d in PREF:
        if fid.startswith(p):
            return d
    return None
files = sorted(glob.glob('soluciones/*.yml'))
if not files:
    add("no hay soluciones/*.yml")
for f in files:
    fid = os.path.basename(f)[:-4]
    try:
        raw = open(f, 'rb').read()
    except OSError as e:
        add("%s: no legible (%s)" % (f, e)); continue
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError as e:
        add("%s: UTF-8 invalido (%s)" % (f, e)); continue
    lines = text.split('\n')
    d = dif_pref(fid)
    if d is None:
        add("%s: prefijo del id sin dificultad conocida" % f); continue
    if len(lines) < 4:
        add("%s: cabecera incompleta" % f); continue
    if not L1.match(lines[0]):
        add("%s: L1 no es el banner canonico de 78" % f)
    m = L2.match(lines[1])
    if not m:
        add("%s: L2 no es el titulo canonico" % f)
    else:
        if m.group(1) != fid:
            add("%s: L2 nombra '%s' != nombre del fichero" % (f, m.group(1)))
        if m.group(2) != d:
            add("%s: L2 dificultad %s != prefijo %s" % (f, m.group(2), d))
    if not L3.match(lines[2]):
        add("%s: L3 no es el separador canonico de 78" % f)
    if not any(TA.match(l) for l in lines[:12]):
        add("%s: sin 'TAREA' anclada en las 12 primeras lineas" % f)
    if any(ord(c) > 127 for l in lines[:3] for c in l):
        add("%s: no-ASCII en L1-L3" % f)
if fails:
    print('\n'.join(fails)); sys.exit(1)
print("[OK ] G5 cabeceras canonicas: %d ficheros" % len(files))
PYG5
) || fail=1
[ -n "$g5_out" ] && printf '%s\n' "$g5_out"

# --- G6 (15B): esquema del pool (contrato E), misma carga que G1
g6_out=$(python3 - <<'PYG6'
import os, sys, yaml
fails = []
def add(m): fails.append("[FAIL] G6 %s" % m)
try:
    with open('scenarios/task_pool.yml', encoding='utf-8') as fh:
        docs = [d for d in yaml.safe_load_all(fh) if isinstance(d, dict)]
except (yaml.YAMLError, OSError, UnicodeDecodeError) as e:
    print("[FAIL] G6 pool no cargable: %s" % e); sys.exit(1)
if not docs:
    print("[FAIL] G6 pool sin documentos dict"); sys.exit(1)
tasks = docs[-1].get('tasks')
if not isinstance(tasks, list) or not tasks:
    print("[FAIL] G6 pool malformado: el ultimo doc dict no tiene lista 'tasks'"); sys.exit(1)

def walk(v, key, path, tokens, refs):
    if isinstance(v, dict):
        for k, vv in v.items():
            walk(vv, k, path + "/" + str(k), tokens, refs)
    elif isinstance(v, list):
        for n, vv in enumerate(v):
            walk(vv, key, path + "/%d" % n, tokens, refs)
    elif isinstance(v, str):
        if '__NODE__' in v:
            tokens.append((key, path))
        if key == 'task_id':
            refs.append((path, v))

PREF = (('hard_', 'hard'), ('med_', 'medium'), ('medium_', 'medium'), ('rand_', 'easy'))
def dif_pref(i):
    for p, d in PREF:
        if i.startswith(p):
            return d
    return None

ids = set()
for t in tasks:
    if isinstance(t, dict) and isinstance(t.get('id'), str) and t['id']:
        ids.add(t['id'])

n_checks = 0
for t in tasks:
    if not isinstance(t, dict):
        add("entrada de tarea no-dict"); continue
    tid = t.get('id')
    if not isinstance(tid, str) or not tid:
        add("tarea sin id valido"); continue
    for k in ('difficulty', 'description', 'checks'):
        if k not in t:
            add("%s: falta clave '%s'" % (tid, k))
    dif = t.get('difficulty')
    if dif not in ('easy', 'medium', 'hard'):
        add("%s: difficulty %r fuera de {easy,medium,hard}" % (tid, dif))
    else:
        dp = dif_pref(tid)
        if dp is not None and dp != dif:
            add("%s: difficulty '%s' incoherente con el prefijo (esperaba %s)" % (tid, dif, dp))
    desc = t.get('description')
    if not isinstance(desc, str) or not desc.strip():
        add("%s: description vacia" % tid)
    checks = t.get('checks')
    if not isinstance(checks, list) or not checks:
        add("%s: 'checks' vacio o ausente" % tid); continue
    for c in checks:
        if not isinstance(c, dict):
            add("%s: check no-dict" % tid); continue
        n_checks += 1
        ct = c.get('type')
        if not isinstance(ct, str) or not ct.strip():
            add("%s: check sin 'type' (grade.sh lo descontaria en silencio)" % tid)
        elif not os.path.isfile('core/checkers/check_%s.sh' % ct):
            add("%s: tipo '%s' sin core/checkers/check_%s.sh" % (tid, ct, ct))
        nm = c.get('name')
        if not isinstance(nm, str) or not nm.strip():
            add("%s: check con 'name' vacio (grade.sh lo descontaria en silencio)" % tid)
    tokens, refs = [], []
    walk(t, None, '', tokens, refs)
    es_lvm = 'lvm' in tid
    for key, path in tokens:
        if not es_lvm:
            add("%s: __NODE__ en tarea no-LVM (%s)" % (tid, path))
        elif key not in ('name', 'path'):
            add("%s: __NODE__ fuera de name/path (%s)" % (tid, path))
    for path, ref in refs:
        if ref not in ids:
            add("%s: checks referencian task_id inexistente '%s' (%s)" % (tid, ref, path))
if fails:
    print('\n'.join(fails)); sys.exit(1)
print("[OK ] G6 esquema del pool: %d tareas, %d checks, checkers alineados" % (len(tasks), n_checks))
PYG6
) || fail=1
[ -n "$g6_out" ] && printf '%s\n' "$g6_out"

# --- G7 (15B): plays de soluciones (contrato F), YAML real
g7_out=$(python3 - <<'PYG7'
import glob, sys, yaml
fails = []
def add(m): fails.append("[FAIL] G7 %s" % m)
ALLOW = {'all', 'localhost', 'node1,node2,node3'}
files = sorted(glob.glob('soluciones/*.yml'))
if not files:
    add("no hay soluciones/*.yml")
for f in files:
    try:
        raw = open(f, 'rb').read()
    except OSError as e:
        add("%s: no legible (%s)" % (f, e)); continue
    if b'\r' in raw:
        add("%s: contiene CR" % f)
    ctrl = sorted({b for b in raw if b < 32 and b not in (10, 9)})
    if ctrl:
        add("%s: bytes de control %s" % (f, ctrl))
    try:
        doc = yaml.safe_load(raw.decode('utf-8'))
    except (yaml.YAMLError, UnicodeDecodeError) as e:
        add("%s: YAML no parsea (%s)" % (f, e)); continue
    if not isinstance(doc, list) or not doc:
        add("%s: no es una lista de plays" % f); continue
    for n, play in enumerate(doc):
        if not isinstance(play, dict):
            add("%s: play %d no es dict" % (f, n)); continue
        h = play.get('hosts')
        if isinstance(h, list):
            hk = ','.join(str(x).strip() for x in h)
        elif isinstance(h, str):
            hk = h.strip()
        else:
            hk = ''
        if not hk:
            add("%s: play %d sin 'hosts' explicito" % (f, n))
        elif hk not in ALLOW:
            add("%s: play %d hosts '%s' fuera de la allowlist" % (f, n, hk))
        if 'become' not in play:
            add("%s: play %d sin 'become' explicito" % (f, n))
        elif not isinstance(play['become'], bool):
            add("%s: play %d 'become' no es booleano YAML (%r)" % (f, n, play['become']))
if fails:
    print('\n'.join(fails)); sys.exit(1)
print("[OK ] G7 plays: %d ficheros, hosts/become explicitos y validos" % len(files))
PYG7
) || fail=1
[ -n "$g7_out" ] && printf '%s\n' "$g7_out"

# --- veredicto (contrato 0/1 para la CI)
if [ "$fail" -eq 0 ]; then
    echo "== LINT ANTI-HUERFANOS: VERDE =="
    exit 0
fi
echo "== LINT ANTI-HUERFANOS: ROJO =="
exit 1
