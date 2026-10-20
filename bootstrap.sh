#!/usr/bin/env bash
# ============================================================
#  RHCE_Lab — bootstrap.sh (v1.3.1)
#  La promesa del README: MV recién restaurada de CUALQUIER
#  snapshot → TODO listo en un solo comando.
#
#  Cadena:
#    [1/5] dependencias del host (vm_bootstrap si falta algo)
#    [2/5] git: sanear el árbol y alinear con GitHub
#    [3/5] lab.sh up   [4/5] lab.sh doctor   [5/5] resumen
#
#  Filosofía DR: GitHub es la única fuente de verdad.
#  Un snapshot puede traer el árbol "sucio" (cambios locales sin
#  commit, restos de iteraciones viejas). pull --ff-only se niega
#  a pisarlos POR DISEÑO, así que aquí sanemos ANTES:
#  fetch + reset --hard origin/main + clean.
#  Ningún snapshot, por sucio que sea, vuelve a bloquear el DR.
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

echo "== [1/5] Dependencias del host =="
if ! command -v docker >/dev/null 2>&1 \
   || ! docker compose version >/dev/null 2>&1 \
   || [ ! -e /dev/loop-control ]; then
    echo "[!] Faltan dependencias -> ejecutando scripts/vm_bootstrap.sh"
    bash scripts/vm_bootstrap.sh
else
    echo "[OK] docker + compose + loop-control presentes"
fi

echo "== [2/5] Git: sanear árbol y alinear con GitHub =="
echo "-- cambios locales (se descartan; el remoto manda):"
git status --short | head -20 || true
git fetch origin
git reset --hard origin/main
git clean -qfd
echo "-- alineado con:"
git log --oneline -1

echo "== [3/5] Levantando el laboratorio =="
./lab.sh up

echo "== [4/5] Doctor =="
./lab.sh doctor

echo "== [5/5] Resumen =="
./lab.sh | grep -E 'Version|Status|Nodes' || true
echo "[DONE] bootstrap completo. Laboratorio DR operativo."
