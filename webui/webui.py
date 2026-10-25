#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
webui.py - Consola web del simulacro RHCE (LOTE 26).

Regla de oro: la web es un mando a distancia del CLI.
 - Toda accion pasa por lab.sh y SOLO por acciones de una allowlist
   (subprocess sin shell: nada llega nunca a una cadena de comandos).
 - El servidor JAMAS escribe estado: lee state/current_exam.yml,
   state/exam_status.yml y state/results/ para pintar el panel.
 - Un solo comando en vuelo: segunda accion mientras otra corre -> 409.
 - Escucha SOLO en 127.0.0.1: el acceso remoto va por tunel SSH
   (ssh -J root@<IP-laboratorio> -L 8888:127.0.0.1:8888 root@<IP-laboratoriob>),
   reutilizando el unico puerto que ya esta abierto. Cero firewalld.

Solo stdlib (el python3 de la propia MV). Lanzar: ./lab.sh web
"""
import argparse
import html
import json
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# ======================================================================
# ADAPTER - unico sitio que conoce el CLI y el estado del lab.
# Cerrado con el recon 26-a:
#   generate -> ./lab.sh exam --random <N> <dif>  (posicional; dif
#               easy|medium|hard|mixed; el swap lo hace el propio lab)
#   start    -> ./lab.sh exam --start             (presenta + cronometro)
#   grade    -> ./lab.sh grade                    (no interactivo)
#   doctor   -> ./lab.sh doctor                   (diagnostico, read-only)
#   estado   -> state/current_exam.yml (id, time_limit en minutos) +
#               state/exam_status.yml (status, start_time)
#   results  -> state/results/*.log  ("Resultado Final: N/N")
# ======================================================================
HERE        = Path(__file__).resolve().parent
PROJECT_DIR = HERE.parent
STATE_DIR   = PROJECT_DIR / "state"
RESULTS_DIR = STATE_DIR / "results"     # ojo: DENTRO de state/, no en la raiz
RUNLOG      = HERE / "run.log"

DIFFICULTIES = ("mixed", "easy", "medium", "hard")

ACTIONS = {
    "generate": ["./lab.sh", "exam", "--random", "{n}", "{d}"],
    "start":    ["./lab.sh", "exam", "--start"],
    "grade":    ["./lab.sh", "grade"],
    "doctor":   ["./lab.sh", "doctor"],
}

# ======================================================================
# Runner: un comando en vuelo; la salida vive en run.log (sobrevive al
# refresh del navegador; cada cliente la lee por offset)
# ======================================================================
RUN = {"proc": None, "action": None, "exit": None}
LOCK = threading.Lock()


def is_running():
    return RUN["proc"] is not None and RUN["proc"].poll() is None


def run_action(name, argv):
    logf = open(RUNLOG, "wb")
    proc = subprocess.Popen(argv, cwd=PROJECT_DIR, stdout=logf,
                            stderr=subprocess.STDOUT,
                            stdin=subprocess.DEVNULL)
    RUN.update(proc=proc, action=name, exit=None)

    def _watch():
        RUN["exit"] = proc.wait()
        logf.close()

    threading.Thread(target=_watch, daemon=True).start()


def read_runlog(offset):
    if not RUNLOG.exists():
        return b"", 0
    with open(RUNLOG, "rb") as f:
        f.seek(offset)
        data = f.read()
    return data, offset + len(data)


# ======================================================================
# Lectura de estado (read-only; el servidor nunca escribe nada aqui)
# ======================================================================
SCORE_RE = re.compile(r"Resultado Final:\s*(\d+)\s*/\s*(\d+)")


def _num_with_key(txt, keypart):
    for k, v in re.findall(r"([A-Za-z_]\w*)\s*[:=]\s*([0-9.]+)", txt):
        if keypart in k.lower():
            try:
                return float(v)
            except ValueError:
                pass
    return None


def lab_state():
    st = {"active": False, "status": None, "exam": None,
          "time_limit": None, "remaining": None}
    ef = STATE_DIR / "current_exam.yml"
    if ef.exists():
        txt = ef.read_text(errors="ignore")
        m = re.search(r"^\s*id:\s*(\S+)", txt, re.M)
        if m:
            st["exam"] = m.group(1)
        tl = _num_with_key(txt, "time_limit")
        if tl:
            st["time_limit"] = int(tl)
    sf = STATE_DIR / "exam_status.yml"
    if sf.exists():
        txt = sf.read_text(errors="ignore")
        m = re.search(r"^\s*status\s*:\s*(\w+)", txt, re.M)
        if m:
            st["status"] = m.group(1)
        start = _num_with_key(txt, "start")
        end = _num_with_key(txt, "end")
        if st["status"] in ("running", "expired") or (start and start > 1e9):
            st["active"] = True
        if start and start > 1e9:
            if end and end > 1e9:
                st["remaining"] = max(0, int(end - time.time()))
            elif st["time_limit"]:
                st["remaining"] = max(
                    0, int(start + st["time_limit"] * 60 - time.time()))
    return st


def last_results(n=5):
    try:
        logs = sorted(RESULTS_DIR.glob("*.log"),
                      key=lambda p: p.stat().st_mtime, reverse=True)
    except FileNotFoundError:
        return []
    out = []
    for p in logs[:n]:
        m = SCORE_RE.search(p.read_text(errors="ignore"))
        out.append({"file": p.name,
                    "passed": int(m.group(1)) if m else None,
                    "total": int(m.group(2)) if m else None})
    return out


# ======================================================================
# ANSI -> HTML (el verde/rojo/cyan del CLI lucen en el navegador)
# ======================================================================
ESC = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")
STYLE = {"31": "c-red", "32": "c-grn", "33": "c-yel", "34": "c-blu",
         "35": "c-mag", "36": "c-cyn", "37": "c-wht", "1": "b", "4": "u"}


def ansi_to_html(raw):
    t = html.escape(raw.decode("utf-8", "replace").replace("\r", "\n"))
    out, stack, pos = [], [], 0
    for m in ESC.finditer(t):
        out.append(t[pos:m.start()])
        if m.group(2) != "m":
            pos = m.end()
            continue
        codes = [c for c in m.group(1).split(";") if c]
        if not codes or "0" in codes:
            out.append("</span>" * len(stack))
            stack = []
        else:
            cls = " ".join(filter(None, (STYLE.get(c) for c in codes)))
            if cls:
                out.append('<span class="%s">' % cls)
                stack.append(cls)
        pos = m.end()
    out.append(t[pos:])
    out.append("</span>" * len(stack))
    return "".join(out)


# ======================================================================
# Frontend embebido (fichero unico a proposito: un heredoc lo despliega)
# ======================================================================
INDEX_HTML = """<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<title>RHCE_Lab - Consola del simulacro</title>
<style>
:root{--bg:#0d1117;--panel:#161b22;--border:#30363d;--fg:#e6edf3;--dim:#8b949e;
--grn:#3fb950;--red:#f85149;--cyn:#39c5ff;--yel:#d29922;--acc:#58a6ff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
font:14px/1.5 ui-monospace,'Cascadia Code','JetBrains Mono',Consolas,monospace}
header{display:flex;justify-content:space-between;align-items:center;
padding:14px 20px;border-bottom:1px solid var(--border);flex-wrap:wrap;gap:8px}
h1{font-size:15px;margin:0;color:var(--cyn);font-weight:600}
.chips{display:flex;gap:8px}
.chip{border:1px solid var(--border);border-radius:999px;padding:2px 10px;
font-size:12px;color:var(--dim)}
.chip b{color:var(--fg);font-weight:600}
main{max-width:980px;margin:0 auto;padding:20px;display:grid;gap:16px}
.row{display:grid;grid-template-columns:1fr auto;gap:16px;align-items:stretch}
.card{background:var(--panel);border:1px solid var(--border);
border-radius:10px;padding:16px}
.card h2{font-size:11px;margin:0 0 10px;color:var(--dim);
text-transform:uppercase;letter-spacing:.08em}
select,input[type=number]{background:var(--bg);color:var(--fg);
border:1px solid var(--border);border-radius:6px;padding:6px 8px;font:inherit}
button{background:#21262d;color:var(--fg);border:1px solid var(--border);
border-radius:6px;padding:8px 14px;font:inherit;cursor:pointer}
button:hover{border-color:var(--acc);color:var(--acc)}
button:disabled{opacity:.45;cursor:wait}
button.primary{background:#1f6feb;border-color:#1f6feb;color:#fff}
#timer{font-size:34px;text-align:right;color:var(--grn);line-height:1.1}
#timer.warn{color:var(--yel)} #timer.crit{color:var(--red)}
#term{background:#010409;border:1px solid var(--border);border-radius:10px;
padding:14px;min-height:320px;max-height:58vh;overflow:auto;white-space:pre-wrap;
word-break:break-word;font-size:13px}
.c-red{color:var(--red)}.c-grn{color:var(--grn)}.c-cyn{color:var(--cyn)}
.c-yel{color:var(--yel)}.c-blu{color:#79c0ff}.c-mag{color:#bc8cff}
.c-wht{color:#f0f6fc}.b{font-weight:700}.u{text-decoration:underline}
.badge{font-size:11px;color:var(--dim);margin-left:10px}
.foot{color:var(--dim);font-size:11px;text-align:center;padding:10px}
@media(max-width:720px){.row{grid-template-columns:1fr}#timer{text-align:left}}
</style></head><body>
<header>
  <h1>RHCE_Lab - Consola del simulacro</h1>
  <div class="chips">
    <span class="chip">examen: <b id="chip-exam">-</b></span>
    <span class="chip">ultimo: <b id="chip-last">-</b></span>
  </div>
</header>
<main>
  <div class="row">
    <div class="card">
      <h2>Generar examen</h2>
      <select id="difficulty">
        <option>mixed</option><option>easy</option>
        <option>medium</option><option>hard</option>
      </select>
      <input id="ntasks" type="number" min="1" max="99" value="5">
      <button class="primary" onclick="gen()">Generar</button>
    </div>
    <div class="card">
      <h2>Cronometro</h2>
      <div id="timer">--:--:--</div>
    </div>
  </div>
  <div class="card">
    <h2>Ejecutar</h2>
    <button onclick="runAction('start')">Iniciar cronometro</button>
    <button onclick="runAction('grade')">Grade</button>
    <button onclick="runAction('doctor')">Doctor</button>
    <button style="float:right" onclick="term.textContent=''">Limpiar</button>
    <span class="badge" id="runbadge"></span>
  </div>
  <div class="card">
    <h2>Salida del simulador</h2>
    <div id="term"></div>
  </div>
</main>
<div class="foot">solo loopback - acceso por tunel SSH (ssh -J) -
toda accion pasa por lab.sh</div>
<script>
const $=i=>document.getElementById(i);
const term=$('term');
let off=0,polling=false,lastRem=null;

function badge(t){$('runbadge').textContent=t||'';}
function setButtons(on){
  document.querySelectorAll('.card button').forEach(b=>b.disabled=!on);}

async function refreshStatus(){
  try{
    const s=await(await fetch('/api/status')).json();
    const ex=s.lab.exam?s.lab.exam+(s.lab.time_limit?' ('+s.lab.time_limit+'m)'):'-';
    $('chip-exam').textContent=ex;
    const L=s.last&&s.last[0];
    $('chip-last').textContent=L&&L.total!=null?L.passed+'/'+L.total:'-';
    lastRem=s.lab.remaining;paintTimer();
    if(s.running&&!polling){off=0;term.textContent='';poll();}
  }catch(e){}
}

async function runAction(action,params){
  try{
    const r=await fetch('/api/run',{method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({action:action,params:params||{}})});
    const j=await r.json();
    if(!r.ok){badge(j.error||('HTTP '+r.status));return;}
    term.textContent='';off=0;poll();
  }catch(e){badge('sin conexion con la webui');}
}

function gen(){
  runAction('generate',{n:$('ntasks').value,d:$('difficulty').value});}

async function poll(){
  polling=true;setButtons(false);badge('ejecutando...');
  let j;
  for(;;){
    try{
      j=await(await fetch('/api/output?offset='+off)).json();
    }catch(e){break;}
    if(j.chunk){
      term.insertAdjacentHTML('beforeend',j.chunk);
      term.scrollTop=term.scrollHeight;}
    off=j.next;
    if(!j.running)break;
    await new Promise(r=>setTimeout(r,700));
  }
  polling=false;setButtons(true);
  if(j)badge((j.action||'')+' -> exit '+j.exit);
  refreshStatus();
}

function paintTimer(){
  const el=$('timer'),rem=lastRem;
  if(rem==null){el.textContent='--:--:--';el.className='';return;}
  const h=String(Math.floor(rem/3600)).padStart(2,'0'),
        m=String(Math.floor(rem%3600/60)).padStart(2,'0'),
        s=String(Math.floor(rem%60)).padStart(2,'0');
  el.textContent=h+':'+m+':'+s;
  el.className=rem<300?'crit':(rem<900?'warn':'');
}

refreshStatus();
setInterval(refreshStatus,10000);
setInterval(()=>{if(lastRem!=null&&lastRem>0){lastRem--;paintTimer();}},1000);
</script></body></html>
"""


# ======================================================================
# HTTP
# ======================================================================
class Handler(BaseHTTPRequestHandler):
    server_version = "RHCE-webui/26"

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/":
            body = INDEX_HTML.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif u.path == "/api/status":
            self._json(200, {"running": is_running(),
                            "action": RUN["action"], "exit": RUN["exit"],
                            "lab": lab_state(), "last": last_results(),
                            "project": str(PROJECT_DIR)})
        elif u.path == "/api/output":
            try:
                off = int(parse_qs(u.query).get("offset", ["0"])[0])
            except ValueError:
                self._json(400, {"error": "offset invalido"})
                return
            data, nxt = read_runlog(off)
            self._json(200, {"chunk": ansi_to_html(data), "next": nxt,
                             "running": is_running(),
                             "action": RUN["action"], "exit": RUN["exit"]})
        else:
            self._json(404, {"error": "no existe"})

    def do_POST(self):
        if urlparse(self.path).path != "/api/run":
            self._json(404, {"error": "no existe"})
            return
        try:
            n = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            self._json(400, {"error": "JSON invalido"})
            return
        name = body.get("action")
        if name not in ACTIONS:
            self._json(400, {"error": "accion no permitida"})
            return
        params = {k: str(v) for k, v in (body.get("params") or {}).items()}
        if name == "generate":
            if not params.get("n", "").isdigit():
                self._json(400, {"error": "n debe ser un entero"})
                return
            if params.get("d") not in DIFFICULTIES:
                self._json(400, {"error": "dificultad no valida"})
                return
        try:
            argv = [a.format(**params) for a in ACTIONS[name]]
        except KeyError as e:
            self._json(400, {"error": "falta parametro %s" % e})
            return
        with LOCK:
            if is_running():
                self._json(409, {"error": "ocupado: %s en marcha" % RUN["action"]})
                return
            run_action(name, argv)
        self._json(200, {"ok": True, "action": name, "argv": argv})

    def log_message(self, *a):
        pass


def main():
    ap = argparse.ArgumentParser(description="Consola web del simulacro RHCE")
    ap.add_argument("--port", type=int, default=8888)
    ap.add_argument("--bind", default="127.0.0.1")
    a = ap.parse_args()
    if a.bind not in ("127.0.0.1", "localhost"):
        print("[!] Aviso: bind en %s expone la UI a la red (el proceso corre como root)." % a.bind)
    print("=" * 56)
    print(" RHCE_Lab webui - mando a distancia del CLI")
    print(" Escuchando en  http://%s:%d" % (a.bind, a.port))
    print(" Proyecto:       %s" % PROJECT_DIR)
    print(" Desde tu equipo (tunel ProxyJump):")
    print("   ssh -J root@<IP-laboratorio> -L %d:127.0.0.1:%d root@<IP-laboratoriob>"
          % (a.port, a.port))
    print("   y abre http://localhost:%d en el navegador" % a.port)
    print("=" * 56)
    ThreadingHTTPServer((a.bind, a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
