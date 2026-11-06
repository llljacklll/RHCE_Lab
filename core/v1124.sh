# ============================================================
#  core/v1124.sh — overrides del dictamen v1.12.4 (C-A..C-G)
#  r3: incorpora el segundo dictamen (5 grupos de bloqueo)
#  r4: incorpora el tercer dictamen (B1/B2 bloqueantes + B3)
#  r5: incorpora el cuarto dictamen (holders + reconsulta
#      post-detach); r4 queda sellado como revisión
#      intermedia (copia íntegra retirada del árbol en el
#      saneamiento previo a la publicación pública)
# ------------------------------------------------------------
#  Se sourcea AL FINAL de core/docker.sh (después de
#  core/disks.sh): bash resuelve funciones en tiempo de
#  EJECUCIÓN, así que estas definiciones SUSTITUYEN a las
#  homónimas de docker.sh/disks.sh sin tocar su texto.
#  La limpieza de los cuerpos antiguos (ya muertos) será el
#  segundo commit del mismo release, tras pasar el gate.
#  Correcciones r4 (dictamen NO-GO de la r3):
#   B1) _lab_dm_release: tras un remove fallido, la SEGUNDA
#      consulta "dmsetup ls" se comprueba por código: si
#      falla, estado DESCONOCIDO y se propaga; jamás se
#      anuncia "desapareció" sin haber podido mirar.
#   B2) _lab_nodes_lvm_off/_lab_doctor_units: el rc=0 del
#      "vgs" general solo prueba que LVM responde; la
#      ausencia de la VG se acredita LEYENDO el listado y
#      comparando el nombre exacto. Si la consulta
#      específica falló pero la VG SÍ aparece en el listado,
#      se actúa en consecuencia (no "no existe").
#   B3) nuevo _lab_loop_on_host con TRES estados para la
#      consulta de loops (0 adjuntado confirmado / 1 sin
#      binding confirmado / 2 consulta fallida). El booleano
#      de la base "[ -e /sys/block/N ]" no distingue un
#      fallo de consulta, y según la hipótesis H1 (sonda
#      pendiente) puede dar PRESENTE un loop solo registrado;
#      release/verify pasan a usar el BINDING (losetup -a)
#      con código de salida verificado.
#   D) visible también el fallo de la consulta de montajes en
#      _lab_nodes_lvm_off (una consulta caída jamás
#      equivale a "sin montajes").
#  Correcciones r5 (dictamen NO-GO de la r4):
#   1) nueva _lab_holders_on_host, sonda de TRES estados para
#      holders: la lectura desnuda "$(ls .../holders)" perdía
#      el rc dentro de la sustitución de comandos y una
#      consulta fallida parecía una lista vacía (defecto
#      confirmado en el cuarto dictamen). Contrato aprobado:
#        0 = holders PRESENTES (consulta válida)
#        1 = sin holders (consulta válida) o ausencia
#            esperada tras CONFIRMAR binding ausente
#        2 = NO concluyente: jamás se libera nada
#   2) lab_disks_release: el detach SOLO procede con "sin
#      holders" VÁLIDO; tras un detach rc=0, RECONSULTA
#      obligatoria del binding (el rc=0 del detach nunca
#      basta para declarar liberado un loop).
#   3) _lab_down_verify: mismo criterio; con holders no
#      concluyentes se informa y se propaga (jamás "sin
#      holders" ni "down verificado" sin consulta válida).
#   4) gancho de test: la sonda lee "${SYS_BLOCK:-/sys/block}"
#      (mismo gancho que setup-disks.sh); en la MV vale el
#      valor por defecto. Cierra además un hallazgo propio
#      r5: el arnés r4 leía la sysfs REAL de la MV en la
#      rama de holders (S10.13) — arnés no hermético.
#  Correcciones r3 (dictamen NO-GO de la r2):
#   A) setup_docker_dns: si "systemctl restart docker"
#      falla, se informa y SE PROPAGA (return 1); el fichero
#      puede estar bien escrito y Docker sin la config.
#   B) _lab_compose_ps: la consulta de compose tiene TRES
#      estados (OK con contenedores / OK vacía / FALLIDA);
#      una consulta fallida JAMÁS equivale a "sin
#      contenedores": se aborta y no se libera nada.
#   C) la salida temprana "ya destruido" solo procede si
#      _lab_down_verify acredita cero DM vg_* y cero loops;
#      con residuos se ejecuta el ciclo completo de
#      liberación/verificación (con sus guardas).
#   D) _lab_nodes_lvm_off: "vgs $vg" fallido NO significa
#      "la VG no existe": se pregunta a LVM en general; si
#      LVM no responde, el nodo NO se da por limpio.
#   E) _lab_dm_release y _lab_down_verify: un fallo de
#      "dmsetup ls"/"dmsetup deps" no equivale a "sin
#      dependencias" ni a "sin residuos": se informa y se
#      propaga.
#   F) doctor: un fallo de "systemctl list-units" y de
#      "vgs" se hace VISIBLE (no se disfraza de estado
#      sano); el conteo de LVs cuenta líneas no vacías de
#      verdad (awk NF, no grep -c .).
#  Correcciones r2:
#   A) daemon.json conserva modo/propietario; el temporal se
#      limpia si algo falla; fichero nuevo -> 0644.
#   B) _valid_ipv4 exige exactamente 4 octetos procesados.
#   C) con montajes vivos NO se intenta vgchange -an.
#   D) _lab_dm_release propaga fallo si retiene un DM.
#   E) lab_disks_release verifica losetup -d y propaga fallo.
#   F) _lab_wipe_node distingue "sin firmas" de "no se pudo
#      consultar", acumula fallo, devuelve no-cero y deja
#      /run/rhce-lab-fresh-FAILED para el doctor.
#   G/H) lab_down: si compose down falla no anuncia éxito;
#      solo libera si ya no quedan contenedores; acumula y
#      propaga el estado de los 4 pasos.
#   I) contador de LVs robusto (nombres no vacíos; error de
#      lvs != VG sin LVs).
#   +) hallazgo propio r2: sustituciones de comando endurecidas
#      (|| rc=$?, || true) para convivir con set -euo pipefail
#      de lab.sh; sin ellas, un grep sin coincidencias (caso
#      sano) abortaría lab.sh a mitad del down/doctor.
# ============================================================

# Gancho de test (en la MV vale el valor por defecto)
FRESH_FAIL_FLAG="${FRESH_FAIL_FLAG:-/run/rhce-lab-fresh-FAILED}"

# ---------- C-D: IPv4 estricta (3 puntos, octetos 0-255) ----------
# r2 (B): además se cuenta que el split produjo 4 campos
_valid_ipv4() {
    local ip="$1" o n nd cnt=0
    nd=$(printf %s "$ip" | tr -cd '.' | wc -c)
    [ "$nd" -eq 3 ] || return 1
    case "$ip" in *..*|.*|*.) return 1 ;; esac
    local IFS='.'
    for o in $ip; do
        cnt=$((cnt+1))
        case "$o" in ''|*[!0-9]*) return 1 ;; esac
        [ "${#o}" -le 3 ] || return 1
        n=$((10#$o))
        [ "$n" -le 255 ] || return 1
        [ "$o" = "$n" ] || return 1   # rechaza ceros a la izquierda
    done
    [ "$cnt" -eq 4 ] || return 1
    return 0
}

# ---------- C-D: setup_docker_dns que conserva daemon.json ----------
#   ""          -> retira SOLO la clave dns (no borra el fichero)
#   ip1[,ip2]   -> array solo con las IP presentes (bug ["ip",""] fuera)
#   JSON preexistente inválido -> aborta SIN sobrescribir (return 1)
#   Escritura atómica (mkstemp + fsync + os.replace)
#   r2 (A): conserva modo y propietario del fichero previo; el
#   temporal se limpia si algo falla; fichero nuevo -> 0644
#   Reinicia Docker SOLO si el contenido efectivo cambió
#   IP inválida como argumento -> exit 1 (contrato antiguo, fail-fast)
function setup_docker_dns() {
    local dns_string="$1" conf="${2:-/etc/docker/daemon.json}"
    local out rc=0 ips ip nips=0 rst
    ips=""
    if [ -n "$dns_string" ]; then
        local oldIFS="$IFS"; IFS=','
        for ip in $dns_string; do
            ip=$(printf %s "$ip" | tr -d '[:space:]')
            [ -n "$ip" ] || continue
            if ! _valid_ipv4 "$ip"; then
                echo -e "${RED}Error: '$ip' no es IPv4 válida (octetos 0-255).${NC}"
                exit 1
            fi
            ips="$ips $ip"
            nips=$((nips+1))
        done
        IFS="$oldIFS"
        [ "$nips" -le 2 ] || {
            echo -e "${RED}Error: máximo 2 servidores DNS.${NC}"; exit 1; }
    fi
    out=$(python3 - "$conf" $ips 2>&1 <<'PYDNS'
import json, os, sys, tempfile
conf, ips = sys.argv[1], sys.argv[2:]
data = {}
st = None
if os.path.exists(conf):
    try:
        with open(conf) as f:
            data = json.load(f)
        if not isinstance(data, dict):
            sys.exit("ERROR: %s no es un objeto JSON; no se toca" % conf)
    except Exception as e:
        sys.exit("ERROR: %s con JSON invalido; NO se sobrescribe: %s" % (conf, e))
    st = os.stat(conf)
elif not ips:
    print("UNCHANGED: no existe daemon.json; nada que hacer")
    sys.exit(3)
if ips:
    data["dns"] = list(ips)
else:
    data.pop("dns", None)
new = json.dumps(data, indent=2, sort_keys=True) + "\n"
if st is not None:
    old = None
    try:
        with open(conf) as f:
            old = json.dumps(json.load(f), indent=2, sort_keys=True) + "\n"
    except Exception:
        old = None
    if new == old:
        print("UNCHANGED: daemon.json sin cambios efectivos")
        sys.exit(3)
d = os.path.dirname(conf) or "."
fd, tmp = tempfile.mkstemp(prefix=".daemon.json.", dir=d)
try:
    with os.fdopen(fd, "w") as f:
        f.write(new)
        f.flush()
        os.fsync(f.fileno())
    if st is not None:
        os.chmod(tmp, st.st_mode & 0o7777)
        os.chown(tmp, st.st_uid, st.st_gid)
    else:
        os.chmod(tmp, 0o644)
    os.replace(tmp, conf)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
print("CHANGED: " + new.strip())
PYDNS
) || rc=$?
    if [ "$rc" -eq 3 ]; then
        echo -e "${YELLOW}[i] ${out#UNCHANGED: }${NC}"
        return 0
    fi
    if [ "$rc" -ne 0 ]; then
        echo -e "${RED}${out}${NC}"
        return 1
    fi
    echo -e "${GREEN}[+] daemon.json actualizado (solo se toca dns).${NC}"
    echo -e "${YELLOW}[!] Reiniciando servicio Docker...${NC}"
    if ! rst=$(sudo systemctl restart docker 2>&1); then
        echo -e "${RED}[!!] El reinicio de Docker FALLÓ; la nueva config NO está activa:${NC}"
        echo -e "${RED}${rst}${NC}"
        return 1
    fi
    echo -e "${GREEN}[+] DNS configurado correctamente en Docker.${NC}"
    return 0
}

# ---------- C-B: apagar LVM del nodo con contenedores VIVOS ----------
# Enumera montajes reales de los mapper de la VG del nodo,
# umount controlado, re-enumera; r2 (C): si queda un montaje
# NO se intenta vgchange -an (se informa y se conserva);
# vgchange -an comprobado. Jamás dmsetup --force.
# r3 (D): "vgs" fallido != VG inexistente: se distingue
# ausencia confirmada (LVM responde sin la VG) de error
# operativo (LVM no responde -> el nodo NO se da por limpio).
# r4 (B2): la ausencia se acredita LEYENDO el listado del
# vgs general y comparando el nombre EXACTO de la VG (un
# rc=0 solo prueba que LVM responde). Si la consulta
# específica falló pero la VG SÍ aparece en el listado, se
# intenta vgchange -an (no se declara inexistente).
# r4 (D): un fallo al consultar /proc/mounts se hace VISIBLE;
# tras el umount, si la re-consulta falla, el nodo queda
# como dudoso (jamás se asume "sin montajes").
_lab_nodes_lvm_off() {
    local node vg mnts mnts_rc busy=0 out vgs_out vgs_rc vg_presente
    for node in node1 node2 node3; do
        vg="vg_${node}"
        if ! _node_up "$node"; then
            echo "  [..] $node no corre: nada que apagar"
            continue
        fi
        mnts_rc=0
        mnts=$(docker exec "$node" awk -v p="/dev/mapper/${vg}-" \
               '$1 ~ p {print $2}' /proc/mounts 2>/dev/null) || mnts_rc=$?
        if [ "$mnts_rc" -ne 0 ]; then
            echo "  [..] $node: no se pudo consultar /proc/mounts (se continúa con guardas)"
        fi
        for mnt in $mnts; do
            echo "  [..] $node: umount $mnt"
            docker exec "$node" umount "$mnt" 2>&1 | sed 's/^/    /' || true
        done
        mnts_rc=0
        mnts=$(docker exec "$node" awk -v p="/dev/mapper/${vg}-" \
               '$1 ~ p {print $2}' /proc/mounts 2>/dev/null) || mnts_rc=$?
        if [ "$mnts_rc" -ne 0 ]; then
            echo "  [!!] $node: no se pudo RE-consultar /proc/mounts; estado de montajes DESCONOCIDO"
            busy=1
            continue
        fi
        if [ -n "$mnts" ]; then
            echo "  [!!] $node OCUPADO: montajes activos:$mnts"
            echo "  [..] $node: NO se intenta vgchange -an con montajes vivos"
            busy=1
            continue
        fi
        vgs_rc=0
        vg_presente=0
        if docker exec "$node" vgs "$vg" >/dev/null 2>&1; then
            vg_presente=1
        else
            vgs_out="$(docker exec "$node" vgs --noheadings -o vg_name 2>/dev/null)" || vgs_rc=$?
            if [ "$vgs_rc" -eq 0 ] && printf '%s\n' "$vgs_out" \
               | awk '{print $1}' | grep -qx "$vg"; then
                vg_presente=1
            fi
        fi
        if [ "$vg_presente" -eq 1 ]; then
            if out=$(docker exec "$node" vgchange -an "$vg" 2>&1); then
                echo "  [OK] $node: $out"
            else
                echo "  [!!] $node: vgchange -an falló: $out"
                busy=1
            fi
        elif [ "$vgs_rc" -eq 0 ]; then
            echo "  [..] $node: $vg no existe (LVM responde; ausencia acreditada en el listado)"
        else
            echo "  [!!] $node: no se pudo consultar LVM; $vg NO se da por limpia"
            busy=1
        fi
    done
    return $busy
}

# ---------- r4 (B3): consulta de loop en el host, TRES estados ----------
# La base usa "_loop_on_host() { [ -e /sys/block/$1 ]; }": un
# booleano que (a) no distingue "ausencia confirmada" de "no
# he podido preguntar" y (b) según la hipótesis H1 (sonda
# pendiente) puede dar PRESENTE un loop solo registrado, sin
# binding. Para release/verify lo que hay que acreditar es el
# BINDING, con la tabla autoritativa del kernel:
#   0 = adjuntado confirmado  ("losetup -a" lista /dev/$dev)
#   1 = SIN binding confirmado (la consulta respondió y no
#       lista el dispositivo)
#   2 = consulta FALLIDA (rc!=0): JAMÁS equivale a "ausente"
_lab_loop_on_host() {
    local dev="$1" out rc=0
    out="$(losetup -a 2>/dev/null)" || rc=$?
    if [ "$rc" -ne 0 ]; then
        return 2
    fi
    if printf '%s\n' "$out" | grep -q "^/dev/$dev:"; then
        return 0
    fi
    return 1
}

# ---------- r5: sonda de holders en el host, TRES estados ----------
# Sustituye a la lectura desnuda "$(ls /sys/block/$dev/holders)"
# cuyo rc se perdía en la sustitución de comandos: una consulta
# fallida era indistinguible de "sin holders" (defecto
# confirmado en el cuarto dictamen en v1124.sh:333 y :412).
# La sonda CONFIRMA SIEMPRE el estado del binding (reconsulta
# con _lab_loop_on_host): la excepción de directorio ausente
# solo procede con binding ausente CONFIRMADO; si el estado
# del dispositivo no se puede determinar, devuelve 2.
#   0 = consulta VÁLIDA: HAY holders (un DM retiene el loop)
#   1 = consulta VÁLIDA: sin holders; o lectura imposible con
#       binding ausente confirmado (ausencia esperada tras el
#       desadjunto)
#   2 = NO CONCLUYENTE: consulta del binding caída, o lectura
#       de holders fallida con binding vivo; JAMÁS se libera
_lab_holders_on_host() {
    local dev="$1" sb="${SYS_BLOCK:-/sys/block}" lrc=0 hout hrc=0
    lrc=0; _lab_loop_on_host "$dev" || lrc=$?
    if [ "$lrc" -eq 2 ]; then
        return 2    # binding indeterminable -> estado indeterminable
    fi
    hrc=0
    hout="$(ls "$sb/$dev/holders" 2>/dev/null)" || hrc=$?
    if [ "$hrc" -ne 0 ]; then
        if [ "$lrc" -eq 1 ]; then
            return 1    # binding ausente CONFIRMADO: ausencia esperada
        fi
        return 2        # binding vivo (o dispositivo incoherente)
    fi
    if [ -n "$hout" ]; then
        return 0
    fi
    return 1
}

# ---------- C-C: verificación explícita del down ----------
# r3 (E): "dmsetup ls" fallido no equivale a "sin DM": se
# informa y se propaga; solo con consulta OK se filtra vg_*.
# r4 (B3): cada loop se consulta con _lab_loop_on_host (tres
# estados): una consulta caída se informa y se propaga; NO
# se interpreta como "loop ausente". Un loop solo registrado
# sin binding (hipótesis H1) ya no se declara "adjuntado".
# r5: el detalle "con holders DM" / "sin holders" pasa por la
# sonda _lab_holders_on_host; con holders no concluyentes se
# informa como tal (jamás "sin holders" sin consulta válida).
_lab_down_verify() {
    local dev dms hrc lrc rc=0
    if ! dms=$(dmsetup ls 2>/dev/null); then
        echo "  [!!] dmsetup ls FALLÓ: estado DM no verificable"
        rc=1
    else
        dms=$(printf '%s\n' "$dms" | awk '{print $1}' \
              | grep -E '^vg_' | tr '\n' ' ' || true)
        if [ -n "$dms" ]; then
            echo "  [!!] DM residual tras el down: $dms"
            rc=1
        fi
    fi
    for dev in loop0 loop1 loop2 loop3 loop4 loop5; do
        lrc=0
        _lab_loop_on_host "$dev" || lrc=$?
        if [ "$lrc" -eq 2 ]; then
            echo "  [!!] /dev/$dev: consulta de loop FALLIDA; no se puede acreditar su ausencia"
            rc=1
            continue
        fi
        if [ "$lrc" -eq 1 ]; then
            continue    # sin binding confirmado (consulta OK)
        fi
        hrc=0
        _lab_holders_on_host "$dev" || hrc=$?
        if [ "$hrc" -eq 0 ]; then
            echo "  [!!] /dev/$dev sigue adjuntado y con holders DM"
        elif [ "$hrc" -eq 1 ]; then
            echo "  [!!] /dev/$dev sigue adjuntado (sin holders)"
        else
            echo "  [!!] /dev/$dev sigue adjuntado (holders no concluyentes)"
        fi
        rc=1
    done
    if [ "$rc" -eq 0 ]; then
        echo "  [OK] down verificado: sin DM vg_* y sin loops retenidos"
    fi
    return $rc
}

# ---------- C-B: DM release SIN --force (sustituye a disks.sh) ----------
# r2 (D): si un DM queda retenido, se informa Y se propaga fallo
# r3 (E): "dmsetup ls" y "dmsetup deps" fallidos no equivalen a
# "sin dependencias": se informa y se propaga.
# r4 (B1): tras un remove fallido, la SEGUNDA "dmsetup ls" se
# separa de su lectura: si la consulta falla, el estado es
# DESCONOCIDO y se propaga (jamás "desapareció" sin prueba).
_lab_dm_release() {
    local d dms deps lst_out lst_rc rc=0
    command -v dmsetup >/dev/null 2>&1 || return 0
    if ! dms=$(dmsetup ls 2>/dev/null); then
        echo "  [!!] dmsetup ls FALLÓ: estado DM no verificable"
        return 1
    fi
    for d in $(printf '%s\n' "$dms" | awk '{print $1}' \
                | grep -E '^vg_'); do
        if ! deps=$(dmsetup deps "$d" 2>&1); then
            echo "  [!!] DM $d: no se pudo consultar deps: $deps"
            rc=1
            continue
        fi
        if printf '%s\n' "$deps" | grep -qE '\(7, *(0|1|2|3|4|5)\)'; then
            if dmsetup remove "$d" 2>/dev/null; then
                echo "  [OK] liberado DM $d"
            else
                lst_rc=0
                lst_out="$(dmsetup ls 2>/dev/null)" || lst_rc=$?
                if [ "$lst_rc" -ne 0 ]; then
                    echo "  [!!] DM $d: tras el remove fallido, dmsetup ls FALLÓ; estado DESCONOCIDO (C-B)"
                    rc=1
                elif printf '%s\n' "$lst_out" | awk -v x="$d" '$1==x' | grep -q .; then
                    echo "  [!!] DM $d RETENIDO; NO se fuerza (C-B)"
                    rc=1
                else
                    echo "  [..] DM $d desapareció durante la limpieza"
                fi
            fi
        else
            echo "  [..] DM $d sin dependencias de loops del lab"
        fi
    done
    return $rc
}

# ---------- C-B: release de loops con guard de holders ----------
# r2 (E): se verifica el resultado de losetup -d y se propaga
# r4 (B1/B3): el predicado de presencia es el BINDING
# (_lab_loop_on_host, tres estados): un loop solo registrado
# sin binding no se toca ni se declara retenido (hipótesis
# H1); tras un detach fallido, la re-consulta distingue
# RETENIDO de "desapareció" de "consulta fallida (estado
# desconocido)".
# r5: el guard de holders pasa por la sonda de tres estados
# (_lab_holders_on_host): SOLO se llega al detach con "sin
# holders" VÁLIDO; con holders presentes o consulta no
# concluyente, NO se libera y se propaga (cierra el defecto
# v1124.sh:412: antes el detach podía ejecutarse sin haber
# acreditado la ausencia de holders). Tras un detach con
# rc=0, RECONSULTA obligatoria del binding: el rc=0 del
# detach JAMÁS basta para declarar liberado el loop.
lab_disks_release() {
    local dev hrc lrc rc=0
    _lab_dm_release || rc=1
    for dev in loop0 loop1 loop2 loop3 loop4 loop5; do
        lrc=0
        _lab_loop_on_host "$dev" || lrc=$?
        if [ "$lrc" -eq 2 ]; then
            echo "  [!!] /dev/$dev: consulta de loop FALLIDA; NO se toca (C-B)"
            rc=1
            continue
        fi
        if [ "$lrc" -eq 1 ]; then
            continue    # sin binding confirmado: nada que liberar
        fi
        hrc=0
        _lab_holders_on_host "$dev" || hrc=$?
        if [ "$hrc" -eq 0 ]; then
            echo "  [!!] /dev/$dev RETENIDO por DM (holders); no se libera"
            rc=1
            continue
        fi
        if [ "$hrc" -eq 2 ]; then
            echo "  [!!] /dev/$dev: holders NO concluyentes; NO se libera (C-B)"
            rc=1
            continue
        fi
        if losetup -d "/dev/$dev" 2>/dev/null; then
            lrc=0
            _lab_loop_on_host "$dev" || lrc=$?
            if [ "$lrc" -eq 1 ]; then
                echo "  [OK] liberado /dev/$dev (binding retirado, reconsulta OK)"
            elif [ "$lrc" -eq 0 ]; then
                echo "  [!!] /dev/$dev: detach rc=0 pero el binding PERSISTE; RETENIDO"
                rc=1
            else
                echo "  [!!] /dev/$dev: tras el detach la consulta FALLÓ; estado DESCONOCIDO"
                rc=1
            fi
        else
            lrc=0
            _lab_loop_on_host "$dev" || lrc=$?
            if [ "$lrc" -eq 0 ]; then
                echo "  [!!] /dev/$dev no se pudo liberar; RETENIDO"
                rc=1
            elif [ "$lrc" -eq 1 ]; then
                echo "  [OK] /dev/$dev desapareció al liberar"
            else
                echo "  [!!] /dev/$dev: tras el detach fallido la consulta FALLÓ; estado DESCONOCIDO"
                rc=1
            fi
        fi
    done
    return $rc
}

# ---------- C-E: wipe fresh verificado y con fallo visible ----------
# Único punto destructivo del ciclo de discos: SOLO el
# anfitrión, SOLO bajo FRESH_MARKER (su llamador lo guarda).
# r2 (F): distingue "sin firmas" de "no se pudo consultar";
# acumula fallos, devuelve no-cero y deja el indicador
# /run/rhce-lab-fresh-FAILED para que el doctor lo muestre.
_lab_wipe_node() {
    local node="$1" dev try sig q rc=0
    for dev in ${NODE_DISKS[$node]}; do
        for try in 1 2 3; do
            docker exec "$node" wipefs -a "/dev/$dev" >/dev/null 2>&1 \
                && break
            sleep 1
        done
        q=0
        sig=$(docker exec "$node" wipefs "/dev/$dev" 2>/dev/null) || q=$?
        if [ "$q" -ne 0 ]; then
            echo "  [!!] $node: /dev/$dev NO SE PUDO VERIFICAR (wipefs rc=$q)"
            rc=1
            continue
        fi
        if [ -n "$sig" ]; then
            echo "  [!!] $node: /dev/$dev conserva firmas: $sig"
            rc=1
            continue
        fi
        echo "  [OK] $node: /dev/$dev pristino (verificado)"
    done
    if [ "$rc" -eq 0 ]; then
        rm -f "$FRESH_FAIL_FLAG"
    else
        touch "$FRESH_FAIL_FLAG"
        echo "  [!!] $node: borrado fresh INCOMPLETO (lo muestra el doctor)" >&2
    fi
    return $rc
}

# ---------- C-C r3: consulta de compose con TRES estados ----------
#   0 = consulta OK: _lab_vivos = nº de contenedores (0..n)
#   1 = consulta FALLIDA: no se puede afirmar nada; jamás se
#       interpreta como "sin contenedores" (r3 B).
#   Requiere cwd = $DOCKER_DIR (proyecto compose).
_lab_compose_ps() {
    local out
    _lab_vivos=""
    if ! out=$(docker compose ps -aq 2>&1); then
        echo "  [!!] docker compose ps FALLÓ: $out" >&2
        return 1
    fi
    _lab_vivos=$(printf '%s\n' "$out" | awk 'NF {n++} END {print n+0}')
    return 0
}

# ---------- C-C: lab_down en el orden del dictamen ----------
# 1) LVM off con contenedores VIVOS -> 2) compose down
# -> 3) liberar solo loops realmente libres -> 4) verificar.
# r2 (G/H): si compose down falla, no se anuncia éxito y la
# liberación solo procede si ya no quedan contenedores; el
# estado de los 4 pasos se acumula y se propaga.
# r3 (B/C): consulta con tres estados; la salida temprana
# "ya destruido" exige verificación de DM/loops; una consulta
# fallida NUNCA se interpreta como "sin contenedores".
function lab_down() {
    local rco=0 rcc=0 rcr=0 rcv=0
    cd "$DOCKER_DIR" || return 1
    if ! _lab_compose_ps; then
        echo -e "${RED}[!!] No puedo acreditar el estado del laboratorio: no se libera nada.${NC}"
        return 1
    fi
    if [ "$_lab_vivos" -eq 0 ]; then
        if _lab_down_verify; then
            echo -e "${YELLOW}[!] El laboratorio ya está destruido (verificado: sin DM vg_* ni loops retenidos).${NC}"
            return 0
        fi
        echo -e "${YELLOW}[!] Sin contenedores pero con residuos de discos: se limpian con guardas.${NC}"
    fi
    echo -e "${YELLOW}[!] 1/4 Apagando LVM de los nodos (contenedores vivos)...${NC}"
    _lab_nodes_lvm_off || rco=1
    echo -e "${YELLOW}[!] 2/4 Destruyendo contenedores, red, volúmenes e imágenes...${NC}"
    if docker compose down -v --remove-orphans --rmi all; then
        echo -e "${GREEN}[+] compose down completado.${NC}"
    else
        echo -e "${RED}[!!] compose down FALLÓ; no se anuncia destrucción completa.${NC}"
        rcc=1
    fi
    if _lab_compose_ps; then
        if [ "$_lab_vivos" -eq 0 ]; then
            echo -e "${YELLOW}[!] 3/4 Liberando loops realmente libres...${NC}"
            lab_disks_release || rcr=1
        else
            echo -e "${YELLOW}[!] Quedan $_lab_vivos contenedores: NO se liberan loops.${NC}"
            rcr=1
        fi
    else
        echo -e "${RED}[!!] No se pudo confirmar que no queden contenedores: NO se liberan loops.${NC}"
        rcr=1
    fi
    echo -e "${YELLOW}[!] 4/4 Verificando el estado final...${NC}"
    _lab_down_verify || rcv=1
    if [ $((rco + rcc + rcr + rcv)) -ne 0 ]; then
        echo -e "${YELLOW}[!] down INCOMPLETO: lvm_off=$rco compose=$rcc release=$rcr verify=$rcv${NC}"
        return 1
    fi
    echo -e "${GREEN}[+] Laboratorio destruido y verificado (LVM off -> down -> release).${NC}"
    return 0
}

# ---------- C-F: doctor ampliado (unidades failed + RB-1) ----------
# Se conserva el doctor base (renombrado en el source de este
# fichero) y se le añaden: 5b unidades failed por nodo con
# pistas de rescate, 5c VG sin LVs -> pista RB-1 condicionada.
# r2 (I): contador de LVs robusto; error de lvs != VG sin LVs.
# r2 (F): muestra el indicador de borrado fresh fallido.
# r3 (F): fallo de "systemctl list-units" y de "vgs" se hace
# VISIBLE (no se convierte en "sin unidades"/"sin VG");
# conteo de LVs con awk NF (líneas no vacías de verdad).
# r4 (B2): la ausencia de la VG se acredita leyendo el
# listado del vgs general; si la consulta específica falló
# pero la VG SÍ aparece, se investiga con lvs (visible).
eval "$(declare -f lab_doctor | sed '1s/lab_doctor/_lab_doctor_base/')"
_lab_doctor_units() {
    local node failed cnt lvout vgs_out vgs_rc vg_visto
    if [ -e "$FRESH_FAIL_FLAG" ]; then
        echo "[!!] el último borrado fresh NO completó: discos posiblemente sucios"
        echo "     (el indicador se retira en el primer borrado verificado)"
    fi
    for node in node1 node2 node3; do
        _node_up "$node" || continue
        if ! failed=$(docker exec "$node" systemctl list-units --failed \
                 --no-legend --plain 2>&1); then
            echo "[..] $node: no se pudo consultar systemctl (unidades failed): $failed"
            continue
        fi
        if [ -n "$failed" ]; then
            echo "[!!] $node unidades failed:"
            echo "$failed" | sed 's/^/     /'
            case "$failed" in
            *fake-disks*)
                echo "     Pista: docker exec $node systemctl restart fake-disks"
                echo "     (idempotente v1.12.4; si reporta GHOST/CONFLICT,"
                echo "      revisa holders: lsblk /dev/loopN — no desadjuntes a mano)"
                ;;
            esac
        fi
    done
    for node in node1 node2 node3; do
        _node_up "$node" || continue
        vgs_rc=0
        vg_visto=0
        if docker exec "$node" vgs "vg_${node}" >/dev/null 2>&1; then
            vg_visto=1
        else
            # r4 (B2): el rc=0 del vgs general solo prueba que
            # LVM responde. Se LEE el listado y se busca la VG
            # exacta; si aparece, el estado se investiga.
            vgs_out="$(docker exec "$node" vgs --noheadings -o vg_name 2>/dev/null)" || vgs_rc=$?
            if [ "$vgs_rc" -eq 0 ] && printf '%s\n' "$vgs_out" \
               | awk '{print $1}' | grep -qx "vg_${node}"; then
                echo "[..] $node: la consulta específica de vg_${node} falló, pero la VG SÍ aparece en el listado"
                vg_visto=1
            fi
        fi
        if [ "$vg_visto" -eq 0 ]; then
            if [ "$vgs_rc" -ne 0 ]; then
                echo "[..] $node: no se pudo consultar LVM; estado de vg_${node} DESCONOCIDO"
            fi
            continue    # ausencia acreditada en el listado, o LVM caído (ya informado)
        fi
        if ! lvout=$(docker exec "$node" lvs --noheadings -o lv_name \
              "vg_${node}" 2>/dev/null); then
            echo "[..] $node: no pude listar LVs de vg_${node}"
            continue
        fi
        cnt=$(printf '%s\n' "$lvout" | awk 'NF {n++} END {print n+0}')
        if [ "${cnt:-0}" -eq 0 ]; then
            echo "[!!] $node: vg_${node} sin LVs (¿teardown a medias?)"
            echo "     Pista RB-1: docker exec $node vgcfgrestore --list vg_${node}"
            echo "     -> restaurar el último 'before lvremove' CON confirmación"
            echo "        del operador; jamás automatizar el restore."
        fi
    done
}
lab_doctor() {
    _lab_doctor_base "$@"
    _lab_doctor_units
}
