# ============================================================
#  core/disks.sh — discos de práctica: TODO automático
# ============================================================
#  RESPONSABILIDAD:
#    Poseer los discos "físicos" que necesitan las tareas de
#    almacenamiento del pool (LVM, filesystems, LUKS...):
#    crearlos como loop devices del HOST, exponerlos en cada
#    nodo, aislarlos por nodo, wipearlos solo en arranques
#    fresh y liberarlos limpios al hacer 'down'.
#
#  CÓMO LLEGA AQUÍ:
#    docker.sh sourcea este fichero AL FINAL (orden
#    histórico de sources). Las funciones quedan registradas
#    y el dispatch de lab.sh las usa como si fueran suyas.
#
#  FUNCIONES PÚBLICAS (menú de lab.sh):
#    lab_doctor ........ chequeo rápido del laboratorio
#    lab_autostart ..... instala el autoarranque (systemd)
#
#  FUNCIONES DEL CICLO DE VIDA (llamadas internas de
#  docker.sh):
#    lab_disks_finalize . asegura discos + filtro LVM en
#                         cada nodo; wipe SOLO si el arranque
#                         es fresh
#    lab_disks_release .. libera DM del lab + loops
#                         (al hacer 'down'/'reset')
#
#  AUXILIARES PRIVADOS (prefijo _):
#    _node_up _dev_in_node _loop_on_host _loop_wait
#    _lab_dm_release _lab_lvm_filter _lab_wipe_node
#
#  MAPA FIJO (coincide con scenarios/task_pool.yml):
#    node1: loop0 loop1 | node2: loop2 loop3 | node3: loop4 loop5
#
#  LAS TRES IDEAS CLAVE DEL FICHERO:
#    1. Los loop devices y el device-mapper son GLOBALES
#       del kernel: los nodos (--privileged) los comparten
#       y se ven los discos entre sí. Por eso hace falta
#       un filtro LVM explícito POR NODO (_lab_lvm_filter).
#    2. Los números de loop son FIJOS por nodo. Sin
#       lab_disks_release los números derivan entre resets
#       y una tarea corregida en node1 miraría a loop2.
#    3. El wipe solo ocurre en arranque fresh (up/reset,
#       marcador que crea docker.sh). Un 'lab.sh start' NO
#       toca los datos: puedes parar/arrancar el lab en
#       mitad de un examen sin perder nada.
#
#  LVs FANTASMA (la trampa del kernel compartido):
#    El registro de DM vive en el HOST, no en el nodo. Los
#    LV que queden activos al hacer 'down' SOBREVIVEN a
#    'docker rm': retienen los loops (EBUSY en losetup -d)
#    y bloquean nombres de VG en el próximo examen.
#    lab_disks_release los quita ANTES de liberar loops y
#    lab_doctor avisa si queda alguno suelto.
# ============================================================

# ---------- config ----------
# Los .img viven FUERA del repo (/var/lib/...): son estado
# de la máquina, no código, y el propio lab los recrea si
# faltan. Cada nodo tiene SUS dos imágenes
# (${node}-loopN.img) para que un wipe de node1 no pueda
# tocar jamás los datos de node2.
DISK_IMG_DIR="/var/lib/rhce-lab/disks"

# 512M: de sobra para pv/vg/lv + filesystem de las tareas,
# y lo bastante pequeño para que truncate sea instantáneo
# (fichero sparse: no ocupa disco hasta que se escribe).
DISK_SIZE="512M"

# Centinela de "este arranque debe dejar los discos
# prístinos". Lo crea docker.sh en up/reset y lo consume el
# primer finalize que lo ve. 'start' NO lo crea → nunca
# wypea un examen en curso.
FRESH_MARKER="/run/rhce-lab-fresh"

# Los loops de cada nodo. Array asociativo: las claves se
# iteran en cualquier orden y ${NODE_DISKS[$node]} expanda
# a "loop0 loop1" (dos palabras) → encaja en 'for dev in'.
declare -A NODE_DISKS=(
    [node1]="loop0 loop1"
    [node2]="loop2 loop3"
    [node3]="loop4 loop5"
)

# ---------- auxiliares ----------
# _node_up: true si el contenedor existe Y está corriendo.
# -f '{{.State.Running}}' imprime exactamente true/false
# (sin él, un error de docker llegaría al grep); el
# 2>/dev/null oculta el "No such object" de un lab ya
# destruido.
_node_up() {
    docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null \
        | grep -q true
}

# _dev_in_node: ¿existe /dev/<loop> como dispositivo de
# BLOQUE dentro del nodo? -b (no -e): un fichero regular
# llamado loop0 sería un falso positivo.
_dev_in_node() {
    docker exec "$1" test -b "/dev/$2" 2>/dev/null
}

# _loop_on_host: ¿existe el loop en el HOST? /sys/block
# solo lista los dispositivos adjuntados al kernel: más
# barato y estable que parsear 'losetup -a'.
_loop_on_host() {
    [ -e "/sys/block/$1" ]
}

# _loop_wait: espera hasta 10 s a que el host tenga el loop
# adjuntado. POR QUÉ: en arranques fríos fake-disks.service
# (la unit de la imagen) crea/adjunta los loops de forma
# asíncrona; sin esta espera el wipe de un arranque fresh
# fallaría en silencio (el /dev/loopN estático del nodo
# pasa el test -b aunque no haya dispositivo real detrás).
# Devuelve el exit code de la última sonda (0 si apareció).
_loop_wait() {
    local dev="$1" i=0
    while [ $i -lt 10 ] && ! _loop_on_host "$dev"; do
        sleep 1
        i=$((i+1))
    done
    _loop_on_host "$dev"
}

# ---------- limpieza DM del lab ----------
# El registro de device-mapper vive en el kernel del HOST y
# los 3 nodos lo comparten. Los LV activos al hacer 'down'
# sobreviven a 'docker rm' y quedan como fantasmas: bloquean
# nombres de VG (EBUSY) y retienen los loops. Esta función
# los elimina en cada down/reset.
#
# SEGURIDAD (doble filtro; el host bootea de LVM rlm-*):
#   1. Solo nombres de DM que empiezan por 'vg_': las
#      tareas del pool crean sus VG con ese prefijo.
#   2. Solo si dependen de los loops del lab (major 7 =
#      loop, minor 0-5 = los seis del mapa fijo).
# JAMÁS dmsetup remove_all ni tocar rlm-*: eso mataría el
# disco raíz del host que ejecuta este laboratorio.
_lab_dm_release() {
    local d deps
    # Sin dmsetup instalado tampoco hay fantasmas LVM que
    # limpiar: salir con éxito en vez de romper el 'down'.
    command -v dmsetup >/dev/null 2>&1 || return 0
    for d in $(dmsetup ls 2>/dev/null | awk '{print $1}' \
                | grep -E '^vg_'); do
        # 'dmsetup deps' lista los major:minor de los que
        # depende el DM; nos quedamos solo con los que
        # cuelgan de NUESTROS loops. El '|| true' evita
        # que un DM que desaparezca a mitad de carrera
        # rompa la limpieza del resto.
        deps=$(dmsetup deps "$d" 2>/dev/null || true)
        echo "$deps" \
            | grep -qE '\(7, *(0|1|2|3|4|5)\)' || continue
        # Dos intentos: remove normal y --force para los
        # tercos (referencias pendientes de udev que aquí,
        # sin udev, jamás se aclaran solas).
        if dmsetup remove "$d" 2>/dev/null; then
            echo "  [OK] liberado DM $d"
        elif dmsetup remove --force "$d" 2>/dev/null; then
            echo "  [OK] liberado DM $d (--force)"
        else
            echo "  [!!] DM $d no liberado"
        fi
    done
    # Nunca falla el 'down': un DM resistente no debe dejar
    # el lab a medias. lab_doctor lo reportará luego.
    return 0
}

# ---------- filtro LVM por nodo ----------
# Genera /etc/lvm/lvmlocal.conf en el nodo con DOS cosas a
# la vez:
#   1. Anti-udev de la imagen: en un contenedor no hay
#      daemon udev. Sin udev_sync=0 / udev_rules=0 /
#      obtain_device_list_from_udev=0, lvcreate aborta con
#      "not found: device not cleared".
#   2. Filtro por nodo: LVM solo escanea SUS dos loops.
#      Kernel compartido → sin filtro node1 "vería" la VG
#      de node2 y las correcciones darían falsos OK entre
#      nodos. Con global_filter los discos ajenos ni
#      siquiera aparecen en un pvs.
# El conf se escribe COMPLETO (no es un parche): así el
# resultado final no depende de lo que trajera la imagen.
_lab_lvm_filter() {
    local node="$1" re="" dev tmp
    # Monta la alternancia de la regex: "0|1". ${dev#loop}
    # arranca el prefijo "loop" y deja el minor del disp.
    for dev in ${NODE_DISKS[$node]}; do
        re+="${dev#loop}|"
    done
    re="${re%|}"
    # El conf se redacta en /tmp del host y se copia con
    # docker cp (hacer exec con heredoc contra el nodo es
    # poco fiable para contenido multilínea).
    tmp="/tmp/lvmlocal.$node.conf"
    # ------------------------------------------------------------
    # SIGNIFICADO del conf (línea a línea):
    #   obtain_device_list_from_udev=0 ... sin udev en el
    #     contenedor, LVM escanea /dev directamente en
    #     lugar de fiarse de los eventos de udev.
    #   use_devicesfile=0 ... el devices file de lvm2 >=2.03
    #     "fijaría" descubrimientos previos: desactivado,
    #     solo manda el filtro.
    #   filter=[...] ... acepta SOLO: mis dos loops (${re}
    #     = "0|1"), /dev/md (tareas RAID) y /dev/mapper/
    #     luks-* (volúmenes LUKS abiertos por las tareas).
    #     El r[.*] final RECHAZA todo lo demás: los loops
    #     de los otros nodos y los rlm-* del host ni entran
    #     en el escaneo.
    #   global_filter ... el mismo filtro también para el
    #     escaneo inicial (pvs/vgs): lo ajeno ni se candidacy.
    #   \$ llega al conf como $ (heredoc SIN comillas): es
    #     el ancla de fin de nombre — sin ella, "loop0"
    #     también matchearía a "loop01".
    #   use_lvmetad=0 ... lvmetad no existe en el pod: evita
    #     avisos del lvm2 moderno.
    #   udev_sync/udev_rules=0 ... el udev del nodo nunca
    #     responde; sin esto lvcreate se queda esperando
    #     confirmaciones y aborta.
    # ------------------------------------------------------------
    cat > "$tmp" <<EOF
# ==========================================
#  RHCE LAB - Override LVM local (por nodo)
#  = anti-udev del original de la imagen +
#    filtro que aísla los discos DE CADA nodo
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
    # lvmlocal.conf es el override de lvm.conf que SOLO
    # afecta a este nodo. mkdir -p lo hace idempotente
    # contra un nodo recién recreado por compose.
    docker exec "$node" mkdir -p /etc/lvm 2>/dev/null
    docker cp "$tmp" "$node:/etc/lvm/lvmlocal.conf" 2>/dev/null
    rm -f "$tmp"
}

# ---------- wipe por nodo ----------
# Deja cada disco como NUEVO: wipefs -a borra las firmas
# que reconoce (filesystem, tabla de particiones, LVM,
# LUKS, RAID...). El alumno encuentra el /dev/loopX
# prístino, exactamente como asume el enunciado.
# 3 intentos con 1 s de margen: en arranque fresh el loop
# a veces está todavía asentándose tras el attach.
# Solo corre si existe FRESH_MARKER (lo guarda su único
# llamador) → jamás wypea un examen en progreso.
_lab_wipe_node() {
    local node="$1" dev try
    for dev in ${NODE_DISKS[$node]}; do
        for try in 1 2 3; do
            if docker exec "$node" wipefs -a "/dev/$dev" \
                >/dev/null 2>&1; then
                echo "  [OK] $node: /dev/$dev pristino"
                break
            fi
            sleep 1
        done
    done
}

# ============================================================
# lab_disks_finalize — la llama _finalize_startup
# (docker.sh) en cada 'up'/'reset'. Por cada nodo arrancado:
#   1. espera a que sus loops existan en el host,
#   2. si el nodo no ve un /dev/loopX, lo repara: adjunta
#      el .img (losetup) y crea el nodo de dispositivo
#      dentro del contenedor (mknod),
#   3. instala el filtro LVM del nodo,
#   4. si el arranque es fresh (marcador), wypea los discos.
# IDEMPOTENTE: puede correr dos veces seguidas sin romper
# nada; lo destructivo está guardado tras el marcador, y
# el marcador se consume al final (one-shot).
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
            # La imagen de ESTE disco: persiste entre boots
            # (/var/lib/rhce-lab/disks/node1-loop0.img).
            img="$DISK_IMG_DIR/${node}-${dev}.img"
            # Espera al attach asíncrono del arranque frío;
            # si el loop no aparece, el || true deja que la
            # reparación de abajo intente adjuntarlo.
            _loop_wait "$dev" || true
            if ! _dev_in_node "$node" "$dev"; then
                # El nodo no ve el disco. Primero asegurar
                # de que el HOST lo tiene adjuntado.
                if ! _loop_on_host "$dev"; then
                    mkdir -p "$DISK_IMG_DIR"
                    # imagen sparse de 512M si no existe
                    [ -f "$img" ] \
                      || truncate -s "$DISK_SIZE" "$img"
                    # carga el módulo loop (MV minimizada)
                    modprobe loop 2>/dev/null || true
                    # adjunta al loop FIJO del mapa; si
                    # está ocupado, primero libre disponible
                    # como salida de emergencia (lab_doctor lo
                    # reportará como desviación del mapa)
                    losetup "/dev/$dev" "$img" 2>/dev/null \
                        || losetup -f "$img" >/dev/null 2>&1
                fi
                # Segunda mitad de la reparación: crear el
                # nodo /dev/loopX DENTRO del contenedor.
                # major 7 = loops; minor = ${dev#loop}.
                # El \ dentro de las comillas une las dos
                # líneas en un solo argumento para bash -c.
                docker exec "$node" bash -c \
                  "[ -b /dev/$dev ] || \
                   mknod /dev/$dev b 7 ${dev#loop}" \
                  >/dev/null 2>&1
            fi
            # Doble confirmación: el nodo ve el disco Y el
            # host tiene el loop. Solo entonces [OK]: un
            # mknod sin loop detrás pasa el test -b pero
            # fallaría en la primera tarea LVM.
            if _dev_in_node "$node" "$dev" \
               && _loop_on_host "$dev"; then
                echo "  [OK] $node <- /dev/$dev"
            else
                echo "  [!!] $node SIN /dev/$dev"
            fi
        done
        # El filtro se reinstala en cada arranque: es
        # barato y blinda el estado tras un compose que
        # recrea los nodos desde cero.
        _lab_lvm_filter "$node"
        echo "  [OK] $node filtro LVM aplicado"
        # El ÚNICO punto destructivo del fichero, y está
        # guardado tras el marcador de arranque fresh.
        if [ -f "$FRESH_MARKER" ]; then
            _lab_wipe_node "$node"
        fi
    done
    # El marcador se consume aunque algún nodo estuviera
    # caído: el trato es "solo up/reset deja los discos
    # prístinos", y un 'start' posterior NO wypea.
    rm -f "$FRESH_MARKER"
    echo "---------------------------------------------"
}

# ============================================================
# lab_disks_release — la llaman lab_down/reset (docker.sh),
# SIEMPRE con los contenedores aún vivos.
# Reglas de orden (críticas):
#   1. PRIMERO el device-mapper: un LV activo retiene el
#      loop y losetup -d se quedaría en EBUSY.
#   2. DESPUÉS los seis loops, por su nombre fijo.
# Sin esto los números derivan entre resets (el pool y los
# filtros hardcodean loop0/2/4 por nodo) y los DM fantasma
# bloquean los nombres de VG del próximo examen.
# ============================================================
lab_disks_release() {
    local dev
    _lab_dm_release
    for dev in loop0 loop1 loop2 loop3 loop4 loop5; do
        if _loop_on_host "$dev"; then
            # Si el -d falla (EBUSY) no se detiene el down:
            # lab_doctor señalará el loop sobrante en la
            # próxima revisión.
            losetup -d "/dev/$dev" 2>/dev/null \
              && echo "  [OK] liberado /dev/$dev"
        fi
    done
    return 0
}

# ============================================================
# lab_doctor — estado general del lab en ~10 s. Comprueba
# 6 cosas, en orden de importancia:
#   1. daemon de docker (si no responde, return 1: nada
#      de lo demás sería diagnóstico).
#   2. los 4 contenedores (control + 3 nodos).
#   3. discos: presentes en nodo Y host, con su fstype
#      (vacío = disco prístino, sin firmas).
#   4. filtro LVM presente en cada nodo.
#   5. DMs vg_* residuales en el kernel del host (restos
#      de un examen o de un 'down' antiguo).
#   6. SELinux del HOST: las tareas fcontext del pool se
#      aplican contra el kernel que los nodos comparten;
#      si está apagado, no pueden pasar.
# Uso: el formato [OK]/[!!] está pensado para pegar la
# salida tal cual en un issue de GitHub.
# ============================================================
lab_doctor() {
    local c node dev fs dms se
    echo "=== RHCE Lab :: doctor ====================="
    # 1) daemon
    if docker info >/dev/null 2>&1; then
        echo "[OK] docker daemon"
    else
        echo "[!!] docker daemon NO responde"
        return 1
    fi
    # 2) contenedores
    for c in control node1 node2 node3; do
        if _node_up "$c"; then
            echo "[OK] contenedor $c"
        else
            echo "[!!] contenedor $c parado"
        fi
    done
    # 3) discos por nodo (existencia + filesystem)
    for node in node1 node2 node3; do
        _node_up "$node" || continue
        for dev in ${NODE_DISKS[$node]}; do
            if _dev_in_node "$node" "$dev" \
               && _loop_on_host "$dev"; then
                # lsblk sin cabecera, sin particiones (-d),
                # solo la columna FSTYPE: xfs, ext4,
                # LVM2_member... o vacío si está prístino.
                fs=$(docker exec "$node" lsblk -ndo FSTYPE \
                     "/dev/$dev" 2>/dev/null)
                echo "[OK] $node /dev/$dev (fstype='${fs:-vacio}')"
            else
                echo "[!!] $node SIN /dev/$dev"
            fi
        done
        # 4) el filtro: grep busca global_filter como
        # prueba de que el conf generado está en su sitio
        if docker exec "$node" grep -q global_filter \
              /etc/lvm/lvmlocal.conf 2>/dev/null; then
            echo "[OK] $node filtro LVM presente"
        else
            echo "[!!] $node sin filtro LVM"
        fi
    done
    # 5) DMs fantasma: nombres vg_* aún registrados en el
    # host. El tr '\n' ' ' los junta en una sola línea.
    dms=$(dmsetup ls 2>/dev/null | awk '{print $1}' \
          | grep -E '^vg_' | tr '\n' ' ')
    if [ -n "$dms" ]; then
        echo "[!!] device-mapper residual: $dms"
        echo "     (limpialo con ./lab.sh reset)"
    else
        echo "[OK] device-mapper sin residuos vg_*"
    fi
    # 6) SELinux del host. Sin getenforce usamos la
    # heurística de /sys/fs/selinux: montado = al menos
    # permissive (las tareas fcontext aplican); ausente =
    # Disabled (no aplicables).
    se=$(getenforce 2>/dev/null \
         || { [ -d /sys/fs/selinux ] \
              && echo Permissive || echo Disabled; })
    if [ "$se" = "Disabled" ]; then
        echo "[!!] SELinux del host desactivado"
        echo "     (tareas fcontext del pool no aplicables)"
    else
        echo "[OK] SELinux del host: $se"
    fi
    echo "============================================"
}

# ============================================================
# lab_autostart — instala rhce-lab.service para que el lab
# se levante solo al arrancar la MV.
# POR QUÉ systemd (y no un cron @reboot): Type=oneshot +
# RemainAfterExit=yes modela "arráncalo una vez y mantén la
# unit como activa", lo que permite emparejar ExecStop con
# un 'systemctl stop rhce-lab' limpio. After/Wants garantizan
# que docker ya existe cuando corre el 'up' (si no, el
# arranque intentaría crear contenedores con la red a medias).
# La unit apunta al directorio ACTUAL del repo (readlink -f
# resuelve symlinks: sobrevive a mover la carpeta sin dejar
# rutas huérfanas).
# ============================================================
lab_autostart() {
    local dir unit
    # Ruta del repo a partir de ESTE fichero:
    # readlink -f .../core/disks.sh → ruta real,
    # dirname → .../core, y /.. sube a la raíz del repo.
    dir=$(cd "$(dirname "$(readlink -f \
          "${BASH_SOURCE[0]}")")/.." && pwd)
    unit=/etc/systemd/system/rhce-lab.service
    # ------------------------------------------------------------
    # SIGNIFICADO de la unit:
    #   After=docker.service ... el 'up' corre cuando el
    #     daemon ya está (lab.sh lo necesita para todo).
    #   Wants=network-online ... pedir red es best-effort:
    #     se desea, pero no es requisito duro de arranque.
    #   Type=oneshot ... ExecStart corre una vez y termina
    #     (no es un demonio).
    #   RemainAfterExit=yes ... systemd mantiene la unit
    #     "active" tras el exit: así existe el ExecStop.
    #   ExecStart/ExecStop ... up al arrancar, stop al
    #     apagar (apagado ordenado del lab).
    #   WantedBy=multi-user.target ... el runlevel
    #     estándar, junto al resto de servicios.
    # ------------------------------------------------------------
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
    # Sin daemon-reload systemd no vería la unit nueva
    # hasta el siguiente booteo.
    systemctl daemon-reload
    # enable la deja armada para el PRÓXIMO arranque; el
    # >/dev/null silencia el "Created symlink".
    systemctl enable rhce-lab.service >/dev/null 2>&1
    echo "[OK] autoarranque instalado: rhce-lab.service"
    echo "     La proxima vez que arranques la MV, el lab"
    echo "     se levanta solo (tras docker.service)."
    echo "     Para quitarlo: systemctl disable rhce-lab"
}
