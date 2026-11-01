#!/bin/bash
# ============================================================
#  tests/pruebas_r3.sh — pruebas unitarias v1.12.4-r3
#  Arnés bajo set -euo pipefail (como lab.sh): cualquier
#  sustitución de comando sin proteger aborta el arnés.
#  Cubre el dictamen NO-GO de la r2 con CASOS DE ERROR DE
#  CONSULTA (no solo salida vacía):
#   S1 clasifica: lectura de sysfs explícita   (punto 1.A)
#   S2 prepara_img: imagen mala no se adjunta  (punto 1.C)
#   S3 udf_ok: directiva efectiva en devices{} (punto 1.B)
#   S4 setup_docker_dns: restart propagado     (punto 2.A)
#   S5 _lab_compose_ps: tres estados           (punto 2.B)
#   S6 lab_down: no liberar con consulta caída (punto 2.B/C)
#   S7 _lab_nodes_lvm_off: vgs caído != sin VG (punto 2.C)
#   S8 _lab_dm_release: ls/deps caídos         (punto 2.E)
#   S9 doctor: systemctl/vgs caídos visibles   (punto 2.D)
#   S10 regresiones r2 (ipv4, dns atómico, montajes,
#       wipe, losetup -d, compose down fallido)
#  Uso (desde la raíz del repo): bash tests/pruebas_r3.sh
#  Los stubs son FUNCIONES del propio proceso: no tocan
#  docker, dmsetup, loops ni imágenes reales de la MV.
# ============================================================
set -euo pipefail

REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SD="${SD:-$REPO/docker/setup-disks.sh}"
V1124="${V1124:-$REPO/core/v1124.sh}"

FT=$(mktemp -d /tmp/pruebas_r3.XXXXXX)
trap 'rm -rf "$FT"' EXIT
CFG="$FT/cfg"; mkdir -p "$CFG" "$FT/docker"
export CFG
FRESH_FAIL_FLAG="$FT/fresh-FAILED"
DOCKER_DIR="$FT/docker"
export SYS_BLOCK="$FT/sys" LOSETUP="$FT/losetup-stub" LVM_CONF="$FT/lvm.conf"
mkdir -p "$SYS_BLOCK"

echo "== sellos de los ficheros bajo prueba =="
md5sum "$SD" "$V1124"

RED=; GREEN=; YELLOW=; NC=
rc=0                       # global que usa nota() del script real
FAIL=0; P=0; LAST_OUT=""
chk() { if [ "${2:-}" = "${3:-}" ]; then P=$((P+1)); echo "PASS  $1 (=$3)"; else echo "FAIL  $1 esperado=$2 obtenido=${3:-<vacío>}"; FAIL=1; fi; }
okfail() { if echo "${1:-}" | grep -q "$2"; then P=$((P+1)); echo "PASS  $3"; else echo "FAIL  $3 (no se vio: $2)"; FAIL=1; fi; }
nofail() { if echo "${1:-}" | grep -q "$2"; then echo "FAIL  $3 (apareció: $2)"; FAIL=1; else P=$((P+1)); echo "PASS  $3"; fi; }

# ---------- stubs (funciones del proceso; estado en $CFG) ----------
DOCKER_LOG="$FT/docker.log"; : > "$DOCKER_LOG"
_node_up() { [ -f "$CFG/down_$1" ] && return 1 || return 0; }
_loop_on_host() { [ -f "$CFG/attached_$1" ]; }
declare -A NODE_DISKS=( [node1]="loop0 loop1" [node2]="loop2 loop3" [node3]="loop4 loop5" )
lab_doctor() { echo "BASE-DOCTOR-LLAMADO"; return 0; }
systemctl() { echo "systemctl $*" >> "$DOCKER_LOG"
    [ -f "$CFG/restart_fail" ] && { echo "job for docker.service failed" >&2; return 1; }
    return 0; }
sudo() { "$@"; }   # en la MV se corre como root
losetup() { echo "losetup $*" >> "$DOCKER_LOG"
    case "$1" in
        -d) [ -f "$CFG/detach_fail" ] && return 1 || return 0 ;;
    esac; return 0; }
dmsetup() { echo "dmsetup $*" >> "$DOCKER_LOG"
    case "$1" in
        ls) [ -f "$CFG/dm_ls_fail" ] && { echo "dmsetup: sim-fail" >&2; return 1; }
            [ -f "$CFG/dms" ] && cat "$CFG/dms"
            return 0 ;;
        deps) [ -f "$CFG/dm_deps_fail" ] && { echo "dmsetup deps: sim-fail" >&2; return 1; }
            [ -f "$CFG/dep_$2" ] && cat "$CFG/dep_$2"
            return 0 ;;
        remove) [ -f "$CFG/dm_busy" ] && return 1
            [ -f "$CFG/dms" ] && sed -i "/^$2/d" "$CFG/dms" 2>/dev/null
            return 0 ;;
    esac; return 0; }
docker() { echo "docker $*" >> "$DOCKER_LOG"
    case "$1" in
        compose) case "$2" in
            ps) local n; n=$(( $(cat "$CFG/ps_n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CFG/ps_n"
                if [ -f "$CFG/ps_fail" ] && [ "$n" -ge "$(cat "$CFG/ps_fail_at" 2>/dev/null || echo 1)" ]; then
                    echo "compose: sim-caido" >&2; return 1
                fi
                [ -f "$CFG/containers" ] && cat "$CFG/containers"
                return 0 ;;
            down) [ -f "$CFG/compose_fail" ] && return 1
                  [ -f "$CFG/compose_keep" ] || rm -f "$CFG/containers"
                  return 0 ;;
        esac; return 0 ;;
        exec)
            local node="$2"; shift 2
            case "$1" in
                awk) [ -f "$CFG/mounts_$node" ] && cat "$CFG/mounts_$node" || true; return 0 ;;
                umount) echo "  umount-ok $*"; return 0 ;;
                vgs) if [ "${2:-}" = "--noheadings" ]; then
                        [ -f "$CFG/vgs_all_fail" ] && { echo "vgs: sim-fail" >&2; return 1; }
                        [ -f "$CFG/vgs_all" ] && cat "$CFG/vgs_all"
                        return 0
                     fi
                     [ -f "$CFG/vgs_fail" ] && { echo "vgs: sim-fail" >&2; return 1; }
                     [ -f "$CFG/novg_$node" ] && return 1 || return 0 ;;
                vgchange) echo "0 logical volume(s) now active"; return 0 ;;
                wipefs) if [ "${2:-}" = "-a" ]; then
                            [ -f "$CFG/wipe_fail" ] && return 1 || return 0
                        else
                            [ -f "$CFG/wipe_qfail" ] && return 3 \
                                || { [ -f "$CFG/wipe_sig" ] && cat "$CFG/wipe_sig"; return 0; }
                        fi ;;
                systemctl) [ -f "$CFG/systemctl_fail" ] && { echo "systemctl: sim-fail" >&2; return 1; }
                    [ -f "$CFG/units" ] && cat "$CFG/units"
                    return 0 ;;
                lvs) [ -f "$CFG/lvs_fail_$node" ] && return 1 \
                        || { [ -f "$CFG/lvs_$node" ] && cat "$CFG/lvs_$node"; return 0; } ;;
                *) return 0 ;;
            esac ;;
        *) return 0 ;;
    esac; }
# stub de losetup -a como FICHERO (lo invoca clasifica vía $LOSETUP)
cat > "$FT/losetup-stub" <<'EOF'
#!/bin/bash
case "$1" in
    -a) [ -f "${CFG:?}/lo_fail" ] && { echo "losetup: sim-fail" >&2; exit 1; }
        [ -f "${CFG:?}/lo_out" ] && cat "${CFG:?}/lo_out"
        exit 0 ;;
esac
exit 0
EOF
chmod +x "$FT/losetup-stub"

# ---------- carga de los ficheros REALES ----------
[ -f "$SD" ] || { echo "no encuentro $SD"; exit 1; }
[ -f "$V1124" ] || { echo "no encuentro $V1124"; exit 1; }
for fn in nota prepara_img clasifica udf_ok; do
    sed -n "/^${fn}()/,/^}/p" "$SD" > "$FT/${fn}.f"
    [ -s "$FT/${fn}.f" ] || { echo "no pude extraer $fn de $SD"; exit 1; }
    # shellcheck disable=SC1090
    source "$FT/${fn}.f"
done
# shellcheck disable=SC1090
source "$V1124"
echo "== ficheros reales cargados bajo set -euo pipefail =="

# ============================================================
echo "== S1) clasifica: lectura de sysfs explícita (punto 1.A) =="
IMG="$FT/disk1.img"; truncate -s 1M "$IMG"
WANT=$(stat -c '%i' "$IMG")
LOOP=/dev/loop0
SB="$SYS_BLOCK"
cl() { local rc=0; clasifica "$LOOP" "$IMG" || rc=$?; echo "$rc"; }
rm -rf "$SB/loop0"; : > "$CFG/lo_out"
chk "1.1 dispositivo ausente en sysfs -> 1" 1 "$(cl)"
mkdir -p "$SB/loop0"
chk "1.2 registrado SIN adjuntar (sin dir loop/) -> 1 [H1]" 1 "$(cl)"
mkdir -p "$SB/loop0/loop"
chk "1.3 losetup callado pero dir loop/ presente -> 7" 7 "$(cl)"
echo "$IMG" > "$SB/loop0/loop/backing_file"
echo "$LOOP: [0042]:$WANT ($IMG)" > "$CFG/lo_out"
chk "1.4 OK: misma ruta y mismo inodo -> 0" 0 "$(cl)"
echo "$LOOP: [0042]:999999 ($IMG)" > "$CFG/lo_out"
chk "1.5 GHOST: misma ruta, otro inodo -> 3" 3 "$(cl)"
echo "$LOOP: [0042]:$WANT (/otra/ruta.img)" > "$CFG/lo_out"
echo "/otra/ruta.img" > "$SB/loop0/loop/backing_file"
chk "1.6 CONFLICT: otra ruta (fuentes coherentes) -> 4" 4 "$(cl)"
echo "$IMG" > "$SB/loop0/loop/backing_file"
echo "$LOOP: [0042]:$WANT ($IMG)" > "$CFG/lo_out"
chk "1.7 OK de nuevo tras restaurar -> 0" 0 "$(cl)"
rm -f "$SB/loop0/loop/backing_file"
chk "1.8 binding declarado, attr ausente -> 7" 7 "$(cl)"
mkdir -p "$SB/loop0/loop/backing_file"
chk "1.9 attr ILEGIBLE (cat falla) -> 7" 7 "$(cl)"
rmdir "$SB/loop0/loop/backing_file"
: > "$SB/loop0/loop/backing_file"
chk "1.10 attr VACÍO con binding declarado -> 7" 7 "$(cl)"
echo "/otra/cosa.img" > "$SB/loop0/loop/backing_file"
chk "1.11 sysfs y losetup discrepan -> 7" 7 "$(cl)"
echo "$IMG" > "$SB/loop0/loop/backing_file"
touch "$CFG/lo_fail"
chk "1.12 losetup -a FALLA -> 7" 7 "$(cl)"
rm -f "$CFG/lo_fail"
c6() { local rc=0; clasifica "$LOOP" "$FT/noexiste.img" || rc=$?; echo "$rc"; }
chk "1.13 imagen ausente -> 6" 6 "$(c6)"
rm -rf "$SB/loop0"

# ============================================================
echo "== S2) prepara_img: imagen mala NO se adjunta (punto 1.C) =="
FLAG_T=0; rm -f "$FT/img2.img"
prepara_img "$FT/img2.img" FLAG_T
chk "2.1 imagen ausente -> se crea de 1G" 1073741824 "$(stat -c '%s' "$FT/img2.img")"
chk "2.2 creada correcta -> bandera sigue a 0" 0 "$FLAG_T"
printf 'x' > "$FT/img3.img"; FLAG_T=0
prepara_img "$FT/img3.img" FLAG_T
chk "2.3 tamaño 1 byte -> bandera a 1 (no se adjuntará)" 1 "$FLAG_T"

# ============================================================
echo "== S3) udf_ok: directiva EFECTIVA en devices{} (punto 1.B) =="
cat > "$LVM_CONF" <<'EOF'
devices {
    # use_devicesfile = 0   <- comentada: NO vale
    dir = "/dev"
}
EOF
chk "3.1 solo comentada en devices -> no ok" 1 "$(udf_ok && echo 0 || echo 1)"
cat > "$LVM_CONF" <<'EOF'
devices {
    dir = "/dev"
}

log {
    use_devicesfile = 0
}
EOF
chk "3.2 directiva real FUERA de devices -> no ok" 1 "$(udf_ok && echo 0 || echo 1)"
cat > "$LVM_CONF" <<'EOF'
devices {
    dir = "/dev"
    use_devicesfile = 0
}
EOF
chk "3.3 efectiva dentro de devices -> ok" 0 "$(udf_ok && echo 0 || echo 1)"
cat > "$LVM_CONF" <<'EOF'
devices {
    dir = "/dev"
}
EOF
sed -i '/^[[:space:]]*devices[[:space:]]*[{]/a\    use_devicesfile = 0' "$LVM_CONF"
chk "3.4 tras el sed del script -> ok" 0 "$(udf_ok && echo 0 || echo 1)"
( LVM_CONF="$FT/nohay.conf" udf_ok ) && r=0 || r=$?
chk "3.5 fichero ausente -> no ok" 1 "$r"

# ============================================================
echo "== S4) setup_docker_dns: reinicio propagado (punto 2.A) =="
D="$CFG/daemon.json"
printf '{"registry-mirrors":["https://mirror.local"],"log-level":"info"}\n' > "$D"
r=0; out=$(setup_docker_dns "8.8.8.8" "$D" 2>&1) || r=$?
chk "4.1 reinicio OK -> rc 0" 0 "$r"
grep -q '"dns": \[' "$D" && grep -q 'registry-mirrors' "$D" \
  && chk "4.2 escribe dns y conserva el resto" OK OK || chk "4.2 escribe dns" OK FAIL
touch "$CFG/restart_fail"
r=0; out=$(setup_docker_dns "9.9.9.9" "$D" 2>&1) || r=$?
rm -f "$CFG/restart_fail"
chk "4.3 restart docker FALLA -> rc 1 (antes devolvía 0)" 1 "$r"
okfail "$out" "NO está activa" "4.4 el fallo del reinicio se informa"
grep -q '9.9.9.9' "$D" && chk "4.5 el fichero sí se escribió" OK OK || chk "4.5 fichero" OK FAIL
printf '{roto' > "$D.bad"; before=$(cat "$D.bad")
r=0; setup_docker_dns "1.1.1.1" "$D.bad" >/dev/null 2>&1 || r=$?
chk "4.6 JSON inválido -> rc 1" 1 "$r"
chk "4.7 JSON inválido: fichero intacto" "$before" "$(cat "$D.bad")"

# ============================================================
echo "== S5) _lab_compose_ps: tres estados (punto 2.B) =="
rm -f "$CFG/ps_n" "$CFG/ps_fail" "$CFG/ps_fail_at"; : > "$CFG/containers"
r=0; _lab_compose_ps || r=$?
chk "5.1 consulta OK vacía -> rc 0 y 0 contenedores" "0:0" "$r:$_lab_vivos"
printf 'abc\ndef\n' > "$CFG/containers"
r=0; _lab_compose_ps || r=$?
chk "5.2 consulta OK con 2 IDs -> 2" "0:2" "$r:$_lab_vivos"
touch "$CFG/ps_fail"
r=0; _lab_compose_ps || r=$?
chk "5.3 consulta FALLIDA -> rc 1 (nunca 'sin contenedores')" "1:" "$r:$_lab_vivos"
rm -f "$CFG/ps_fail" "$CFG/containers"

# ============================================================
echo "== S6) lab_down: nunca liberar con consulta caída (punto 2.B/C) =="
RC_OUT=0
run_down() {
    local r=0
    : > "$DOCKER_LOG"; rm -f "$CFG/ps_n"
    out=$(lab_down 2>&1) || r=$?
    LAST_OUT="$out"; RC_OUT=$r
}
rm -f "$CFG/ps_fail" "$CFG/ps_fail_at" "$CFG/dms" "$CFG/compose_fail" "$CFG/compose_keep"
touch "$CFG/ps_fail"
run_down; chk "6.1 ps caído desde el inicio -> rc 1" 1 "$RC_OUT"
okfail "$LAST_OUT" "no se libera nada" "6.2 mensaje: no se libera nada"
if grep -q 'compose down' "$DOCKER_LOG"; then chk "6.3 sin compose down" "sin-down" "con-down"; else chk "6.3 sin compose down" "sin-down" "sin-down"; fi
rm -f "$CFG/ps_fail"
run_down; chk "6.4 sin contenedores y sin residuos -> rc 0 temprano" 0 "$RC_OUT"
okfail "$LAST_OUT" "ya está destruido" "6.5 salida temprana VERIFICADA (DM/loops)"
if grep -q 'compose down' "$DOCKER_LOG"; then chk "6.6 sin down innecesario" "sin-down" "con-down"; else chk "6.6 sin down innecesario" "sin-down" "sin-down"; fi
printf 'vg_datos\n' > "$CFG/dms"
printf '1 dependencies : (7, 0)\n' > "$CFG/dep_vg_datos"
run_down; chk "6.7 sin contenedores pero con DM residual -> limpia (rc 0)" 0 "$RC_OUT"
if grep -q 'dmsetup remove vg_datos' "$DOCKER_LOG"; then chk "6.8 DM residual liberado" OK OK; else chk "6.8 DM residual liberado" OK FAIL; fi
if grep -q 'compose down' "$DOCKER_LOG"; then chk "6.9 pasó por el flujo completo" OK OK; else chk "6.9 pasó por el flujo completo" OK FAIL; fi
rm -f "$CFG/dms" "$CFG/dep_vg_datos"
echo "abc" > "$CFG/containers"; touch "$CFG/ps_fail"; echo 2 > "$CFG/ps_fail_at"
run_down; chk "6.10 ps falla tras el down -> rc 1" 1 "$RC_OUT"
okfail "$LAST_OUT" "NO se liberan loops" "6.11 no libera sin confirmación fiable"
rm -f "$CFG/ps_fail" "$CFG/ps_fail_at" "$CFG/containers"
echo "def456" > "$CFG/containers"; touch "$CFG/compose_keep"
run_down; chk "6.12 quedan contenedores tras el down -> rc 1" 1 "$RC_OUT"
okfail "$LAST_OUT" "Quedan 1 contenedores" "6.13 mensaje de contenedores vivos"
rm -f "$CFG/compose_keep" "$CFG/containers"

# ============================================================
echo "== S7) _lab_nodes_lvm_off: vgs caído != VG inexistente (punto 2.C) =="
touch "$CFG/vgs_fail" "$CFG/vgs_all_fail"
r=0; out=$(_lab_nodes_lvm_off 2>&1) || r=$?
chk "7.1 LVM no responde -> nodo NO se da por limpio (rc 1)" 1 "$r"
okfail "$out" "no se pudo consultar LVM" "7.2 mensaje de consulta fallida"
rm -f "$CFG/vgs_all_fail"; printf 'vg_otra\n' > "$CFG/vgs_all"
r=0; out=$(_lab_nodes_lvm_off 2>&1) || r=$?
chk "7.3 LVM responde y la VG no está -> rc 0" 0 "$r"
okfail "$out" "no existe (LVM responde" "7.4 ausencia confirmada por LVM vivo"
rm -f "$CFG/vgs_fail" "$CFG/vgs_all"

# ============================================================
echo "== S8) _lab_dm_release: consultas caídas != sin dependencias (punto 2.E) =="
touch "$CFG/dm_ls_fail"
r=0; out=$(_lab_dm_release 2>&1) || r=$?
chk "8.1 dmsetup ls FALLA -> rc 1" 1 "$r"
okfail "$out" "no verificable" "8.2 el estado DM se declara no verificable"
rm -f "$CFG/dm_ls_fail"
printf 'vg_datos\n' > "$CFG/dms"; touch "$CFG/dm_deps_fail"; : > "$DOCKER_LOG"
r=0; out=$(_lab_dm_release 2>&1) || r=$?
chk "8.3 dmsetup deps FALLA -> rc 1" 1 "$r"
okfail "$out" "no se pudo consultar deps" "8.4 el fallo de deps se informa"
if grep -q 'remove' "$DOCKER_LOG"; then chk "8.5 sin remove a ciegas" "sin-remove" "con-remove"; else chk "8.5 sin remove a ciegas" "sin-remove" "sin-remove"; fi
rm -f "$CFG/dm_deps_fail"
printf '1 dependencies : (7, 0)\n' > "$CFG/dep_vg_datos"; : > "$DOCKER_LOG"
r=0; out=$(_lab_dm_release 2>&1) || r=$?
chk "8.6 DM de loops -> remove y rc 0" 0 "$r"
if grep -q 'dmsetup remove vg_datos' "$DOCKER_LOG"; then chk "8.7 remove ejecutado" OK OK; else chk "8.7 remove ejecutado" OK FAIL; fi
touch "$CFG/dm_busy"; printf 'vg_datos\n' > "$CFG/dms"
r=0; out=$(_lab_dm_release 2>&1) || r=$?
chk "8.8 remove falla y el DM sigue -> RETENIDO rc 1" 1 "$r"
okfail "$out" "RETENIDO; NO se fuerza" "8.9 jamás se fuerza"
rm -f "$CFG/dm_busy" "$CFG/dms" "$CFG/dep_vg_datos"

# ============================================================
echo "== S9) doctor: fallos de consulta visibles (punto 2.D) =="
touch "$CFG/systemctl_fail"
out=$(lab_doctor 2>&1) || true
okfail "$out" "no se pudo consultar systemctl" "9.1 fallo de list-units VISIBLE"
rm -f "$CFG/systemctl_fail"
touch "$CFG/vgs_fail" "$CFG/vgs_all_fail"
out=$(lab_doctor 2>&1) || true
okfail "$out" "no se pudo consultar LVM" "9.2 fallo de vgs VISIBLE (no 'VG inexistente')"
rm -f "$CFG/vgs_fail" "$CFG/vgs_all_fail"
printf '  lv_datos\n\n  lv_swap\n' > "$CFG/lvs_node1"
out=$(lab_doctor 2>&1) || true
nofail "$out" "vg_node1 sin LVs" "9.3 línea en blanco NO cuenta como LV (sin falso RB-1)"
touch "$FRESH_FAIL_FLAG"
out=$(lab_doctor 2>&1) || true
okfail "$out" "borrado fresh NO completó" "9.4 indicador de fresh fallido visible"
rm -f "$FRESH_FAIL_FLAG" "$CFG/lvs_node1"

# ============================================================
echo "== S10) regresiones r2 =="
v() { _valid_ipv4 "$1" && echo OK || echo NO; }
chk "10.1 ipv4 1.2.3.4" OK "$(v 1.2.3.4)"
chk "10.2 ipv4 rechaza 256.1.1.1" NO "$(v 256.1.1.1)"
chk "10.3 ipv4 rechaza cero a la izquierda" NO "$(v 01.2.3.4)"
D2="$CFG/daemon2.json"
printf '{"registry-mirrors":["https://mirror.local"],"dns":["8.8.8.8"],"log-level":"info"}\n' > "$D2"
chmod 640 "$D2"
r=0; setup_docker_dns "" "$D2" >/dev/null 2>&1 || r=$?
chk "10.4 dns='' -> rc 0" 0 "$r"
if grep -q 'registry-mirrors' "$D2" && ! grep -q '"dns"' "$D2"; then chk "10.5 retira solo dns" OK OK; else chk "10.5 retira solo dns" OK FAIL; fi
chk "10.6 modo 640 conservado" 640 "$(stat -c '%a' "$D2")"
echo "/datos" > "$CFG/mounts_node1"; : > "$DOCKER_LOG"
r=0; out=$(_lab_nodes_lvm_off 2>&1) || r=$?
chk "10.7 lvm_off con montaje -> busy (rc 1)" 1 "$r"
okfail "$out" "NO se intenta vgchange -an con montajes vivos" "10.8 con montaje: se informa"
if grep -q 'vgchange -an vg_node1' "$DOCKER_LOG"; then chk "10.9 sin vgchange con montajes" "sin-vgchange" "con-vgchange"; else chk "10.9 sin vgchange con montajes" "sin-vgchange" "sin-vgchange"; fi
rm -f "$CFG/mounts_node1"
r=0; out=$(_lab_wipe_node node1) || r=$?
chk "10.10 wipe limpio -> 0" 0 "$r"
echo 'SIFIRMA LVM2_member' > "$CFG/wipe_sig"
r=0; out=$(_lab_wipe_node node1) || r=$?
chk "10.11 firmas restantes -> rc 1" 1 "$r"
okfail "$out" "conserva firmas" "10.12 mensaje de firmas"
rm -f "$CFG/wipe_sig" "$FRESH_FAIL_FLAG"
touch "$CFG/attached_loop0"
r=0; out=$(lab_disks_release) || r=$?
chk "10.13 release de loop libre -> 0" 0 "$r"
chk "10.14 losetup -d ejecutado" "1" "$(grep -c 'losetup -d /dev/loop0' "$DOCKER_LOG" || true)"
touch "$CFG/attached_loop0" "$CFG/detach_fail"
r=0; out=$(lab_disks_release) || r=$?
chk "10.15 detach falla -> rc 1" 1 "$r"
rm -f "$CFG/detach_fail" "$CFG/attached_loop0"
echo "abc123" > "$CFG/containers"; touch "$CFG/compose_fail"
r=0; out=$(lab_down 2>&1) || r=$?
chk "10.16 compose down falla -> rc 1" 1 "$r"
okfail "$out" "no se anuncia destrucción completa" "10.17 no anuncia éxito"
okfail "$out" "NO se liberan loops" "10.18 no libera con vivos"
rm -f "$CFG/compose_fail" "$CFG/containers"

echo
if [ "$FAIL" -eq 0 ]; then echo "pruebas_r3: $P PASS, 0 FAIL — TODO OK"; else echo "pruebas_r3: $P PASS, HAY FALLOS"; fi
exit "$FAIL"
