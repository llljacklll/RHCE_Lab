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

# DM fantasma: los device-mapper son GLOBALES y sobreviven
# al recreate del contenedor. Un LV activo de la generacion
# anterior retiene MI loop: losetup -d y el attach acaban en
# EBUSY y set -e mata el servicio (asi murio node1/node2 en
# el up de las 15:58). Solo toco los dm cuyo slave DIRECTO
# es uno de mis loops: jamas toco los dm de otros nodos.
for d in "$D0" "$D1"; do
    for dm in /sys/block/dm-*; do
        [ -e "$dm/slaves/${d#/dev/}" ] || continue
        base=${dm#/sys/block/}
        majmin=$(cat "$dm/dev")
        [ -e "/dev/$base" ] || mknod "/dev/$base" b \
            "${majmin%:*}" "${majmin#*:}" 2>/dev/null || true
        dmsetup remove -f "/dev/$base" 2>/dev/null || true
    done
done
losetup -d "$D0" 2>/dev/null || true
losetup -d "$D1" 2>/dev/null || true
if ! losetup "$D0" "$DISK_DIR/disk1.img" 2>/dev/null; then
    # kernel device sin registrar: LOOP_CTL_ADD desde dentro (contenedor privilegiado)
    python3 - <<'PYEOF' 2>/dev/null || true
import fcntl, os
fd = os.open('/dev/loop-control', os.O_RDWR)
for i in range(8):
    try: fcntl.ioctl(fd, 0x4C80, i)
    except OSError: pass
PYEOF
    losetup "$D0" "$DISK_DIR/disk1.img"
fi
losetup "$D1" "$DISK_DIR/disk2.img"
wipefs -a "$D0" 2>/dev/null || true
wipefs -a "$D1" 2>/dev/null || true

# lvm.conf (lvmlocal.conf ya cubre el grueso)
grep -q "use_devicesfile = 0" /etc/lvm/lvm.conf \
    || sed -i '/^devices {/a\    use_devicesfile = 0' /etc/lvm/lvm.conf
echo "LVM Ready: ${HOSTNAME} -> $D0 $D1"
