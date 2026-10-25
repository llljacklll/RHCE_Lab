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
 - LOTE 27 - terminal del nodo de control: /ws monta un bash de login
   con PTY sobre WebSocket (RFC6455 minimo escrito a mano, cero
   dependencias) y lo pinta xterm.js servido LOCAL (webui/static/).
   Mismo puerto => el tunel SSH NO cambia. Gate anti drive-by: /ws
   solo acepta Origin localhost/127.0.0.1 (un WS no tiene SOP y sin
   este gate cualquier web abierta en el navegador abriria un shell).
 - LOTE 28 - enunciado SIEMPRE a la vista: tarjeta Tareas del examen
   con [editar] (inyecta 'vim ansible/playbooks/<task>.yml' en la
   sesion WS) y [solucion] (soluciones/<task>.yml read-only). El
   terminal se DOCKA a la derecha sin ocultar la Salida del simulador.
   /api/exam y /api/solucion son LECTURA pura; task saneado [A-Za-z0-9_].

Solo stdlib (el python3 de la propia MV). Lanzar: ./lab.sh web
"""
import argparse
import base64
import codecs
import fcntl
import hashlib
import html
import json
import os
import pty
import re
import signal
import socket
import struct
import subprocess
import termios
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
#   results  -> state/results/*.log  (informe: "Nota  : N/N")
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
SCORE_RE = re.compile(r"^\s*Nota\s*:\s*(\d+)\s*/\s*(\d+)", re.M)


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
# LOTE 28 - tareas del examen y soluciones de referencia (solo LECTURA).
#   exam_tasks:    '- id: <task>' + '  description: ...' por tarea,
#                  tal como las serializa yaml.dump en current_exam.yml.
#   read_solution: task saneado [A-Za-z0-9_]+ ANTES de tocar el disco;
#                  sin ese gate un ?task=../../etc/passwd leeria ficheros
#                  que no son suyos.
# ======================================================================
TASK_ID_RE = re.compile(r"^\s*-\s+id:\s*(\S+)\s*$", re.M)
DESC_RE = re.compile(r"^\s+description:\s*(.+?)\s*$", re.M)
SOL_TASK_RE = re.compile(r"^[A-Za-z0-9_]+$")


def exam_tasks():
    ef = STATE_DIR / "current_exam.yml"
    if not ef.exists():
        return []
    txt = ef.read_text(errors="ignore")
    out = []
    for m in TASK_ID_RE.finditer(txt):
        rest = txt[m.end():]
        stop = re.search(r"^\s*-\s+id:|^\s*checks:", rest, re.M)
        span = rest[:stop.start()] if stop else rest
        d = DESC_RE.search(span)
        desc = d.group(1).strip() if d else ""
        if len(desc) > 1 and desc[0] == desc[-1] and desc[0] in "'\"":
            desc = desc[1:-1]
        out.append({"id": m.group(1), "desc": html.escape(desc)})
    return out


def read_solution(task):
    if not SOL_TASK_RE.match(task or ""):
        return None
    try:
        return (PROJECT_DIR / "soluciones" / (task + ".yml")
                ).read_text(errors="replace")
    except OSError:
        return None


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
<link rel="icon" href="data:,">
<link rel="stylesheet" href="/static/xterm.min.css">
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
#terminal-card{display:none}
#xtermbox{height:52vh;min-height:320px;background:#010409;
border:1px solid var(--border);border-radius:10px;padding:6px}
.termbar{display:flex;justify-content:space-between;align-items:center;
margin:0 0 10px}
.wson{color:var(--grn)} .wsoff{color:var(--dim)}
.duo{display:grid;gap:16px;align-items:stretch}
.task{display:flex;align-items:center;gap:10px;padding:7px 0;
border-bottom:1px solid var(--border);font-size:13px}
.task:last-child{border-bottom:0}
.task .tid{color:var(--cyn);font-size:11px;min-width:150px}
.task .desc{flex:1;color:var(--fg)}
.taskbtns{display:flex;gap:6px}
button.mini{padding:3px 10px;font-size:11px;border-radius:999px}
#solpre{background:#010409;border:1px solid var(--border);border-radius:10px;
padding:14px;overflow:auto;max-height:52vh;white-space:pre-wrap;margin:0;
font-size:12.5px}
body.termon #terminal-card{display:block}
body.termon .duo{grid-template-columns:minmax(0,1fr) minmax(0,48%)}
body.termon main{max-width:1400px}
body.termon #xtermbox{height:calc(100vh - 292px);min-height:340px}
@media(max-width:1100px){body.termon .duo{grid-template-columns:1fr}}
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
  <div class="card" id="taskcard">
    <h2>Tareas del examen
      <span class="badge">[editar] abre vim en el terminal - [solucion] solo lectura</span></h2>
    <div id="tasklist"><div class="task"><span class="desc">sin examen - Generar para listar tareas</span></div></div>
    <pre id="solpre" style="display:none"></pre>
  </div>
  <div class="card">
    <h2>Ejecutar</h2>
    <button onclick="runAction('start')">Iniciar cronometro</button>
    <button id="btnTerm" onclick="tToggle()">Terminal</button>
    <button onclick="runAction('grade')">Grade</button>
    <button onclick="runAction('doctor')">Doctor</button>
    <button style="float:right" onclick="term.textContent=''">Limpiar</button>
    <span class="badge" id="runbadge"></span>
  </div>
  <div class="duo">
  <div class="card" id="outcard">
    <h2>Salida del simulador</h2>
    <div id="term"></div>
  </div>
  <div class="card" id="terminal-card">
    <h2>Terminal del nodo de control
      <span class="badge">aqui se HACE el examen</span></h2>
    <div class="termbar">
      <span class="wsoff" id="wsState">terminal: desconectado</span>
      <button onclick="wsConnect()">Conectar</button>
    </div>
    <div id="xtermbox"></div>
  </div>
  </div>
</main>
<div class="foot">solo loopback - acceso por tunel SSH (ssh -J) -
toda accion pasa por lab.sh</div>
<script src="/static/xterm.min.js"></script>
<script src="/static/xterm-addon-fit.min.js"></script>
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
    const ex=s.lab.exam?s.lab.exam+(s.lab.time_limit?' ('+s.lab.time_limit+'m)':''):'-';
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
  refreshStatus();loadTasks();
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

// ---- LOTE 27: terminal del nodo de control (xterm.js + /ws) ----
let xt=null,fit=null,ws=null;
function wsSend(o){if(ws&&ws.readyState===1)ws.send(JSON.stringify(o));}
function wsTxt(t,on){const e=$('wsState');e.textContent='terminal: '+t;
  e.className=on?'wson':'wsoff';}
function wsConnect(){
  if(!window.Terminal||!window.FitAddon){
    wsTxt('faltan /static/xterm*.js (lote 27 S1)',false);return;}
  if(ws&&(ws.readyState===0||ws.readyState===1))return;
  if(!xt){
    xt=new Terminal({cursorBlink:true,fontSize:14,scrollback:5000,
      fontFamily:'ui-monospace,Menlo,Consolas,monospace',
      theme:{background:'#010409',foreground:'#e6edf3',cursor:'#58a6ff'}});
    fit=new FitAddon.FitAddon();xt.loadAddon(fit);xt.open($('xtermbox'));
    xt.onData(d=>wsSend({type:'input',data:d}));
    window.addEventListener('resize',()=>{if(document.body.classList.contains('termon')){
      fit.fit();wsSend({type:'resize',cols:xt.cols,rows:xt.rows});}});
  }
  wsTxt('conectando...',false);
  ws=new WebSocket((location.protocol==='https:'?'wss://':'ws://')+location.host+'/ws');
  ws.onopen=()=>{wsTxt('conectado',true);
    fit.fit();wsSend({type:'resize',cols:xt.cols,rows:xt.rows});};
  ws.onmessage=e=>{if(typeof e.data==='string')xt.write(e.data);};
  ws.onclose=()=>{wsTxt('desconectado (Conectar para reentrar)',false);};
  ws.onerror=()=>{wsTxt('error de socket',false);};
}
function tToggle(){
  const on=document.body.classList.toggle('termon');
  $('btnTerm').textContent=on?'Panel':'Terminal';
  if(on){wsConnect();if(fit)setTimeout(()=>fit.fit(),50);}
}

// ---- LOTE 28: enunciado a la vista + vim auto-apuntado + soluciones ----
async function loadTasks(){
  try{
    const j=await(await fetch('/api/exam')).json();
    const box=$('tasklist');
    if(!j.tasks||!j.tasks.length){
      box.innerHTML='<div class="task"><span class="desc">sin examen - Generar para listar tareas</span></div>';
      return;}
    box.innerHTML=j.tasks.map(t=>
      '<div class="task"><span class="tid">'+t.id+'</span>'+
      '<span class="desc">'+(t.desc||'')+'</span>'+
      '<span class="taskbtns">'+
      '<button class="mini" data-do="edit" data-id="'+t.id+'">editar</button>'+
      '<button class="mini" data-do="sol" data-id="'+t.id+'">solucion</button>'+
      '</span></div>').join('');
  }catch(e){}
}
$('tasklist').addEventListener('click',ev=>{
  const b=ev.target.closest('button.mini');
  if(!b)return;
  if(b.dataset.do==='edit')editTask(b.dataset.id);
  else solTask(b.dataset.id);
});
function editTask(id,retry){
  if(!ws||ws.readyState!==1){
    if(!document.body.classList.contains('termon'))tToggle();
    if((retry||0)<20)setTimeout(()=>editTask(id,(retry||0)+1),250);
    return;}
  wsSend({type:'input',data:'vim ansible/playbooks/'+id+'.yml\\r'});
}
async function solTask(id){
  try{
    const r=await fetch('/api/solucion?task='+encodeURIComponent(id));
    const j=await r.json();
    if(!r.ok){alert(j.error||('HTTP '+r.status));return;}
    const p=$('solpre');
    p.textContent='### soluciones/'+id+'.yml ###\\n\\n'+j.content;
    p.style.display='block';
    p.scrollIntoView({block:'nearest'});
  }catch(e){}
}
refreshStatus();
loadTasks();
setInterval(refreshStatus,10000);
setInterval(()=>{if(lastRem!=null&&lastRem>0){lastRem--;paintTimer();}},1000);
</script></body></html>
"""


# ======================================================================
# LOTE 27 - Terminal del nodo de control: /ws monta un bash de login
# con PTY y lo sirve a xterm.js. RFC6455 minimo escrito a mano (cero
# dependencias). Gate anti drive-by: un WS no tiene SOP y cualquier
# web del navegador podria apuntar a localhost, asi que /ws solo
# acepta Origin localhost/127.0.0.1 (o sin Origin: clientes CLI).
# ======================================================================
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
WS_MAX = 10 * 1024 * 1024
STATIC_FILES = {
    "xterm.min.css": "text/css; charset=utf-8",
    "xterm.min.js": "application/javascript; charset=utf-8",
    "xterm-addon-fit.min.js": "application/javascript; charset=utf-8",
}


def ws_frame(op, payload=b""):
    """Frame de servidor (sin mascara; el cliente SI enmascara)."""
    n = len(payload)
    if n < 126:
        head = struct.pack(">BB", 0x80 | op, n)
    elif n < 65536:
        head = struct.pack(">BBH", 0x80 | op, 126, n)
    else:
        head = struct.pack(">BBQ", 0x80 | op, 127, n)
    return head + payload


def ws_read(rf, n):
    """Lee n bytes exactos del stream del cliente."""
    buf = b""
    while len(buf) < n:
        chunk = rf.read(n - len(buf))
        if not chunk:
            raise ConnectionError("ws: cliente desconectado")
        buf += chunk
    return buf


def ws_recv(rf):
    """Lee un frame de cliente (RFC: siempre enmascarado). (op, datos)"""
    h = ws_read(rf, 2)
    op, masked, ln = h[0] & 0x0F, h[1] & 0x80, h[1] & 0x7F
    if ln == 126:
        ln = struct.unpack(">H", ws_read(rf, 2))[0]
    elif ln == 127:
        ln = struct.unpack(">Q", ws_read(rf, 8))[0]
    if ln > WS_MAX:
        raise ValueError("ws: frame gigante (%d)" % ln)
    if not masked:
        raise ConnectionError("ws: frame sin mascara")
    key = ws_read(rf, 4)
    data = bytearray(ws_read(rf, ln))
    for i in range(ln):
        data[i] ^= key[i & 3]
    return op, bytes(data)


class TerminalSession:
    """Un bash de login (cwd del lab) con PTY por cada cliente WS.

    Dos hilos: pty->ws (salida) y ws->pty (teclado/resize). Al morir
    cualquiera de los dos lados se mata el grupo completo de la sesion
    (bash + hijos tipo vim o ssh a los nodos gestionados)."""

    def __init__(self, sock, rfile):
        self.sock, self.rf = sock, rfile
        self.dead = False
        self.tlock = threading.Lock()
        self.slock = threading.Lock()
        self.dec = codecs.getincrementaldecoder("utf-8")("replace")
        self.pid, self.master = pty.fork()
        if self.pid == 0:                        # hijo: bash del lab
            os.environ["TERM"] = "xterm-256color"
            try:
                os.chdir(PROJECT_DIR)
            except OSError:
                pass
            try:
                os.execvp("/bin/bash", ["/bin/bash", "-l"])
            except Exception:
                os._exit(127)
        print("[ws] sesion abierta: pid %d (bash de login en %s)"
              % (self.pid, PROJECT_DIR), flush=True)
        threading.Thread(target=self._pty_to_ws, daemon=True).start()
        threading.Thread(target=self._ws_to_pty, daemon=True).start()

    def _send(self, op, payload=b""):
        if self.dead:
            return
        try:
            with self.slock:
                self.sock.sendall(ws_frame(op, payload))
        except OSError:
            self._teardown()

    def _pty_to_ws(self):
        try:
            while True:
                chunk = os.read(self.master, 65536)
                if not chunk:
                    break
                self._send(1, self.dec.decode(chunk).encode("utf-8", "replace"))
        except OSError:
            pass
        finally:
            try:
                os.close(self.master)
            except OSError:
                pass
        self._teardown()

    def _ws_to_pty(self):
        try:
            while True:
                op, data = ws_recv(self.rf)
                if op == 8:                      # close del cliente
                    break
                if op == 9:                      # ping -> pong
                    self._send(10, data)
                    continue
                if op in (1, 2):
                    msg = json.loads(data.decode("utf-8", "replace"))
                    if msg.get("type") == "input":
                        buf = str(msg.get("data", "")).encode("utf-8", "replace")
                        while buf:
                            buf = buf[os.write(self.master, buf):]
                    elif msg.get("type") == "resize":
                        fcntl.ioctl(self.master, termios.TIOCSWINSZ,
                                    struct.pack("HHHH",
                                                int(msg.get("rows") or 24),
                                                int(msg.get("cols") or 80),
                                                0, 0))
        except Exception:
            pass
        self._teardown()

    def _teardown(self):
        with self.tlock:
            if self.dead:
                return
            self.dead = True
            try:
                with self.slock:
                    self.sock.sendall(ws_frame(8, b""))   # close WS limpio
            except OSError:
                pass
            try:
                os.killpg(self.pid, signal.SIGKILL)       # bash + hijos
            except (ProcessLookupError, PermissionError):
                pass
            try:
                os.waitpid(self.pid, 0)                   # sin zombies
            except (ChildProcessError, OSError):
                pass
            try:
                os.close(self.master)
            except OSError:
                pass
            try:
                self.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                self.sock.close()
            except OSError:
                pass
            print("[ws] sesion cerrada: pid %d" % self.pid, flush=True)


# ======================================================================
# HTTP
# ======================================================================
class Handler(BaseHTTPRequestHandler):
    server_version = "RHCE-webui/28"
    ws_takeover = False            # /ws: el socket ya no es del handler

    def finish(self):
        if self.ws_takeover:       # no cerrar rfile/wfile: son del terminal
            return
        super().finish()

    def _static(self, name):
        ctype = STATIC_FILES.get(name)
        if not ctype:
            self._json(404, {"error": "estatico no permitido"})
            return
        try:
            body = (HERE / "static" / name).read_bytes()
        except OSError:
            self._json(404, {"error": "falta webui/static/%s (lote 27 S1)"
                              % name})
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _websocket(self):
        org = self.headers.get("Origin", "")
        host = org.split("//", 1)[-1].split(":")[0]
        if org and host not in ("localhost", "127.0.0.1"):
            self._json(403, {"error": "Origin no permitido"})
            return
        key = (self.headers.get("Sec-WebSocket-Key") or "").strip()
        up = self.headers.get("Upgrade", "").lower() == "websocket" \
            and "upgrade" in self.headers.get("Connection", "").lower()
        if not key or not up:
            self._json(400, {"error": "handshake WS invalido"})
            return
        acc = base64.b64encode(
            hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
        self.connection.sendall(
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n"
            b"Sec-WebSocket-Accept: " + acc.encode() + b"\r\n\r\n")
        self.close_connection = True
        TerminalSession(self.connection, self.rfile)   # desde aqui, suyo
        self.ws_takeover = True
        self.server._ws_sockets.add(self.connection)  # el server no lo cerrara

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path.startswith("/static/"):
            self._static(u.path[8:])
            return
        if u.path == "/ws":
            self._websocket()
            return
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
        elif u.path == "/api/exam":
            self._json(200, {"tasks": exam_tasks()})
        elif u.path == "/api/solucion":
            task = parse_qs(u.query).get("task", [""])[0]
            content = read_solution(task)
            if content is None:
                self._json(404, {"error": "sin solucion (task invalida o inexistente)"})
            else:
                self._json(200, {"task": task, "content": content})
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


class LabServer(ThreadingHTTPServer):
    """ThreadingHTTPServer que no cierra los sockets tomados por /ws."""

    def __init__(self, addr, handler):
        super().__init__(addr, handler)
        self._ws_sockets = set()

    def shutdown_request(self, request):
        if request in self._ws_sockets:
            self._ws_sockets.discard(request)
            return
        super().shutdown_request(request)


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
    print(" Terminal:       boton [Terminal] - bash del lab via /ws (lotes 27-28)")
    print(" Tareas:         [editar] vim en el terminal + [solucion] modo lectura")
    print("=" * 56)
    LabServer((a.bind, a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
