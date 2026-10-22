#!/bin/bash
# ============================================================
#  core/checkers/check_package.sh — plugin de corrección: RPM
# ------------------------------------------------------------
#  QUÉ VALIDA: que un paquete RPM esté instalado en el nodo.
#
#  CONTRATO con _run_check (grade.sh), común a TODOS los
#  plugins de core/checkers/:
#    - No son funciones: son FRAGMENTOS que _run_check carga
#      con "source" DENTRO de su propia función; por eso
#      pueden usar `local` y ven las variables del llamador.
#    - $1 = node .. contenedor gestionado a comprobar (una
#      pasada por cada nodo de LAB_NODES, con __NODE__ ya
#      expandido en name/path si el YAML lo usaba).
#    - $2 = name .. parámetro principal de la tarea (aquí:
#      el nombre del paquete, p. ej. "tree").
#    - $3 = path .. parámetro secundario (aquí: sin uso).
#    - SALIDA: UNA línea en stdout, "OK" o "FAIL <razón>":
#      la razón viaja al reporte y de ahí al log de
#      state/results/. Los avisos de infraestructura van a
#      stderr. _run_check corta el examen al primer FAIL.
#
#  HONESTIDAD PRISTINO=>FAIL: en un laboratorio recién
#  montado el paquete NO está y este check canta FAIL sin
#  necesitar nada más. Se valida ESTADO (rpm -q consulta la
#  base de datos RPM), no procesos ni ficheros del alumno.
# ============================================================
local node="$1"; local pkg="$2"
if docker exec "$node" rpm -q "$pkg" >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAIL el paquete $pkg no está instalado en $node (rpm -q)"
fi
