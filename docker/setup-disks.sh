#!/bin/bash
# ==========================================
#  setup-disks.sh v2 — discos LVM fake (MV)
#  - EL10 no crea /dev/loopN: mknod propio
#  - los loops son GLOBALES en el kernel ->
#    pareja FIJA por nodo para no pisarse:
#      node1 -> loop0/1   node2 -> loop2/3
#      node3 -> loop4/5   control -> nada
#  - PROHIBIDO 'losetup -D' (desmontaria
#    los discos de los OTROS nodos)
# ==========================================
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
