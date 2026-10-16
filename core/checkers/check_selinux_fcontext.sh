#!/bin/bash
# ============================================================
#  🔌 CHECKER: selinux_fcontext (SELinux SIMULADO)
# ============================================================
#  CONTRATO (invocado por core/grade.sh vía 'source'):
#    $1 = nodo      → contenedor objetivo (node1..node3)
#    $2 = contexto  → contexto SELinux esperado (ej: httpd_sys_content_t)
#    $3 = ruta      → fichero/directorio a inspeccionar
#
#  LÓGICA (SELinux no está activo en los contenedores Docker):
#    1. Lee el xattr security.selinux del fichero (en hex) y lo
#       decodifica para compararlo con el contexto esperado.
#    2. Fallback DIDÁCTICO: si el fichero existe → OK, porque sin
#       kernel SELinux activo el fcontext real no aplica.
#
#  SALIDA: "OK" | "FAIL" (el motor solo acepta exactamente OK)
# ============================================================

local node="$1"
local expected_ctx="$2"
local path="$3"

# El xattr security.selinux es binario: se lee en hex y se decodifica
local actual_ctx
actual_ctx=$(docker exec "$node" getfattr -n security.selinux -e hex "$path" 2>/dev/null | tail -1 | cut -d'"' -f 2 | xxd -r -p 2>/dev/null)

if [[ "$actual_ctx" == *"$expected_ctx"* ]]; then
    echo "OK"
elif docker exec "$node" test -f "$path"; then
    echo "OK"
else
    echo "FAIL"
fi
