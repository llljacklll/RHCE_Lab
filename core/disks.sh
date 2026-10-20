# ============================================================
# core/disks.sh — discos de práctica: TODO automático
#
#  FUNCIONES:
#    lab_disks_finalize  → asegura discos + filtro LVM en cada
#                          nodo; wipe SOLO si el arranque es fresh
#    lab_disks_release   → libera loops al hacer down
#    lab_doctor          → chequeo rápido del laboratorio
#    lab_autostart       → instala el autoarranque (systemd)
#
#  MAPA FIJO (coincide con scenarios/task_pool.yml):
#    node1: loop0 loop1 | node2: loop2 loop3 | node3: loop4 loop5
#
#  POR QUÉ:
#    - Los loops y device-mapper son GLOBALES del kernel: los
#      nodos (--privileged) se ven los discos entre sí.
#    - El filtro LVM por nodo hace que cada nodo SOLO escanee
#      SUS discos: se acaban los falsos OK entre nodos.
#    - El wipe solo ocurre tras "lab.sh up/reset" (arranque
#      fresh). Un "lab.sh start" NO borra tu trabajo.
# ============================================================

# ---------- config ----------
DISK_IMG_DIR="/var/lib/rhce-lab/disks"
DISK_SIZE="512M"
FRESH_MARKER="/run/rhce-lab-fresh"

declare -A NODE_DISKS=(
    [node1]="loop0 loop1"
    [node2]="loop2 loop3"
    [node3]="loop4 loop5"
)

# ---------- auxiliares ----------
_node_up() {
    docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null \
        | grep -q true
}

_dev_in_node() {
    docker exec "$1" test -b "/dev/$2" 2>/dev/null
}

_loop_on_host() {
    [ -e "/sys/block/$1" ]
}

# ---------- filtro LVM por nodo ----------
# FIX12d: escribe el conf COMPLETO (anti-udev del
# original de la imagen + filtro por nodo). Sin
# udev_sync=0 / udev_rules=0 / obtain_device_list_
# from_udev=0, lvcreate aborta con "not found:
# device not cleared" (en el pod no hay udev).
_lab_lvm_filter() {
    local node="$1" re="" dev tmp
    for dev in ${NODE_DISKS[$node]}; do
        re+="${dev#loop}|"
    done
    re="${re%|}"
    tmp="/tmp/lvmlocal.$node.conf"
    cat > "$tmp" <<EOF
# ==========================================
#  RHCE LAB - Override LVM local (por nodo)
#  = anti-udev del original de la imagen +
#    filtro que aisla los discos DE CADA nodo
# ==========================================
devices {
    obtain_device_list_from_udev = 0
    use_devicesfile = 0
    filter = [
        "a[/dev/loop(${re})\$]",
        "a[/dev/md]",
        "a[/dev/mapper/luks-]",
        "r[.*]"
    ]
    global_filter = [
        "a[/dev/loop(${re})\$]",
        "a[/dev/md]",
        "a[/dev/mapper/luks-]",
        "r[.*]"
    ]
}

global {
    use_lvmetad = 0
}

activation {
    udev_sync = 0
    udev_rules = 0
}
EOF
    docker exec "$node" mkdir -p /etc/lvm 2>/dev/null
    docker cp "$tmp" "$node:/etc/lvm/lvmlocal.conf" 2>/dev/null
    rm -f "$tmp"
}

# ---------- wipe por nodo ----------
_lab_wipe_node() {
    local node="$1" dev
    for dev in ${NODE_DISKS[$node]}; do
        docker exec "$node" wipefs -a "/dev/$dev" \
            >/dev/null 2>&1 \
          && echo "  [OK] $node: /dev/$dev pristino"
    done
}

# ============================================================
# lab_disks_finalize — la llama _finalize_startup (docker.sh)
#   - idempotente: attach host si falta, mknod si hace falta
#   - wipe SOLO si existe el marcador fresh (lab.sh up/reset)
# ============================================================
lab_disks_finalize() {
    local node dev img
    echo "---- discos por nodo -----------------------"
    for node in node1 node2 node3; do
        if ! _node_up "$node"; then
            echo "  [..] $node no arrancado, salto"
            continue
        fi
        for dev in ${NODE_DISKS[$node]}; do
            img="$DISK_IMG_DIR/${node}-${dev}.img"
            if ! _dev_in_node "$node" "$dev"; then
                if ! _loop_on_host "$dev"; then
                    mkdir -p "$DISK_IMG_DIR"
                    [ -f "$img" ] \
                      || truncate -s "$DISK_SIZE" "$img"
                    modprobe loop 2>/dev/null || true
                    losetup "/dev/$dev" "$img" 2>/dev/null \
                        || losetup -f "$img" >/dev/null 2>&1
                fi
                docker exec "$node" bash -c \
                  "[ -b /dev/$dev ] || \
                   mknod /dev/$dev b 7 ${dev#loop}" \
                  >/dev/null 2>&1
            fi
            if _dev_in_node "$node" "$dev"; then
                echo "  [OK] $node <- /dev/$dev"
            else
                echo "  [!!] $node SIN /dev/$dev"
            fi
        done
        _lab_lvm_filter "$node"
        echo "  [OK] $node filtro LVM aplicado"
        if [ -f "$FRESH_MARKER" ]; then
            _lab_wipe_node "$node"
        fi
    done
    rm -f "$FRESH_MARKER"
    echo "---------------------------------------------"
}

# ============================================================
# lab_disks_release — liberar loops al hacer down
#   Sin esto, los números se desplazan entre resets
#   (loop0/2/4 deben seguir siendo loop0/2/4).
# ============================================================
lab_disks_release() {
    local dev
    for dev in loop0 loop1 loop2 loop3 loop4 loop5; do
        if _loop_on_host "$dev"; then
            losetup -d "/dev/$dev" 2>/dev/null \
              && echo "  [OK] liberado /dev/$dev"
        fi
    done
    return 0
}

# ============================================================
# lab_doctor — estado general en 10 segundos
# ============================================================
lab_doctor() {
    local c node dev fs
    echo "=== RHCE Lab :: doctor ====================="
    if docker info >/dev/null 2>&1; then
        echo "[OK] docker daemon"
    else
        echo "[!!] docker daemon NO responde"
        return 1
    fi
    for c in control node1 node2 node3; do
        if _node_up "$c"; then
            echo "[OK] contenedor $c"
        else
            echo "[!!] contenedor $c parado"
        fi
    done
    for node in node1 node2 node3; do
        _node_up "$node" || continue
        for dev in ${NODE_DISKS[$node]}; do
            if _dev_in_node "$node" "$dev"; then
                fs=$(docker exec "$node" lsblk -ndo FSTYPE \
                     "/dev/$dev" 2>/dev/null)
                echo "[OK] $node /dev/$dev (fstype='${fs:-vacio}')"
            else
                echo "[!!] $node SIN /dev/$dev"
            fi
        done
        if docker exec "$node" grep -q global_filter \
              /etc/lvm/lvmlocal.conf 2>/dev/null; then
            echo "[OK] $node filtro LVM presente"
        else
            echo "[!!] $node sin filtro LVM"
        fi
    done
    echo "============================================"
}

# ============================================================
# lab_autostart — el lab se levanta solo con la MV (systemd)
# ============================================================
lab_autostart() {
    local dir unit
    dir=$(cd "$(dirname "$(readlink -f \
          "${BASH_SOURCE[0]}")")/.." && pwd)
    unit=/etc/systemd/system/rhce-lab.service
    cat > "$unit" <<EOF
[Unit]
Description=RHCE Lab (autoarranque con la MV)
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$dir
ExecStart=$dir/lab.sh up
ExecStop=$dir/lab.sh stop

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable rhce-lab.service >/dev/null 2>&1
    echo "[OK] autoarranque instalado: rhce-lab.service"
    echo "     La proxima vez que arranques la MV, el lab"
    echo "     se levanta solo (tras docker.service)."
    echo "     Para quitarlo: systemctl disable rhce-lab"
}
