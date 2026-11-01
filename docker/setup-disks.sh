#!/bin/bash
# ============================================================
#  DOCKER/SETUP-DISKS.SH — attach idempotente por nodo
#  v1.12.4-r3 (C-A del dictamen + revisiones de ChatGPT):
#  el NODO nunca destruye y SOLO adjunta lo verificablemente
#  libre.
# ------------------------------------------------------------
#  Correcciones r3 (dictamen NO-GO de la r2):
#   A) clasifica(): la lectura de sysfs se comprueba de
#      verdad (resultado Y contenido). Atributo ausente
#      cuando debería estar, ilegible o vacío -> 7; fuentes
#      que discrepan -> 7. LIBRE exige el acuerdo de DOS
#      fuentes: sin línea en losetup -a Y sin dir loop/ en
#      sysfs.  H1 (hallazgo propio r3): la r2 devolvía 7
#      para el loop registrado y SIN adjuntar (el dir loop/,
#      igual que backing_file, solo existe con binding
#      activo; lo confirma v1.12.3 en la MV), lo que
#      rompería el primer attach. Ahora ese caso es 1.
#   B) use_devicesfile=0: se exige la directiva EFECTIVA
#      dentro de devices{} (sin comentarios y en su
#      bloque); una coincidencia textual suelta no vale.
#   C) imagen que no mide 1G: NO se adjunta (se conserva el
#      rc 6 y "LVM Ready" no se anuncia).
#  Correcciones r2 sobre la r1:
#   B) LIBRE solo con el loop confirmado libre; si el estado
#      no se puede verificar (sysfs ausente, fuentes que
#      discrepan, loop "lost") -> 7 NO VERIFICABLE: se
#      aborta, jamás se trata como libre.
#   C) GHOST (misma ruta, inodo retenido distinto) y CONFLICT
#      (otra ruta) se distinguen en la clasificación (3 y 4).
#   D) tras cada attach se re-clasifica; si el binding no
#      corresponde a la imagen esperada -> fallo y sin "LVM
#      Ready" (cierra la carrera clasificar->adjuntar).
#   E) imagen de tamaño != 1G eleva rc y bloquea "LVM Ready".
#   F) use_devicesfile=0 se verifica después del sed.
#  El inodo retenido sale del KERNEL (lo_inode del
#  LOOP_GET_STATUS64; losetup -a lo imprime como
#  "dev: [hexdev]:inodo (ruta)") y se CRUZA con sysfs
#  backing_file; si las fuentes discrepan -> 7.
#  El borrado fresh vive SOLO en el anfitrión (FRESH_MARKER,
#  _lab_wipe_node en core/disks.sh). down/up da discos nuevos
#  por construcción (las .img viven en la capa del contenedor);
#  restart/start conserva los datos del alumno (G01/G02).
#  Códigos: 0 OK · 1 LIBRE confirmado (uso interno) · 3 GHOST
#  · 4 CONFLICT · 5 fallo operativo · 6 tamaño incorrecto ·
#  7 NO VERIFICABLE. 3/4/7 exigen decisión manual: nunca se
#  desadjunta ni se sobrescribe nada.
#  Ganchos de test: SYS_BLOCK, LOSETUP, DISK_DIR y LVM_CONF
#  solo se sobreescriben en pruebas unitarias; en la MV
#  valen los por defecto.
#  SIN set -e a propósito: los códigos los gobierna la
#  clasificación, no el primer comando que falle.
# ============================================================

SYS_BLOCK="${SYS_BLOCK:-/sys/block}"
LOSETUP="${LOSETUP:-losetup}"

DISK_DIR="${DISK_DIR:-/opt/lvm_disks}"
LVM_CONF="${LVM_CONF:-/etc/lvm/lvm.conf}"
mkdir -p "$DISK_DIR"

# identidad: hostname o IP fija (igual que v1.12.3)
SELF_IP=$(python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.connect(("172.20.0.10",1)); print(s.getsockname()[0])' 2>/dev/null || true)
case "${HOSTNAME} ${SELF_IP}" in
    *node1*|*172.20.0.11*) L0=0; L1=1 ;;
    *node2*|*172.20.0.12*) L0=2; L1=3 ;;
    *node3*|*172.20.0.13*) L0=4; L1=5 ;;
    *) echo "fake-disk: '${HOSTNAME}' no lleva discos (skip)"; exit 0 ;;
esac
D0=/dev/loop$L0; D1=/dev/loop$L1
I0="$DISK_DIR/disk1.img"; I1="$DISK_DIR/disk2.img"
echo "fake-disk: ${HOSTNAME} -> $D0 $D1"

# nodos loop: crear si faltan (EL10 no los trae)
[ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237
[ -b "$D0" ] || mknod "$D0" b 7 "$L0"
[ -b "$D1" ] || mknod "$D1" b 7 "$L1"

# nota <código>: guarda el peor código de salida. Los estados
# que exigen decisión manual (3/4/7) prevalecen sobre los
# fallos operativos (5/6); el primer fallo operativo manda.
rc=0
nota() {
    [ "$1" -eq 0 ] && return 0
    case "$rc" in 3|4|7) return 0 ;; esac
    case "$1" in 3|4|7) rc=$1; return 0 ;; esac
    [ "$rc" -eq 0 ] && rc=$1
    return 0
}

# imagenes 1G: crear si faltan; si una existente no mide 1G,
# AVISO + código 6 + bandera: NO se adjunta (C-r3); jamás se
# redimensiona ni se toca
prepara_img() {   # $1=imagen  $2=nombre de la variable-bandera
    if [ ! -f "$1" ]; then
        truncate -s 1G "$1"
        return 0
    fi
    local sz
    sz=$(stat -c '%s' "$1")
    if [ "$sz" -eq 1073741824 ]; then
        return 0
    fi
    echo "fake-disk: AVISO: $1 mide $sz bytes (esperado 1073741824); no se toca ni se adjunta" >&2
    printf -v "$2" 1
    nota 6
    return 0
}
MAL0=0; MAL1=0
prepara_img "$I0" MAL0
prepara_img "$I1" MAL1

udevadm settle --timeout=3 2>/dev/null || true

registra_loops() {
    # registra loop0-7 en el kernel si faltan (privileged)
    python3 - <<'PYEOF' 2>/dev/null || true
import fcntl, os
fd = os.open('/dev/loop-control', os.O_RDWR)
for j in range(8):
    try: fcntl.ioctl(fd, 0x4C80, j)
    except OSError: pass
PYEOF
}

# clasifica $1=/dev/loopN contra la imagen esperada $2
#   0=OK (misma ruta y mismo inodo retenido)  1=LIBRE confirmado
#   3=GHOST (misma ruta, otro inodo)  4=CONFLICT (otra ruta)
#   6=imagen ausente  7=NO VERIFICABLE (jamás se trata como libre)
# r3 (A): LIBRE exige el acuerdo de DOS fuentes (losetup -a
# sin línea Y sin dir loop/ en sysfs); con binding declarado,
# la lectura de backing_file se comprueba de verdad
# (resultado y contenido): ausente/ilegible/vacío -> 7.
clasifica() {
    local l="$1" img="$2" want la line bp held ruta bpf
    [ -e "$img" ] || return 6
    want=$(stat -c '%i' "$img" 2>/dev/null) || return 6
    [ -d "$SYS_BLOCK" ] || return 7
    if [ ! -d "$SYS_BLOCK/${l#/dev/}" ]; then
        return 1      # el kernel no conoce el dispositivo: libre definitivo
    fi
    bpf="$SYS_BLOCK/${l#/dev/}/loop/backing_file"
    la=$("$LOSETUP" -a 2>/dev/null) || return 7
    line=$(printf '%s\n' "$la" | awk -v d="$l:" '$1 == d')
    if [ -n "$line" ]; then
        # binding declarado: sysfs DEBE corroborarlo de verdad
        [ -e "$bpf" ] || return 7    # attr ausente cuando debe estar: 7
        bp=$(cat "$bpf" 2>/dev/null) || bp=""
        [ -n "$bp" ] || return 7     # attr ilegible o vacío: 7
        held=$(printf '%s\n' "$line" | sed -n 's/^[^ ]*: \[[^]]*\]:\([0-9]*\).*/\1/p')
        ruta=$(printf '%s\n' "$line" | sed -n 's/^[^ ]*: \[[^]]*\]:[0-9]* (\(.*\))$/\1/p')
        { [ -n "$held" ] && [ -n "$ruta" ]; } || return 7
        [ "$bp" = "$ruta" ] || return 7   # fuentes discrepan: 7
        [ "$ruta" != "$img" ] && return 4   # CONFLICT: otra ruta
        [ "$held" = "$want" ] && return 0   # OK: mismo inodo retenido
        return 3                            # GHOST: misma ruta, otro inodo
    fi
    # losetup no lo lista: LIBRE solo si sysfs confirma sin binding
    [ -e "$bpf" ] && return 7        # attr de backing presente: discrepancia
    [ -d "$SYS_BLOCK/${l#/dev/}/loop" ] && return 7
    return 1                         # dos fuentes sin binding: LIBRE confirmado
}

# diagnóstico del conflicto (sin acciones destructivas)
reporta_conflicto() {
    local l="$1" img="$2" st="$3" bp wi held
    bp=$(cat "$SYS_BLOCK/${l#/dev/}/loop/backing_file" 2>/dev/null)
    wi=$(stat -c '%i' "$img" 2>/dev/null)
    held=$("$LOSETUP" -a 2>/dev/null | awk -v d="$l:" '$1 == d' \
           | sed -n 's/^[^ ]*: \[[^]]*\]:\([0-9]*\).*/\1/p')
    echo "fake-disk: CONFLICTO en $l (código $st):" >&2
    case "$st" in
        3) echo "  tipo: GHOST — misma ruta, inodo retenido distinto" >&2 ;;
        4) echo "  tipo: CONFLICT — asociado a otro fichero" >&2 ;;
        *) echo "  tipo: NO VERIFICABLE — estado inconsistente o ilegible" >&2 ;;
    esac
    echo "  esperado: $img (inodo actual ${wi:-?})" >&2
    echo "  sysfs backing : ${bp:-<vacío o ilegible>}" >&2
    echo "  inodo retenido: ${held:-<no disponible>}" >&2
    echo "  holders:" >&2
    lsblk -no MAJ:MIN,NAME,HOLDERS "$l" 2>/dev/null | sed 's/^/    /' >&2
    echo "  NO se desadjunta ni se sobrescribe automáticamente." >&2
    echo "  Runbook: docs/auditoria (RB-1); no sacrificar LV activo." >&2
}

for par in "$D0:$I0:MAL0" "$D1:$I1:MAL1"; do
    l=${par%%:*}; r=${par#*:}; img=${r%%:*}; flag=${r##*:}
    if [ "${!flag}" = 1 ]; then
        echo "fake-disk: [..] $l: NO se adjunta: $img incumple el contrato de tamaño" >&2
        nota 6
        continue
    fi
    clasifica "$l" "$img"; st=$?
    case $st in
        0) echo "fake-disk: $l OK ($img) — sin cambios" ;;
        1) registra_loops
           if losetup "$l" "$img" 2>/dev/null; then
               clasifica "$l" "$img"; vst=$?
               if [ "$vst" -eq 0 ]; then
                   echo "fake-disk: adjuntado y verificado $l -> $img"
               else
                   echo "fake-disk: [!!] attach NO verificado en $l (clasifica=$vst)" >&2
                   nota 5
               fi
           elif losetup "$l" "$img"; then
               clasifica "$l" "$img"; vst=$?
               if [ "$vst" -eq 0 ]; then
                   echo "fake-disk: adjuntado y verificado $l -> $img (2do intento)"
               else
                   echo "fake-disk: [!!] attach NO verificado en $l (clasifica=$vst)" >&2
                   nota 5
               fi
           else
               echo "fake-disk: ERROR adjuntando $l" >&2
               nota 5
           fi ;;
        3|4) reporta_conflicto "$l" "$img" "$st"; nota "$st" ;;
        6) echo "fake-disk: [!!] $img ausente: imposible verificar" >&2; nota 6 ;;
        *) reporta_conflicto "$l" "$img" 7; nota 7 ;;
    esac
done

# verificación honesta: ambos discos con su 1G real
for l in "$D0" "$D1"; do
    sz=$(blockdev --getsize64 "$l" 2>/dev/null || echo 0)
    if [ "$sz" -ne 1073741824 ]; then
        echo "fake-disk: $l sin 1G real (size=$sz)" >&2
        nota 6
    fi
done

# precondición LVM (B-r3): la directiva EFECTIVA dentro de
# devices{} — no vale una coincidencia textual comentada o
# fuera de bloque; se comprueba antes y después de editar.
udf_ok() {
    local cf="${LVM_CONF:-/etc/lvm/lvm.conf}"
    [ -f "$cf" ] || return 1
    awk '
        /^[[:space:]]*devices[[:space:]]*\{/ {dev=1; next}
        dev && /^[[:space:]]*[[:alnum:]_]+[[:space:]]*\{/ {exit}
        dev {
            sub(/[[:space:]]*#.*/, "")
            if ($0 ~ /^[[:space:]]*use_devicesfile[[:space:]]*=[[:space:]]*0[[:space:]]*$/) {print "OK"; exit}
        }
    ' "$cf" 2>/dev/null | grep -qx OK
}
if ! udf_ok; then
    sed -i '/^[[:space:]]*devices[[:space:]]*[{]/a\    use_devicesfile = 0' \
        "${LVM_CONF:-/etc/lvm/lvm.conf}" 2>/dev/null
    udf_ok || { echo "fake-disk: [!!] no pude asegurar use_devicesfile=0 (efectiva en devices{})" >&2; nota 5; }
fi

if [ "$rc" -eq 0 ]; then
    echo "LVM Ready: ${HOSTNAME} -> $D0 $D1 (attach idempotente v1.12.4-r3)"
else
    echo "fake-disk: salida con código $rc; SIN 'LVM Ready'" >&2
fi
exit $rc
