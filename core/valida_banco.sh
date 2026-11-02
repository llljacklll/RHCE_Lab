#!/bin/bash
# ============================================================
#  core/valida_banco.sh - validador propio del banco (V-1)
# ------------------------------------------------------------
#  Puerta 6/6 de la CI (.github/workflows/ci.yml) y comando
#  suelto en local. SOLO LECTURA: no escribe nada del repo,
#  no toca docker ni los nodos.
#
#  QUE NO HACE (no duplicar lo ya cubierto):
#   - huerfanos pool<->soluciones<->README: lint_pool.sh (5/5)
#   - tipos<->checkers de todo scenarios/**: CI 4/5 (aqui la
#     capa C3 lo replica en local)
#   - playbooks de solucion: los valida Ansible en runtime
#
#  TRES CAPAS (contrato 14B, dictamen GO):
#   A formato: A1 UTF-8 valido; A2 sin bytes de control salvo
#     \n y \t; A3 REGLA DE ORO del parser grade.sh: ninguna
#     linea de datos lleva comentario final. Regla YAML real:
#     '#' abre comentario si va tras un blanco o al inicio de
#     linea, y nunca dentro de comillas.
#   B esquema: examenes fijos con claves exactas {id,
#     difficulty, title, time_limit, tasks, checks}; id ==
#     nombre de fichero; difficulty == directorio padre;
#     time_limit entero > 0; tareas {id, description}; ids
#     de tarea sin duplicados; checks {type, task_id};
#     >=1 check por task (no 1:1); todo task_id de checks
#     existe en tasks. Pool: fuente = ultimo documento dict
#     (docs[-1], convencion de lint_pool); tareas {id,
#     difficulty, description, checks}; ids unicos; checks
#     {type, name}; task_id opcional pero, si aparece, debe
#     existir.
#   C cruces: C1 contra la spec Fase 5 parseada de
#     core/test.sh (dificultad y numero de checks por
#     examen; sin hardcode) y biyeccion spec<->ficheros;
#     C3 todo tipo de check con su checker; C4 conjuntos
#     completos examen fijo <-> playbook de solucion
#     (faltantes Y huerfanos, en ambas direcciones).
#
#  NOTA YAML 1.1: PyYAML safe_load interpreta 'on:' como el
#  booleano True (trampa documentada en ci.yml). Esta
#  herramienta valida la semantica que el proyecto consume
#  de verdad (grade.sh y exam.sh leen los campos del
#  esquema B); no reescribe ni reinterpreta los datos.
#
#  LVM (WARN, no FAIL; dictamen 14B): en checks de tipo lvm,
#  si el name parece VG de nombre fijo ('vg_' sin el token
#  __NODE__) se avisa con fichero y linea: device-mapper es
#  global al kernel y el patron docente es vg_<nodo>. El
#  aviso no sustituye a los checkers ni a la validacion en
#  runtime.
#
#  CONTRATO: exit 0 = VERDE (los WARN no bloquean);
#            exit 1 = ROJO (hay algun FAIL).
# ============================================================

cd "$(dirname "$0")/.." || { echo "no encuentro la raiz del repo"; exit 1; }

if ! python3 -c "import yaml" 2>/dev/null; then
    echo "[X] valida_banco necesita PyYAML (es un validador YAML):"
    echo "    dnf install -y python3-pyyaml"
    exit 1
fi

python3 - <<'PYVB'
import glob
import os
import re
import sys
import yaml

fails = 0
warns = 0
pool_n = 0

def fail(path, ln, msg):
    global fails
    fails += 1
    print("[FAIL] %s:%s %s" % (path, ln, msg))

def warn(path, ln, msg):
    global warns
    warns += 1
    print("[WARN] %s:%s %s" % (path, ln, msg))

def line_de(path, aguja):
    # primera linea que contiene la aguja (para avisos con linea)
    try:
        with open(path, encoding="utf-8") as fh:
            for ln, line in enumerate(fh, 1):
                if aguja in line:
                    return ln
    except OSError:
        pass
    return "?"

def scan_texto(path):
    # Capa A sobre el texto crudo: A1 UTF-8, A2 control, A3
    try:
        text = open(path, encoding="utf-8").read()
    except UnicodeDecodeError as e:
        fail(path, "?", "A1 no es UTF-8 valido: %s" % e)
        return
    for ln, line in enumerate(text.splitlines(), 1):
        for ch in line:
            if ord(ch) < 32 and ch != "\t":
                fail(path, ln, "A2 byte de control 0x%02X" % ord(ch))
        s = line.strip()
        if not s or s.startswith("#"):
            continue  # comentario en linea completa: permitido
        in_s = in_d = False
        prev = " "
        for ch in line:
            if ch == "'" and not in_d:
                in_s = not in_s
            elif ch == '"' and not in_s:
                in_d = not in_d
            elif ch == "#" and not in_s and not in_d and prev in " \t":
                fail(path, ln, "A3 comentario final en linea de datos")
                break
            prev = ch

tipos = set()
for p in glob.glob("core/checkers/check_*.sh"):
    tipos.add(os.path.basename(p)[6:-3])
if not tipos:
    fail("core/checkers/", "?", "C3 no encuentro plugins check_*.sh")

DIFS = ("easy", "medium", "hard")

def lvm_warn(path, c):
    # dictamen 14B: WARN con fichero y linea, nunca FAIL
    if c.get("type") != "lvm":
        return
    nombre = str(c.get("name") or "")
    if "vg_" in nombre and "__NODE__" not in nombre:
        warn(path, line_de(path, nombre),
             "LVM '%s' parece VG de nombre fijo sin token __NODE__ "
             "(device-mapper global al kernel; patron docente: "
             "vg_<nodo>)" % nombre)

fijos = {}  # id -> (path, dificultad, n_checks)
for path in sorted(glob.glob("scenarios/*/*.yml")):
    d = os.path.basename(os.path.dirname(path))
    base = os.path.basename(path)
    scan_texto(path)
    try:
        data = yaml.safe_load(open(path, encoding="utf-8"))
    except yaml.YAMLError as e:
        mark = getattr(e, "problem_mark", None)
        ln = getattr(mark, "line", None)
        ln = (ln + 1) if isinstance(ln, int) else "?"
        fail(path, ln, "A/B YAML no parsea: %s"
             % str(e).splitlines()[0][:60])
        continue
    if d not in DIFS:
        warn(path, "?", "B directorio de dificultad raro: %s/" % d)
    if not isinstance(data, dict):
        fail(path, "?", "B el examen no es un dict YAML")
        continue
    claves = set(data.keys())
    req = set(["id", "difficulty", "title", "time_limit",
               "tasks", "checks"])
    extra = sorted(claves - req)
    falta = sorted(req - claves)
    if extra:
        fail(path, "?", "B claves fuera de esquema: %s"
             % ", ".join(extra))
    if falta:
        fail(path, "?", "B claves que faltan: %s" % ", ".join(falta))
    if data.get("id") != base[:-4]:
        fail(path, "?", "B id=%r no coincide con el fichero %s"
             % (data.get("id"), base))
    if data.get("difficulty") != d:
        fail(path, "?", "B difficulty=%r pero vive en %s/"
             % (data.get("difficulty"), d))
    tl = data.get("time_limit")
    if isinstance(tl, bool) or not isinstance(tl, int) or tl <= 0:
        fail(path, "?", "B time_limit debe ser entero > 0 (es %r)"
             % (tl,))
    tids = []
    vistos = set()
    for t in (data.get("tasks") or []):
        if not isinstance(t, dict):
            fail(path, "?", "B tarea que no es dict")
            continue
        tid = t.get("id")
        if not tid:
            fail(path, "?", "B tarea sin id")
            continue
        if tid in vistos:
            fail(path, "?", "B id de tarea duplicado: %s" % tid)
        vistos.add(tid)
        tids.append(tid)
        if not t.get("description"):
            fail(path, "?", "B tarea %s sin description" % tid)
    con_check = set()
    for c in (data.get("checks") or []):
        if not isinstance(c, dict):
            fail(path, "?", "B check que no es dict")
            continue
        ct = c.get("type")
        if not ct:
            fail(path, "?", "B check sin type")
            continue
        if ct not in tipos:
            fail(path, "?", "C3 tipo sin checker: %s" % ct)
        lvm_warn(path, c)
        tref = c.get("task_id")
        if not tref:
            fail(path, "?", "B check (%s) sin task_id" % ct)
            continue
        con_check.add(tref)
        if tref not in tids:
            fail(path, "?", "B check apunta a tarea inexistente: "
                 "%s" % tref)
    for tid in tids:
        if tid not in con_check:
            fail(path, "?", "B tarea %s sin ningun check" % tid)
    chk = data.get("checks")
    n = len(chk) if isinstance(chk, list) else 0
    fijos[base[:-4]] = (path, d, n)

src = ""
if os.path.exists("core/test.sh"):
    src = open("core/test.sh", encoding="utf-8").read()
specs = re.findall(r'"(exam_[0-9]+):(easy|medium|hard):'
                   r'([0-9]+)/[0-9]+"', src)
esp = {}
for sid, dif, nc in specs:
    if sid in esp:
        fail("core/test.sh", "?", "C1 examen repetido en spec: %s"
             % sid)
    esp[sid] = (dif, int(nc))
if not esp:
    fail("core/test.sh", "?", "C1 no hallo la spec de Fase 5")
for sid in sorted(esp):
    dif, nc = esp[sid]
    if sid not in fijos:
        fail("core/test.sh", "?", "C1 la spec pide %s y no hay "
             "scenarios/<d>/%s.yml" % (sid, sid))
        continue
    path, d, n = fijos[sid]
    if d != dif:
        fail(path, "?", "C1 %s vive en %s/ y la spec dice %s"
             % (sid, d, dif))
    if n != nc:
        fail(path, "?", "C1 %s tiene %s checks y la spec exige %s"
             % (sid, n, nc))
for sid in sorted(fijos):
    if sid not in esp:
        fail(fijos[sid][0], "?", "C1 examen fijo sin spec de Fase "
             "5 (huerfano de bateria): %s" % sid)

POOL = "scenarios/task_pool.yml"
if not os.path.exists(POOL):
    fail(POOL, "?", "B falta scenarios/task_pool.yml")
else:
    scan_texto(POOL)
    docs = []
    try:
        for x in yaml.safe_load_all(open(POOL, encoding="utf-8")):
            if isinstance(x, dict):
                docs.append(x)
    except yaml.YAMLError as e:
        mark = getattr(e, "problem_mark", None)
        ln = getattr(mark, "line", None)
        ln = (ln + 1) if isinstance(ln, int) else "?"
        fail(POOL, ln, "A/B YAML no parsea: %s"
             % str(e).splitlines()[0][:60])
    if not docs:
        fail(POOL, "?", "B pool sin documentos dict (fuente: "
             "docs[-1], convencion de lint_pool)")
    else:
        pool = docs[-1]
        pts = pool.get("tasks")
        if not isinstance(pts, list) or not pts:
            fail(POOL, "?", "B pool sin lista 'tasks' en docs[-1]")
        else:
            pool_n = len(pts)
            ids = set()
            refs = []
            for t in pts:
                if not isinstance(t, dict):
                    fail(POOL, "?", "B tarea de pool que no es dict")
                    continue
                tid = t.get("id")
                if not tid:
                    fail(POOL, "?", "B tarea de pool sin id")
                    continue
                if tid in ids:
                    fail(POOL, "?", "B id duplicado en pool: %s" % tid)
                ids.add(tid)
                if t.get("difficulty") not in DIFS:
                    fail(POOL, "?", "B difficulty rara en %s: %r"
                         % (tid, t.get("difficulty")))
                if not t.get("description"):
                    fail(POOL, "?", "B tarea %s sin description" % tid)
                chk = t.get("checks")
                if not isinstance(chk, list) or not chk:
                    fail(POOL, "?", "B tarea %s sin checks" % tid)
                    continue
                for c in chk:
                    if not isinstance(c, dict):
                        fail(POOL, "?", "B check de %s que no es dict"
                             % tid)
                        continue
                    ct = c.get("type")
                    if not ct:
                        fail(POOL, "?", "B check de %s sin type" % tid)
                        continue
                    if ct not in tipos:
                        fail(POOL, "?", "C3 tipo sin checker: %s" % ct)
                    if not c.get("name"):
                        fail(POOL, "?", "B check de %s sin name" % tid)
                    lvm_warn(POOL, c)
                    tref = c.get("task_id")
                    if tref is not None:
                        refs.append((tid, tref))
            for tid, tref in refs:
                if tref not in ids:
                    fail(POOL, "?", "B task_id de %s apunta a tarea "
                         "inexistente: %s" % (tid, tref))

pb = set()
for p in glob.glob("ansible/playbooks/exam_*.yml"):
    pb.add(os.path.basename(p)[:-4])
for sid in sorted(esp):
    if sid not in pb:
        fail("ansible/playbooks/", "?", "C4 falta el playbook de %s "
             "(solucion de referencia)" % sid)
for p in sorted(pb):
    if p not in esp:
        fail("ansible/playbooks/%s.yml" % p, "?", "C4 playbook "
             "huerfano: sin examen fijo ni spec de Fase 5")

print("")
print("valida_banco: %d examen(es) fijo(s) | pool: %d tarea(s) | "
      "tipos con checker: %d" % (len(fijos), pool_n, len(tipos)))
print("")
if fails:
    print("== VALIDA BANCO: ROJO (%d FAIL, %d WARN) =="
          % (fails, warns))
    sys.exit(1)
print("== VALIDA BANCO: VERDE (%d FAIL, %d WARN) ==" % (fails, warns))
sys.exit(0)
PYVB
