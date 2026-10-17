#!/bin/bash
# ============================================================
#  RHCE LAB - Guion automatizado para grabar el video
#  Un solo comando lanza todo el flujo, con pausas de video
#  y marcas de tiempo T+mm:ss en pantalla.
#
#  Uso:
#    PACING=1 ./scripts/demo_video.sh   ritmo normal (~5-6 min)
#    PACING=2 ./scripts/demo_video.sh   ritmo lento (mucha narracion)
#    PACING=0 ./scripts/demo_video.sh   ensayo rapido (sin pausas)
#    AUTO=1 ./scripts/demo_video.sh     sin pausa interactiva
#
#  Ctrl+C aborta en cualquier momento.
# ============================================================
set -u
P="${PACING:-1}"
cd ~/RHCE_Lab || { echo "[FAIL] no encuentro ~/RHCE_Lab"; exit 1; }

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
