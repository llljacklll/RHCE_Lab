#!/bin/bash
# ============================================================
#  SCRIPTS/DEMO_VIDEO.SH — Guion automatizado de la grabación
# ------------------------------------------------------------
#  Un solo comando recorre la demo COMPLETA del laboratorio
#  (host -> arranque -> smoke -> vault/discos -> examen ->
#  corrección), con marcas T+mm:ss en pantalla para facilitar
#  el montaje del vídeo después.
#
#  USO (variables de ambiente, todas opcionales):
#    PACING=1  ritmo normal (~5-6 min de grabación)
#    PACING=2  ritmo lento (mucha narración en directo)
#    PACING=0  ensayo rápido (sin pausas)
#    AUTO=1    sin la pausa interactiva de la sección examen
#
#  DISEÑO:
#   - banner() y cmd() imprimen el comando en verde y LUEGO lo
#     ejecutan: la terminal graba piezas listas para el corte.
#   - ts() marca T+mm:ss desde el arranque del guion.
#   - Fallbacks: si falta smoke_test.sh o PyYAML en el host, la
#     demo sigue con comprobaciones básicas inline (no se cae).
#   - Sección 5: pausa interactiva para resolver tareas en vivo
#     desde otro terminal; ENTER pasa a la corrección.
#   - Ctrl+C aborta en cualquier momento sin dejar el lab
#     raro: todo lo ejecutado es idempotente.
#  NOTA (excepción funcional del lote 8): el cd era ~/RHCE_Lab
#  absoluto y rompía la cadena desde demo_video_full.sh en
#  cualquier otra ruta; ahora es relativo al repo.
# ============================================================
set -u
P="${PACING:-1}"
cd "$(dirname "$0")/.." || { echo "[FAIL] no encuentro la raíz del repo"; exit 1; }

T0=$(date +%s)
ts() { local e=$(( $(date +%s) - T0 )); printf 'T+%02d:%02d' $((e/60)) $((e%60)); }
banner() { printf '\n\033[1;36m========== %s [%s] ==========\033[0m\n' "$*" "$(ts)"; sleep "$((2*P))"; }
cmd() {
    printf '\033[1;32m%s\033[0m\n' "\$ $1"
    sleep "$((2*P))"
    bash -c "$1"
    sleep "$((2*P))"
}

clear
banner "RHCE AUTOMATION LAB - DEMO COMPLETA (snapshot fresco)"
echo "  Pausas: PACING=$P  (0=ensayo 1=video 2=relajado)"
sleep "$((3*P))"

# ---------- 1/7 EL HOST ----------
banner "1/7 EL HOST: Rocky 10 + Docker + loops persistentes"
cmd "who -b && uptime -p"
cmd "hostnamectl | sed -n '1,7p'"
cmd "docker --version && docker compose version"
cmd "systemctl is-active rhce-lab-loop && ls /dev/loop* | tr '\n' ' '; echo"
cmd "git log --oneline -8"
cmd "git tag -l 'v*' | tail -3"

# ---------- 2/7 LAB ARRIBA ----------
banner "2/7 LEVANTAR EL LABORATORIO"
if docker image inspect docker-control:latest >/dev/null 2>&1; then
    echo "[INFO] imagenes presentes -> arranque rapido"
    cmd "./lab.sh start"
else
    echo "[INFO] sin imagenes -> build completo"
    cmd "./lab.sh up"
fi
cmd "./lab.sh"

# ---------- 3/7 SMOKE ----------
banner "3/7 BATERIA DE VERIFICACION (smoke test)"
if [ -x scripts/smoke_test.sh ]; then
    cmd "./scripts/smoke_test.sh"
else
    echo "[AVISO] falta scripts/smoke_test.sh -> basicos inline"
    cmd "docker ps --format 'table {{.Names}}\t{{.Status}}'"
    cmd "docker exec control ansible all -m ping"
fi

# ---------- 4/7 ESTRELLA ----------
banner "4/7 PRUEBAS ESTRELLA: vault + discos por nodo"
cmd "docker exec control ansible all -m ping"
cmd "docker exec control ansible-vault view --vault-password-file /opt/ansible/files/.vault_pass /opt/ansible/files/secrets.yml"
cmd "docker exec node1 bash -c 'lsblk -o NAME,SIZE,TYPE /dev/loop0 /dev/loop1'"
cmd "docker exec node3 bash -c 'lsblk -o NAME,SIZE,TYPE /dev/loop4 /dev/loop5'"

# ---------- 5/7 EXAMEN ----------
banner "5/7 MODO EXAMEN"
if python3 -c 'import yaml' 2>/dev/null; then
    cmd "./lab.sh exam --random 3"
else
    echo "[AVISO] falta python3-pyyaml en el host -> examen estatico"
    cmd "./lab.sh exam easy/exam_001.yml"
fi
sleep 10
cmd "./lab.sh exam --start"

# ---------- PAUSA (resolucion opcional en vivo) ----------
if [ "${AUTO:-0}" = "1" ]; then
    sleep "$((5*P))"
else
    echo ""
    read -r -p ">> PAUSA: resuelve tareas en vivo si quieres (otro terminal). ENTER para corregir... " _
fi

# ---------- 6/7 GRADE ----------
banner "6/7 CORRECCION AUTOMATICA"
cmd "./lab.sh grade"

# ---------- 7/7 CIERRE ----------
banner "7/7 ESTADO FINAL"
cmd "./lab.sh"
echo ""
echo "[FIN] Guion completado - detén la grabación."
