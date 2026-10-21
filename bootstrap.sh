#!/usr/bin/env bash
# ============================================================
#  RHCE_Lab — bootstrap.sh (v1.3.3)
#  El "disaster recovery" de un solo comando: MV recién restaurada
#  de CUALQUIER snapshot -> TODO listo en 5 pasos.
#
#  LA PROMESA (la misma del README): ejecutar esto y ponerse a trabajar.
#
#  CADENA:
#    [1/5] dependencias del host (vm_bootstrap si falta algo)
#    [2/5] git: sanear el árbol y alinear con GitHub
#    [3/5] ./lab.sh up    [4/5] ./lab.sh doctor    [5/5] resumen
#
#  FILOSOFÍA DR: GitHub es la ÚNICA fuente de verdad.
#  Un snapshot puede traer el árbol "sucio" (cambios sin commit, restos
#  de iteraciones viejas, ficheros sin trackear). 'git pull --ff-only'
#  se negaría a pisarlos POR DISEÑO, y eso bloquearía el DR — así que
#  aquí se SANEA ANTES de alinear: fetch + reset --hard + clean.
#
#  AVISO (quien clone el repo, léeme): el paso [2/5] DESCARTA sin piedad
#  cualquier cambio local sin commitear y borra lo untracked. Es el
#  contrato del bootstrap: el remoto manda. No ejecutar esto si tienes
#  trabajo local que quieras conservar.
# ============================================================

# -e aborta al primer fallo, -u pita por variables vacías, -o pipefail
# hace que un pipe falle si CUALQUIER eslabón falla (no solo el último).
# Para un script de DR, fallar RÁPIDO y ruidoso es lo correcto.
set -euo pipefail
# Trabajar siempre desde la raíz del repo, llámese desde donde se llame.
cd "$(dirname "$0")"

echo "== [1/5] Dependencias del host =="
# Igual que el preflight de lab.sh, pero comprobando /dev/loop-control
# (el dispositivo que PERMITE crear loops; lab.sh comprueba /dev/loop0,
# un loop ya creado: dos formas de preguntar "¿puedo hacer LVM aquí?").
if ! command -v docker >/dev/null 2>&1 \
   || ! docker compose version >/dev/null 2>&1 \
   || [ ! -e /dev/loop-control ]; then
    echo "[!] Faltan dependencias -> ejecutando scripts/vm_bootstrap.sh"
    bash scripts/vm_bootstrap.sh
else
    echo "[OK] docker + compose + loop-control presentes"
fi

echo "== [2/5] Git: sanear árbol y alinear con GitHub =="
# Transparencia: mostrar qué se va a descartar ANTES de descartarlo.
# '|| true': con pipefail, un git status fallido (p.ej. permisos raros)
# no debe abortar el DR por un listado meramente informativo.
echo "-- cambios locales (se descartan; el remoto manda):"
git status --short | head -20 || true
# Alineación dura con el remoto:
git fetch origin
git reset --hard origin/main
# 'clean -qfd': borra lo untracked (-f fuerza, -d incluye directorios,
# -q silencioso). Drástico A PROPÓSITO: garantiza que ningún snapshot,
# por sucio que sea, vuelva a bloquear el DR.
git clean -qfd
echo "-- alineado con:"
git log --oneline -1

echo "== [3/5] Levantando el laboratorio =="
./lab.sh up

echo "== [4/5] Doctor =="
./lab.sh doctor

echo "== [5/5] Resumen =="
# lab.sh sin argumentos pinta banner+ayuda; nos quedamos solo con las
# líneas de estado (Version/Status/Nodes). '|| true': si el grep no
# casa nada, los pasos 3 y 4 ya validaron el DR — no hay que fallar
# aquí por un filtro vacío.
./lab.sh | grep -E 'Version|Status|Nodes' || true
echo "[DONE] bootstrap completo. Laboratorio DR operativo."
