#!/bin/bash
# ============================================================
#  DOCKER/SETUP-DISKS.SH — Discos LVM fake por nodo (arranque)
# ------------------------------------------------------------
#  Lo invoca fake-disks.service en cada boot: deja a CADA nodo
#  con SU pareja de /dev/loopN de 1G para las prácticas LVM.
#
#  DISEÑO:
#   - Los loop devices son GLOBALES en el kernel (compartidos
#     por todos los contenedores): por eso cada nodo tiene una
#     pareja FIJA y solo toca la suya:
#       node1 -> loop0/1   node2 -> loop2/3
#       node3 -> loop4/5   control -> ninguno
#   - Identidad por hostname O por IP fija (case con ambas):
#     robusto aunque falle el hostname temporal.
#   - EL10 no crea /dev/loopN por sí solo: mknod propio de
#     loop-control y de los dos loops si faltan.
#   - Si el kernel aún no tiene ese número de loop, se registra
#     desde dentro con LOOP_CTL_ADD (ioctl 0x4C80; exige
#     privileged) y se reintenta el attach.
#   - PROHIBIDO 'losetup -D': es global y desmontaría también
#     los discos de los OTROS nodos.
#   - wipefs al final: cada arranque nace limpio; una práctica
#     a medias de ayer no contamina la de hoy.
#   - set -e: cualquier fallo corta el script entero — un nodo
#     con medio disco adjunto es peor que un nodo sin discos.
# ============================================================
set -e
DISK_DIR="/opt/lvm_disks"; mkdir -p "$DISK_DIR"

# identidad del contenedor: hostname o IP fija (python3 siempre esta en los nodos)
SELF_IP=$(python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.connect(("172.20.0.10",1)); print(s.getsockname()[0])' 2>/dev/null || true)
case "${HOSTNAME} ${SELF_IP}" in
    *node1*|*172.20.0.11*) L0=0; L1=1 ;;
    *node2*|*172.20.0.12*) L0=2; L1=3 ;;
    *node3*|*172.20.0.13*) L0=4; L1=5 ;;
    *) echo "fake-disk: '${HOSTNAME}' no lleva discos (skip)"; exit 0 ;;
esac
D0=/dev/loop$L0; D1=/dev/loop$L1
echo "fake-disk: ${HOSTNAME} -> $D0 $D1"

# nodos loop: crear si faltan (EL10 no los trae)
[ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237
[ -b "$D0" ] || mknod "$D0" b 7 "$L0"
[ -b "$D1" ] || mknod "$D1" b 7 "$L1"

# imagenes 1G y attach SOLO a los propios
truncate -s 1G "$DISK_DIR/disk1.img" "$DISK_DIR/disk2.img"

# DM fantasma + loops zombi: dm y loops son GLOBALES en el kernel
# y sobreviven al recreate del contenedor. Un LV activo de la
# generacion anterior retiene MI loop: losetup -d y el attach
# acaban en EBUSY y set -e mata el servicio (node1/node2 en el
# up de las 15:58; node3 en el de las 16:40 pese al ancla de un
# solo pase: la remocion forzada de un dm puede quedar DIFERIDA
# unos segundos y un solo intento no converge). Ahora la limpieza
# es CONVERGENTE (reintenta y verifica por sysfs) y el attach
# reintenta con re-limpieza. Solo toco los dm cuyo slave DIRECTO
# es uno de mis loops: jamas los dm de otros nodos.
limpia_dms() {
    for d in "$D0" "$D1"; do
        for dm in /sys/block/dm-*; do
            [ -e "$dm/slaves/${d#/dev/}" ] || continue
            base=${dm#/sys/block/}
            majmin=$(cat "$dm/dev" 2>/dev/null) || continue
            [ -e "/dev/$base" ] || mknod "/dev/$base" b \
                "${majmin%:*}" "${majmin#*:}" 2>/dev/null || true
            dmsetup remove -f "/dev/$base" 2>/dev/null || true
        done
    done
}
suela_loops() {
    losetup -d "$D0" 2>/dev/null || true
    losetup -d "$D1" 2>/dev/null || true
}
loop_libre() {  # $1=/dev/loopN -> RC 0 si SIN backing (libre)
    [ ! -e "/sys/block/${1#/dev/}/loop/backing_file" ]
}
registra_loops() {
    # kernel device sin registrar: LOOP_CTL_ADD desde dentro (privileged)
    python3 - <<'PYEOF' 2>/dev/null || true
import fcntl, os
fd = os.open('/dev/loop-control', os.O_RDWR)
for j in range(8):
    try: fcntl.ioctl(fd, 0x4C80, j)
    except OSError: pass
PYEOF
}
adjunta() {  # $1=/dev/loopN  $2=imagen
    local i
    for i in 1 2 3 4 5; do
        if losetup "$1" "$2" 2>/dev/null; then
            return 0
        fi
        limpia_dms
        suelta_loops
        registra_loops
        sleep 1
    done
    # ultimo intento EN VOZ ALTA: si falla, set -e mata el servicio
    losetup "$1" "$2"
}

# frenar posibles interferentes LVM (no-op si ya van saltados)
systemctl stop lvm2-monitor.service dm-event.socket dm-event.service \
    2>/dev/null || true
udevadm settle --timeout=3 2>/dev/null || true

# convergencia: hasta ~10s dejando MIS loops libres antes del attach
i=1
while [ "$i" -le 10 ]; do
    limpia_dms
    suelta_loops
    if loop_libre "$D0" && loop_libre "$D1"; then
        break
    fi
    sleep 1
    i=$((i+1))
done
if ! ( loop_libre "$D0" && loop_libre "$D1" ); then
    echo "fake-disk: AVISO: $D0/$D1 siguen ocupados tras 10s" >&2
fi

adjunta "$D0" "$DISK_DIR/disk1.img"
adjunta "$D1" "$DISK_DIR/disk2.img"

# verificacion honesta: ambos discos con su 1G real (no medio disco)
for d in "$D0" "$D1"; do
    sz=$(blockdev --getsize64 "$d" 2>/dev/null || echo 0)
    if [ "$sz" -ne 1073741824 ]; then
        echo "fake-disk: $d sin 1G real (size=$sz)" >&2
        exit 1
    fi
done
wipefs -a "$D0" 2>/dev/null || true
wipefs -a "$D1" 2>/dev/null || true

# lvm.conf (lvmlocal.conf ya cubre el grueso)
grep -q "use_devicesfile = 0" /etc/lvm/lvm.conf \
    || sed -i '/^devices {/a\    use_devicesfile = 0' /etc/lvm/lvm.conf
echo "LVM Ready: ${HOSTNAME} -> $D0 $D1"
