#!/bin/bash
# ============================================================
#  tests/pruebas_webui.sh — bateria 15A: estado de la web
# ------------------------------------------------------------
#  QUE: prueba unitaria de lab_state() y exam_tasks() de
#    webui/webui.py contra FIXTURES YAML, sin arrancar el
#    servidor, sin tocar el state/ real y sin docker ni lab
#    (dictamen #10 R3: pruebas que no toquen el arranque).
#  COMO: importlib probe de webui.py con STATE_DIR
#    redirigido a un mktemp; aserciones en python.
#  CASOS:
#   S1 parseo current_exam.yml: mapping canonico (C01),
#      acentos UTF-8 reales (C02), acentos escapados \xF1
#      del formato antiguo (C03), raiz lista (C04), raiz
#      escalar (C05), fichero vacio (C06), time_limit vacio
#      admitido (C07), YAML roto sin traceback (C08),
#      items malformados filtrados (C09).
#   S2 exam_status.yml: start_time/end_time (C10), variante
#      start/end (C11), expired con end en pasado -> restante
#      0 (C12).
#   S3 PyYAML ausente (shim ImportError): warning accionable
#      en lab_state y en pyyaml_warning, exam_tasks [], sin
#      caida (C13).
#   S4 regla UTF-8 de transporte: roundtrip allow_unicode y
#      escapado antiguo via safe_load (C14); exam_random.sh
#      serializa con allow_unicode=True (C15).
#  Uso (desde la raiz del repo): bash tests/pruebas_webui.sh
# ============================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
[ -f webui/webui.py ] || { echo "[FRENO] webui/webui.py no encontrado"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

RC=0
python3 - "$TMP" <<'PYEOF' || RC=$?
import importlib.util, json, os, pathlib, subprocess, sys, time

tmp = pathlib.Path(sys.argv[1])
state = tmp / "state"
state.mkdir(parents=True, exist_ok=True)

WEBUI = pathlib.Path("webui/webui.py").resolve()
spec = importlib.util.spec_from_file_location("webui_probe", str(WEBUI))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.STATE_DIR = state          # hermetico: jamas el state/ real

NPASS = [0]; NFAIL = [0]
def check(cid, cond, msg=""):
    if cond:
        NPASS[0] += 1; print("[OK]    " + cid)
    else:
        NFAIL[0] += 1; print("[FRENO] " + cid + " :: " + msg)

def w_exam(t): (state / "current_exam.yml").write_text(t, encoding="utf-8")
def w_status(t): (state / "exam_status.yml").write_text(t, encoding="utf-8")
def clear():
    for p in ("current_exam.yml", "exam_status.yml"):
        (state / p).unlink(missing_ok=True)

ACC = "configurar la red con \u00f1 y acentuaci\u00f3n"

check("C00 probe importable", hasattr(m, "lab_state") and hasattr(m, "exam_tasks") and hasattr(m, "pyyaml_warning"))

# ---- S1: current_exam.yml ----
clear(); w_exam("id: examen_demo\ndifficulty: hard\ntitle: Demo\ntime_limit: 45\ntasks:\n- id: task_a\n  description: hacer algo\n- id: task_b\n  description: otra cosa\nchecks: []\n")
st = m.lab_state(); ts = m.exam_tasks()
check("C01 mapping canonico", st["exam"] == "examen_demo" and st["time_limit"] == 45 and [t["id"] for t in ts] == ["task_a", "task_b"] and ts[0]["desc"] == "hacer algo", repr(st) + repr(ts))

clear(); w_exam("id: examen_utf8\ntime_limit: 30\ntasks:\n- id: task_n\n  description: " + ACC + "\n")
ts = m.exam_tasks()
check("C02 acentos UTF-8 reales", bool(ts) and ts[0]["desc"] == ACC, repr(ts))

clear(); w_exam(r'id: examen_escapado' + "\n" + r'time_limit: 30' + "\n" + r'tasks:' + "\n" + r'- id: task_e' + "\n" + r'  description: "configurar la red con \xF1 y acentuaci\xF3n"' + "\n")
ts = m.exam_tasks()
check("C03 acentos escapados (formato antiguo)", bool(ts) and ts[0]["desc"] == ACC, repr(ts))

clear(); w_exam("- id: x\n  description: raiz lista\n")
st = m.lab_state(); ts = m.exam_tasks()
check("C04 raiz lista -> vacio seguro (dictamen #8)", st == {"active": False, "status": None, "exam": None, "time_limit": None, "remaining": None} and ts == [], repr(st) + repr(ts))

clear(); w_exam("42\n")
st = m.lab_state(); ts = m.exam_tasks()
check("C05 raiz escalar -> vacio seguro", st["exam"] is None and ts == [], repr(st) + repr(ts))

clear(); w_exam("")
st = m.lab_state(); ts = m.exam_tasks()
check("C06 fichero vacio -> vacio seguro", st["exam"] is None and st["time_limit"] is None and ts == [], repr(st) + repr(ts))

clear(); w_exam("id: e1\ntime_limit:\ntasks: []\n")
st = m.lab_state()
check("C07 time_limit vacio admitido", st["exam"] == "e1" and st["time_limit"] is None, repr(st))

clear(); w_exam("id: [sin cerrar\n")
st = m.lab_state(); ts = m.exam_tasks()
check("C08 YAML roto -> vacio seguro sin traceback", st["exam"] is None and ts == [], repr(st) + repr(ts))

clear(); w_exam("id: e2\ntasks:\n- description: sin id\n- id: ok\n  description: d\n- 42\n")
ts = m.exam_tasks()
check("C09 items malformados filtrados", [t["id"] for t in ts] == ["ok"] and ts[0]["desc"] == "d", repr(ts))

# ---- S2: exam_status.yml ----
clear(); w_exam("id: e3\ntime_limit: 30\ntasks: []\n")
w_status("status: running\nstart_time: %d\n" % (int(time.time()) - 600))
st = m.lab_state()
check("C10 start_time + running -> restante ~1200", st["active"] is True and st["status"] == "running" and st["remaining"] is not None and 1100 <= st["remaining"] <= 1300, repr(st))

clear(); w_exam("id: e4\ntime_limit: 30\ntasks: []\n")
w_status("status: running\nstart: %d\n" % (int(time.time()) - 600))
st = m.lab_state()
check("C11 variante start/end", st["active"] is True and st["remaining"] is not None and 1100 <= st["remaining"] <= 1300, repr(st))

clear(); w_exam("id: e5\ntime_limit: 30\ntasks: []\n")
w_status("status: expired\nstart_time: %d\nend: %d\n" % (int(time.time()) - 7200, int(time.time()) - 3600))
st = m.lab_state()
check("C12 expired con end en pasado -> restante 0", st["active"] is True and st["remaining"] == 0, repr(st))

# ---- S3: PyYAML ausente (shim) ----
shim = tmp / "shim"; shim.mkdir(exist_ok=True)
(shim / "yaml.py").write_text('raise ImportError("shim: PyYAML ausente para la prueba")\n', encoding="utf-8")
probe_src = """
import importlib.util, json, pathlib, sys
spec = importlib.util.spec_from_file_location("webui_probe2", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.STATE_DIR = pathlib.Path(sys.argv[2])
print(json.dumps({"lab": m.lab_state(), "tasks": m.exam_tasks(), "warn": m.pyyaml_warning()}))
"""
env = dict(os.environ); env["PYTHONPATH"] = str(shim)
r = subprocess.run([sys.executable, "-c", probe_src, str(WEBUI), str(state)], env=env, capture_output=True, text=True)
try:
    j = json.loads(r.stdout)
except Exception:
    j = None
check("C13 sin PyYAML -> warning accionable y sin caida",
      j is not None and bool(j["lab"].get("warning")) and "vm_bootstrap.sh" in j["lab"]["warning"]
      and j["lab"]["exam"] is None and j["tasks"] == [] and bool(j["warn"]) and "vm_bootstrap.sh" in j["warn"],
      repr(r.stdout) + repr(r.stderr[-300:]))

# ---- S4: regla UTF-8 de transporte ----
import yaml
s = {"description": ACC}
d1 = yaml.dump(s, default_flow_style=False, sort_keys=False, width=1000, allow_unicode=True)
d2 = yaml.dump(s, default_flow_style=False, sort_keys=False, width=1000)
check("C14 roundtrip allow_unicode + retrocompat escapado", yaml.safe_load(d1) == s and yaml.safe_load(d2) == s and ("\u00f1" in d1) and ("\\xF1" in d2), repr(d1) + repr(d2))

src = pathlib.Path("core/exam_random.sh").read_text(encoding="utf-8")
check("C15 exam_random serializa con allow_unicode=True", "yaml.dump(exam, default_flow_style=False, sort_keys=False, width=1000, allow_unicode=True)" in src, "")

print("== bateria webui: %d/%d OK ==" % (NPASS[0], NPASS[0] + NFAIL[0]))
sys.exit(0 if NFAIL[0] == 0 else 1)
PYEOF

if [ "$RC" -ne 0 ]; then echo "[FRENO] bateria rc=$RC"; exit 1; fi
