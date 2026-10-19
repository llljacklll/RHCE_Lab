#!/usr/bin/env bash
# ============================================================================
# demo_video_full.sh - v1.1.2 - DEMO COMPLETA: dependencias + laboratorio
#
# SECCION 0 (nueva): auto-provisiona el host via scripts/vm_bootstrap.sh:
#   docker-ce + compose plugin, python3 + PyYAML, unidad rhce-lab-loop.
#   FIX10: ademas crea ansible/files/.vault_pass si falta (el repo lo ignora
#   a proposito en .gitignore -> un clone fresco no lo trae; lo necesitan
#   el smoke 5/5 y ansible-vault).
# Despues delega en scripts/demo_video.sh (secciones 1-7 del guion original).
# PACING y AUTO se respetan (defecto 1/1). Idempotente: si ya esta instalado,
# la seccion 0 solo verifica y pasa adelante en segundos.
#
# Uso:   bash /root/RHCE_Lab/scripts/demo_video_full.sh          (grabacion)
#        PACING=0 bash /root/RHCE_Lab/scripts/demo_video_full.sh (ensayo)
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
T0=$(date +%s)

tstamp(){ local S=$(( $(date +%s) - T0 )); printf '\033[1;36m[T+%02d:%02d]\033[0m ' $(( S/60 )) $(( S%60 )); }
banner(){ printf '\n\033[1;35m%s\033[0m\n\033[1;35m%s\033[0m\n\033[1;35m%s\033[0m\n' \
  "============================================================" "$*" \
  "============================================================"; }

banner "RHCE EX294 LAB - DEMO COMPLETA (dependencias + laboratorio)"
echo "Guion: seccion 0 = dependencias del host (vm_bootstrap.sh)"
echo "       secciones 1-7 = laboratorio completo (demo_video.sh)"
echo

# ---------------------------------------------------------------------------
banner "SECCION 0 - DEPENDENCIAS DEL HOST (vm_bootstrap.sh)"
echo "El laboratorio instala sus propios requisitos (idempotente):"
echo "  - docker-ce + docker-compose-plugin (repo oficial EL10)"
echo "  - python3 + PyYAML (generador de examenes --random)"
echo "  - unidad systemd rhce-lab-loop (discos dedicados por nodo)"
echo
tstamp; echo -n "Estado actual: "
if command -v docker >/dev/null 2>&1; then
  docker --version
else
  echo "docker NO instalado -> se instala ahora (~2-4 min)"
fi
tstamp; echo -n "PyYAML: "
python3 -c 'import yaml; print("OK", yaml.__version__)' 2>/dev/null || echo "ausente -> se instala"
tstamp; echo -n "Discos loop: "
[ -e /dev/loop0 ] && echo "/dev/loop0 presente" || echo "ausente -> la unidad los creara"
echo

tstamp; echo "Lanzando scripts/vm_bootstrap.sh (salida en vivo)..."
echo
bash "$SCRIPT_DIR/vm_bootstrap.sh" || { banner "[X] vm_bootstrap.sh FALLO (mirar output arriba)"; exit 1; }

echo
tstamp; echo "Verificacion post-install:"
docker --version
docker compose version
python3 -c 'import yaml; print("PyYAML", yaml.__version__)'
tstamp; echo -n "Discos loop: "
[ -e /dev/loop0 ] && lsblk -ndo NAME,SIZE /dev/loop0 && echo "     [OK] listo para el laboratorio" || echo "[i] se crearan al arrancar"
echo

# --- FIX10: .vault_pass (gitignored a proposito, no viaja en el repo) --------
# Sin ese archivo fallan el smoke test (check 5/5) y ansible-vault (seccion 4).
tstamp; echo -n "Vault (.vault_pass): "
VP="$SCRIPT_DIR/../ansible/files/.vault_pass"
if [ ! -f "$VP" ]; then
  mkdir -p "$(dirname "$VP")"
  printf 'RhceLab2026\n' > "$VP"
  chmod 600 "$VP"
  echo "creado (gitignored a proposito, secreto local)"
else
  echo "presente"
fi
echo

# ---------------------------------------------------------------------------
banner "DEPENDENCIAS LISTAS -> DEMO DEL LABORATORIO (demo_video.sh)"
echo "Siguientes secciones: arranque + build de imagenes (1a vez ~2 min),"
echo "smoke 11 checks, discos por nodo, examen aleatorio, grade y cierre."
echo
cd "$SCRIPT_DIR/.."
exec bash "$SCRIPT_DIR/demo_video.sh"
