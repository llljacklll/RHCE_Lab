#!/bin/bash
# ============================================================
#  SCRIPTS/SMOKE_TEST.SH — Verificación integral del laboratorio
# ------------------------------------------------------------
#  5 grupos de checks en orden de dependencias (si uno falla,
#  los siguientes casi seguro también):
#    1/5 Contenedores — los 4 nodos arriba (docker ps).
#    2/5 Conectividad — ansible ping desde control (3/3 nodos).
#    3/5 Discos fake  — cada nodo con SU pareja de loops bien
#                       enganchada a sus .img de /opt/lvm_disks.
#    4/5 Aislamiento  — /dev/loop0 mide 1G usable y el nvme
#                       REAL del host no aparece en pvs (el
#                       filtro de lvmlocal.conf funciona).
#    5/5 Vault        — secrets.yml desencripta con .vault_pass
#                       y contiene db_password.
#
#  USO (desde la raíz del repo): ./scripts/smoke_test.sh
#  CONTRATO: exit 0 = LAB 100% READY (apto para examen);
#            exit 1 = FALLOS (resumen con recuentos).
#  Nota: el 5/5 necesita ansible/files/.vault_pass (no viaja
#  en git; lo crean create_vault.sh y la demo completa).
# ============================================================
cd "$(dirname "$0")/.." || { echo "no encuentro la raiz del repo"; exit 1; }

C_GREEN='\033[0;32m'; C_RED='\033[0;31m'; C_CYAN='\033[0;36m'; C_NC='\033[0m'
PASS=0; FAIL=0
ok()  { echo -e "  ${C_GREEN}[ OK ]${C_NC} $*"; PASS=$((PASS+1)); }
bad() { echo -e "  ${C_RED}[FAIL]${C_NC} $*"; FAIL=$((FAIL+1)); }
hdr() { echo -e "\n${C_CYAN}== $* ==${C_NC}"; }

hdr "1/5 Contenedores"
for c in control node1 node2 node3; do
    docker ps --format '{{.Names}}' | grep -qx "$c" && ok "$c up" || bad "$c caido"
done

hdr "2/5 Ansible: control -> nodos"
P=$(docker exec control ansible all -m ping 2>/dev/null | grep -c '"ping": "pong"')
[ "$P" -eq 3 ] 2>/dev/null && ok "ping 3/3 nodos" || bad "ping ${P:-0}/3"

hdr "3/5 Discos LVM fake (pareja propia por nodo)"
for n in node1:0 node2:2 node3:4; do
    c=${n%%:*}; l=${n##*:}
    docker exec $c losetup -a 2>/dev/null | grep -q "^/dev/loop$l:.*(/opt/lvm_disks/disk1.img)" \
        && ok "$c: /dev/loop$l <- disk1.img" \
        || bad "$c: /dev/loop$l sin disco (revisar fake-disk.service)"
done

hdr "4/5 LVM usable y aislamiento por nodo"
# (a) Capacidad: presencia y tamano de AMBOS discos de cada pareja (solo lectura).
for par in "node1:0 1" "node2:2 3" "node3:4 5"; do
    c=${par%%:*}; propios=${par#*:}
    for n in $propios; do
        SZ=$(docker exec "$c" blockdev --getsize64 "/dev/loop$n" 2>/dev/null)
        [ "$SZ" = "1073741824" ] && ok "$c: /dev/loop$n = 1G" || bad "$c: /dev/loop$n raro (tam=$SZ)"
    done
done
# (b) Admision + aislamiento con oraculo lvmdiskscan: escanea TODO lo que el
#     filtro deja ver a LVM (con PV o en blanco) y NADA mas. Evidencia 16A2:
#     lista la pareja completa de cada nodo (disco1 con PV + disco2 en blanco)
#     y oculta el nvme real, los vecinos y el resto. pvs -a queda DESCARTADO
#     como oraculo: en esta pila omite los discos en blanco de forma no fiable
#     (3 de 4 ejecuciones; sospecha hints/cache de LVM2, backlog LVMDISK-2).
#     Frente al contrato viejo (pvs == /dev/loop0), este check NO depende del
#     estado del lab: pasa en pristino y tras practica, porque no afirma
#     cuantos PV hay, solo QUE la pareja completa es admisible y nada ajeno
#     se cuela. Los unicos admitidos fuera de la pareja son los carve-outs del
#     propio filtro (/dev/md* y /dev/mapper/luks-*): asi es el contrato disenado.
for par in "node1:0 1" "node2:2 3" "node3:4 5"; do
    c=${par%%:*}; propios=${par#*:}
    LISTA=$(docker exec "$c" lvmdiskscan 2>/dev/null | awk '/\/dev\//{print $1}' | sort)
    ESPERA=$(for n in $propios; do echo "/dev/loop$n"; done | sort)
    FALTA=$(comm -23 <(echo "$ESPERA") <(echo "$LISTA"))
    EXTRA=$(comm -13 <(echo "$ESPERA") <(echo "$LISTA") | grep -vE '^/dev/md[0-9]*$|^/dev/mapper/luks-' || true)
    if [ -n "$FALTA" ]; then bad "$c: LVM no admite:$FALTA (ve: $(echo $LISTA | tr '\n' ' '))"
    elif [ -n "$EXTRA" ]; then bad "$c: filtro deja ver ajenos:$(echo $EXTRA | tr '\n' ' ')"
    else ok "$c: LVM admite su pareja completa y nada ajeno (aislamiento OK)"; fi
done

hdr "5/5 Ansible Vault"
docker exec control ansible-vault view --vault-password-file /opt/ansible/files/.vault_pass \
    /opt/ansible/files/secrets.yml 2>/dev/null | grep -q '^db_password:' \
    && ok "secrets.yml desencripta con .vault_pass" \
    || bad "vault: falta ansible/files/.vault_pass (RhceLab2026)"

echo -e ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${C_GREEN} ================================== ${C_NC}"
    echo -e "${C_GREEN}   LAB 100% READY   ($PASS checks)  ${C_NC}"
    echo -e "${C_GREEN} ================================== ${C_NC}"
    exit 0
else
    echo -e "${C_RED} ====== $FAIL FALLOS / $PASS OK ====== ${C_NC}"
    exit 1
fi
