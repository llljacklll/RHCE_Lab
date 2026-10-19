#!/usr/bin/env bash
# ============================================================
# bootstrap.sh — MV recién restaurada → lab listo "de primera"
#
#   bash bootstrap.sh
#
#   1. docker instalado y activo (si faltaba)
#   2. repo actualizado (si hay red)
#   3. lab.sh up  → contenedores + discos + filtro LVM + ssh
#   4. lab.sh doctor → resumen de estado
#
#   Nota: el wipe de discos ocurre DENTRO de lab.sh up
#   (arranque fresh). Restore de MV + bootstrap = lab prístino.
# ============================================================
set -u
LAB_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

step() { echo -e "\n=== $* ==="; }
ok()   { echo "  [OK] $*"; }
warn() { echo "  [!!] $*"; }

step "1/4 Docker"
if command -v docker >/dev/null 2>&1; then
    ok "docker presente: $(docker --version 2>/dev/null)"
else
    warn "docker no encontrado, instalando..."
    if command -v dnf >/dev/null 2>&1; then
        dnf -y install docker-ce 2>/dev/null \
          || dnf -y install moby-engine 2>/dev/null \
          || dnf -y install docker
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get -y install docker.io
    else
        warn "no se detecto gestor de paquetes (dnf/apt)"
    fi
fi
systemctl enable --now docker 2>/dev/null \
  || service docker start 2>/dev/null || true
if docker info >/dev/null 2>&1; then
    ok "docker daemon activo"
else
    warn "docker daemon NO responde (revisa y relanza)"
    exit 1
fi

step "2/4 Repo"
if [ -d "$LAB_DIR/.git" ]; then
    ok "repo en $LAB_DIR"
    git -C "$LAB_DIR" pull --ff-only >/dev/null 2>&1 \
      && ok "actualizado a $(git -C "$LAB_DIR" \
             rev-parse --short HEAD)" \
      || warn "sin actualizar (sin red o divergencia) — sigo"
else
    warn "$LAB_DIR no es un clone git — sigo igualmente"
fi

step "3/4 Levantando el laboratorio (lab.sh up)"
[ -x "$LAB_DIR/lab.sh" ] || chmod +x "$LAB_DIR/lab.sh"
"$LAB_DIR/lab.sh" up || { warn "lab.sh up fallo"; exit 1; }

step "4/4 Doctor"
"$LAB_DIR/lab.sh" doctor || true

echo
echo "=== LISTO ==================================="
echo "  entrar al nodo control:  $LAB_DIR/lab.sh shell"
echo "  autoarranque con la MV:  $LAB_DIR/lab.sh autostart"
echo "=============================================="
