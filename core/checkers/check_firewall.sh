#!/bin/bash
# ============================================================
#  core/checkers/check_firewall.sh — plugin: firewalld (dual)
# ------------------------------------------------------------
#  QUÉ VALIDA: que la configuración PERMANENTE de firewalld
#  contenga el puerto o servicio pedido en la zona dada. La
#  runtime se pierde al reiniciar: el examen pide permanente.
#
#  CONTRATO con _run_check (grade.sh), igual que TODA la
#  familia de core/checkers/:
#    $1 = node .. nodo a comprobar
#    $2 = name ... "8081/tcp" (puerto) o "https" (servicio):
#                  lleva '/' -> puerto; si no, servicio.
#    $3 = path ... zona; OPCIONAL (vacío -> "public")
#    SALIDA: UNA línea en stdout, "OK" o "FAIL <razón>".
#
#  POR QUÉ DUAL: el lab convive con dos realities:
#   - firewalld ARRANCADO (Docker nativo, examen real):
#     se pregunta con firewall-cmd --permanent.
#   - firewalld PARADO (modo offline histórico, herencia
#     WSL): se lee /etc/firewalld/zones/<zona>.xml, que es
#     exactamente lo que firewall-offline-cmd escribe.
# ============================================================
local node="$1"; local spec="$2"; local zone="${3:-public}"
local pat fwon=0
if docker exec "$node" systemctl is-active --quiet firewalld 2>/dev/null; then
    fwon=1
fi
if [ -z "$spec" ]; then
    echo "FAIL falta puerto o servicio ('name:' en el YAML)"
elif printf '%s' "$spec" | grep -q "/"; then
    if [ "$fwon" = 1 ]; then
        if docker exec "$node" firewall-cmd --permanent --zone="$zone" \
                --query-port="$spec" >/dev/null 2>&1; then
            echo "OK"
        else
            echo "FAIL el puerto $spec no está en la zona $zone de $node"
        fi
    else
        pat="<port port=\"${spec%/*}\" protocol=\"${spec#*/}\""
        if docker exec "$node" grep -qE -- "$pat" \
                "/etc/firewalld/zones/$zone.xml" 2>/dev/null; then
            echo "OK"
        else
            echo "FAIL el puerto $spec no está en $zone.xml de $node (offline)"
        fi
    fi
else
    if [ "$fwon" = 1 ]; then
        if docker exec "$node" firewall-cmd --permanent --zone="$zone" \
                --query-service="$spec" >/dev/null 2>&1; then
            echo "OK"
        else
            echo "FAIL el servicio $spec no está en la zona $zone de $node"
        fi
    else
        pat="<service name=\"$spec\""
        if docker exec "$node" grep -qE -- "$pat" \
                "/etc/firewalld/zones/$zone.xml" 2>/dev/null; then
            echo "OK"
        else
            echo "FAIL el servicio $spec no está en $zone.xml (offline)"
        fi
    fi
fi
