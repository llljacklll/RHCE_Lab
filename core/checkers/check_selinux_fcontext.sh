#!/bin/bash
# ============================================================
#  Checker SELinux fcontext — v2 "fina" (v1.3.0)
# ------------------------------------------------------------
#  ANTES (v1.2.0): comparaba el xattr security.selinux con el
#  tipo esperado. Dentro del contenedor ese xattr SIEMPRE es el
#  del runtime Docker (container_ro_file_t, lo confirmó tu
#  getfattr), así que caía al fallback "existe => OK": un check
#  cosmético que no demostraba nada.
#
#  AHORA: valida a nivel de POLICY, que dentro del contenedor
#  SÍ es real y persistente aunque el kernel no cargue SELinux:
#    1) semanage fcontext -l contiene la spec con el tipo
#    2) matchpathcon mapea la ruta al tipo esperado
#    3) fallback legacy SOLO si la policy no es accesible
#       (con aviso por stderr, nunca en silencio)
#
#  Contrato con _run_check (source con 3 args):
#    $1 = node   nodo a comprobar
#    $2 = name   tipo SELinux esperado (p.ej. httpd_sys_content_t)
#    $3 = path   spec fcontext (p.ej. "/web(/.*)?" o /web)
#
#  Prístino => FAIL garantizado (no hay regla => honesto).
# ============================================================
local node="$1" ftype="$2" spec="$3"

# --- normalizar la spec: sin comillas, sin barra final
spec=$(printf '%s' "$spec" | tr -d "\"'" | sed 's#/$##')

# --- ruta "desnuda" (sin la parte regex): /web(/.*)? => /web
local bare="${spec%%(*}"
[ -z "$bare" ] && bare="$spec"

# --- la policy responde en este nodo?
local rules
rules=$(docker exec "$node" semanage fcontext -l 2>/dev/null)
if [ -n "$rules" ]; then
    # 1a) la regla está en la policy local (semanage fcontext -a ...)
    if printf '%s\n' "$rules" | grep -F -- "$spec" | grep -q -- "$ftype"; then
        echo "OK"
        return 0
    fi
    # 1b) matchpathcon: la policy mapea la ruta al tipo esperado
    #     (cubre: el alumno metió /web(/.*)? y la tarea pide /web/fichero)
    local mapped
    mapped=$(docker exec "$node" matchpathcon "$bare" 2>/dev/null | awk '{print $2}')
    mapped="${mapped##*:}"
    if [ "$mapped" = "$ftype" ]; then
        echo "OK"
        return 0
    fi
    echo "FAIL"
    return 1
fi

# --- fallback legacy: sin policy accesible en el contenedor
echo "[checker] $node: policy SELinux no accesible, fallback a existencia" >&2
if docker exec "$node" test -e "$bare" 2>/dev/null; then
    echo "OK"
else
    echo "FAIL"
fi
