#!/bin/bash
# ============================================================
#  core/docker.sh — ciclo de vida del laboratorio
# ============================================================
#  RESPONSABILIDAD:
#    Construir, levantar, parar, destruir y entrar en los
#    contenedores del laboratorio (control + node1..node3).
#
#  FUNCIONES (llamadas desde el dispatch de lab.sh):
#    lab_up / lab_start / lab_stop / lab_down / lab_reset / lab_shell
#
#  AUXILIARES (prefijo _ = interno de este fichero):
#    setup_docker_dns, _wait_for_ssh, _setup_ssh_keys,
#    _finalize_startup
#
#  FUERA DE AQUÍ:
#    lab_doctor y lab_autostart viven en core/disks.sh (histórico),
#    que se sourcea al final de este fichero. lab_disks_finalize y
#    lab_disks_release (discos de las tareas LVM) también.
#
#  NOTA DE ESTILO:
#    Este fichero usa líneas cortas a propósito: las líneas de
#    200+ caracteres se truncaban al copiar/pegar entre el chat
#    y el terminal. No las alargues.
# ============================================================

# ------------------------------------------------------------
# setup_docker_dns <"ip1,ip2"|"">
#   ""       → elimina daemon.json y restaura el DNS del sistema
#   ip1,ip2  → fuerza el DNS de Docker (redes corporativas)
#
# POR QUÉ EXISTE: docker incrusta el resolver en cada contenedor.
# Sin daemon.json copia el del host; en redes corporativas con DNS
# interno, eso hace que los contenedores no resuelvan los repos
# (dnf falla y el lab no se construye). '--dns' lo fuerza globalmente.
# CAMBIO GLOBAL: daemon.json afecta a TODO docker y reinicia el
# daemon (los contenedores que estén corriendo se paran; el 'up'
# posterior los recrea con el nuevo DNS).
# ------------------------------------------------------------
function setup_docker_dns() {
    local dns_string="$1"

    # Modo "sin DNS forzado": restaurar el del sistema
    if [ -z "$dns_string" ]; then
        echo -e "${YELLOW}[!] Usando DNS del sistema (Recomendado en redes corporativas).${NC}"
        if [ -f /etc/docker/daemon.json ]; then
            sudo rm -f /etc/docker/daemon.json
            sudo systemctl restart docker >/dev/null 2>&1
            echo -e "${GREEN}[+] Fichero daemon.json eliminado. DNS restaurado.${NC}"
        fi
        return
    fi

    # Validar formato: una IPv4 o dos separadas por coma
    if ! echo "$dns_string" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}(,([0-9]{1,3}\.){3}[0-9]{1,3})?$'; then
        echo -e "${RED}Error: El DNS '$dns_string' no es válido.${NC}"
        exit 1
    fi

    local dns1 dns2
    dns1=$(echo "$dns_string" | cut -d',' -f1)
    dns2=$(echo "$dns_string" | cut -d',' -f2)

    # PENDIENTE (bug conocido): con una sola IP, dns2 queda vacío y el
    # JSON sale como {"dns": ["1.1.1.1", ""]}, que el daemon puede
    # rechazar. Arreglo propuesto en su momento: generar el array solo
    # con las IPs presentes. NO se toca en esta pasada de comentarios.
    echo -e "${YELLOW}[!] Configurando DNS forzado de Docker (${dns1}, ${dns2})...${NC}"
    sudo mkdir -p /etc/docker
    echo "{\"dns\": [\"${dns1}\", \"${dns2}\"]}" | sudo tee /etc/docker/daemon.json > /dev/null
    echo -e "${YELLOW}[!] Reiniciando servicio Docker...${NC}"
    sudo systemctl restart docker
    echo -e "${GREEN}[+] DNS configurado correctamente en Docker.${NC}"
}

# ------------------------------------------------------------
# _wait_for_ssh <nodo>
#   Espera (máx 30s) a que systemd tenga sshd activo en el nodo.
#   Los contenedores del lab arrancan systemd REAL, así que
#   systemctl funciona dentro como en una máquina física. sshd
#   tarda unos segundos en el primer boot (genera host keys).
# ------------------------------------------------------------
function _wait_for_ssh() {
    local node="$1"
    local max_retries=30
    local count=0
    while [ $count -lt $max_retries ]; do
        if docker exec "$node" systemctl is-active --quiet sshd 2>/dev/null; then
            return 0
        fi
        count=$((count+1))
        sleep 1
    done
    return 1
}

# ------------------------------------------------------------
# _setup_ssh_keys
#   Deja a 'control' conectando SIN contraseña a los 3 nodos:
#     1) espera sshd en los 4 contenedores,
#     2) genera la clave RSA de root en control (si no existe),
#     3) ssh-copy-id al usuario 'ansible' de cada nodo, con reintentos.
#   La clave va a authorized_keys del usuario ansible: el inventario
#   (hosts.ini) trae ansible_password=ansible como fallback, pero con
#   la clave Ansible no pide password en cada conexión.
# ------------------------------------------------------------
function _setup_ssh_keys() {
    echo -e "${CYAN}[+] Configurando claves SSH entre nodos...${NC}"

    # 1) Esperar a que los 4 contenedores tengan sshd activo
    for node in control node1 node2 node3; do
        echo -e "  Esperando SSH en ${node}..."
        if ! _wait_for_ssh "$node"; then
            echo -e "  ${RED}[FAIL] ${node} no arrancó SSH a tiempo${NC}"
            return 1
        fi
        echo -e "  ${GREEN}[OK]${NC} ${node}"
    done

    # 2) Generar la clave RSA de root en el control (si no existe)
    #    -N "" = sin passphrase; -q silencia la salida de ssh-keygen.
    docker exec control bash -c \
        'if [ ! -f /root/.ssh/id_rsa ]; then ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa -q; fi'

    # 3) Copiar la clave pública a cada nodo (con reintentos)
    #    sshpass -p ansible: el password de práctica del lab.
    #    StrictHostKeyChecking=no: no pedir confirmación de fingerprint
    #    (los contenedores se recrean y sus host keys cambian siempre).
    #    &>/dev/null: silencia TODO, incluido el prompt; solo importa
    #    el exit-code, que alimenta los reintentos (20 x 1s).
    for node in node1 node2 node3; do
        local max_retries=20
        local count=0
        local success=false
        while [ $count -lt $max_retries ]; do
            if docker exec control sshpass -p ansible ssh-copy-id \
                 -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
                 ansible@"${node}" &>/dev/null; then
                success=true
                break
            fi
            count=$((count+1))
            sleep 1
        done
        if $success; then
            echo -e "  ${GREEN}[OK]${NC} Clave → ${node}"
        else
            echo -e "  ${RED}[FAIL] No se pudo copiar clave a ${node}${NC}"
        fi
    done
    echo -e "${GREEN}[+] Claves SSH configuradas.${NC}"
}

# ------------------------------------------------------------
# _finalize_startup
#   Últimos pasos tras levantar, en orden:
#     1) lab_disks_finalize (core/disks.sh): crea/recupera los loops
#        de LVM por nodo + filtro. '|| true': un problema de discos
#        NO debe tumbar el arranque (se diagnostica con 'doctor').
#     2) esperar systemd y repartir claves SSH
#     3) nota firewalld offline (portable en WSL2/VM: el paquete
#        está, el servicio no se gestiona en contenedores)
#     4) tabla de contenedores (compose ps) y ping de Ansible
# El ping corre DENTRO de control: -w /opt/ansible = cwd del
# contenedor (la carpeta ansible/ del repo montada); el ping es
# INFORMATIVO, no aborta si falla — el alumno ve el unreachable
# y puede reintentar. 2>/dev/null silencia warnings de SSH.
# ------------------------------------------------------------
function _finalize_startup() {
    # discos + filtro LVM por nodo (implementación en core/disks.sh)
    lab_disks_finalize || true
    echo -e "${YELLOW}[!] Esperando a que systemd arranque los servicios...${NC}"
    _setup_ssh_keys
    echo ""
    echo -e "${YELLOW}[!] Nota: Firewalld se usa en modo 'offline' (portable en WSL2 y VM).${NC}"
    sleep 2
    echo -e "${GREEN}[+] Entorno listo.${NC}"
    cd "$DOCKER_DIR" && docker compose ps
    echo ""
    echo -e "${CYAN}[+] Verificando conectividad Ansible...${NC}"
    docker exec -w /opt/ansible control ansible nodes -m ping \
        -i /opt/ansible/inventory/hosts.ini \
        --ssh-common-args="-o StrictHostKeyChecking=no" 2>/dev/null
}

# ------------------------------------------------------------
# lab_up → construir imágenes (--build) y levantar TODO
# MARCADOR "FRESH" (clave para los discos del alumno):
#   /run/rhce-lab-fresh le dice a core/disks.sh que el arranque es
#   fresco y puede RE-CREAR (wipe) los loops. /run es tmpfs: el
#   marcador muere solo al reiniciar la MV. La regla es sutil:
#   si el lab YA está corriendo (up/bootstrap sobre lab arriba) NO se
#   marca fresh → los discos del alumno NO se borran. Tras un down o
#   un reboot de la MV, node1 no existe/no corre → marcador → wipe.
#   Se consulta node1 como testigo: si node1 corre, el lab corre.
# ------------------------------------------------------------
function lab_up() {
    if ! docker inspect -f '{{.State.Running}}' node1 \
         2>/dev/null | grep -q true; then
        touch /run/rhce-lab-fresh 2>/dev/null || true
    fi
    prepare_local_env
    setup_docker_dns "$DNS_CONFIG"
    echo -e "${GREEN}[+] Levantando laboratorio (Construyendo imágenes)...${NC}"
    cd "$DOCKER_DIR" || exit 1
    docker compose up -d --build
    _finalize_startup
}

# ------------------------------------------------------------
# lab_start → levantar SIN recompilar (rápido)
# No gestiona el marcador fresh: solo lab_up decide qué es "fresco".
# Útil para reactivar tras un 'stop' o un reinicio de la MV con las
# imágenes ya construidas.
# ------------------------------------------------------------
function lab_start() {
    echo -e "${GREEN}[+] Levantando laboratorio (sin recompilar)...${NC}"
    cd "$DOCKER_DIR" || exit 1
    docker compose up -d
    _finalize_startup
}

# ------------------------------------------------------------
# lab_stop → detener contenedores (conserva imágenes y datos)
# 'compose ps -q' vacío = no hay NADA corriendo de este proyecto.
# stop ≠ down: conserva contenedores, volúmenes e imágenes.
# ------------------------------------------------------------
function lab_stop() {
    cd "$DOCKER_DIR" || exit 1
    if [ -z "$(docker compose ps -q 2>/dev/null)" ]; then
        echo -e "${YELLOW}[!] El laboratorio ya está detenido.${NC}"
        return
    fi
    echo -e "${YELLOW}[!] Deteniendo contenedores...${NC}"
    docker compose stop
    echo -e "${GREEN}[+] Laboratorio detenido (usa 'start' para reactivarlo).${NC}"
}

# ------------------------------------------------------------
# lab_down → destruir TODO: contenedores, red, volúmenes e imágenes
# 'ps -aq' (con -a) para detectar también contenedores PARADOS:
# tras un 'stop' el proyecto existe aunque no corra nada, y down
# debe limpiarlo igualmente.
#   -v            : borra volúmenes (¡los datos de dentro!)
#   --rmi all     : borra las imágenes del proyecto
#   --remove-orphans: limpia contenedores sueltos de renombres antiguos
# Después libera los loops del host (lab_disks_release): los loops
# son GLOBALES al host; si quedan ocupados, el próximo arranque
# recibiría loop6, loop7... y las tareas/checkers esperan los
# números exactos loop0/2/4. '|| true': no bloquea la destrucción.
# ------------------------------------------------------------
function lab_down() {
    cd "$DOCKER_DIR" || exit 1
    if [ -z "$(docker compose ps -aq 2>/dev/null)" ]; then
        echo -e "${YELLOW}[!] El laboratorio ya está destruido.${NC}"
        return
    fi
    echo -e "${YELLOW}[!] Destruyendo laboratorio (total: contenedores, red, volúmenes e imágenes)...${NC}"
    docker compose down -v --remove-orphans --rmi all
    echo -e "${GREEN}[+] Laboratorio destruido por completo.${NC}"
    # liberar loops del host para que el próximo fresh reciba 0/2/4
    lab_disks_release || true
}

# ------------------------------------------------------------
# lab_reset → regeneración limpia (down + up)
# La vía soportada de "empezar de cero": down destruye todo y el up
# posterior detecta arranque fresco → loops re-creados limpios.
# ------------------------------------------------------------
function lab_reset() {
    lab_down
    echo "-----------------------------------"
    lab_up
}

# ------------------------------------------------------------
# lab_shell → entrar interactivo al nodo control
# '-it' = terminal interactiva (por eso solo tiene sentido desde
# una consola; los scripts usan 'docker exec' sin -t).
# ------------------------------------------------------------
function lab_shell() {
    require_control_running
    echo -e "${CYAN}[+] Entrando al nodo de control...${NC}"
    echo -e "${YELLOW}------------------------------------------------${NC}"
    echo -e "${YELLOW}Tip: para salir del contenedor, escribe 'exit'.${NC}"
    docker exec -it control bash
}

# ------------------------------------------------------------
# CARGA TARDÍA de core/disks.sh (discos LVM + doctor + autostart)
# lab_doctor y lab_autostart viven ahí (histórico). Cargarlo al FINAL
# es seguro: bash resuelve las llamadas a funciones en tiempo de
# EJECUCIÓN, y las funciones de arriba solo invocan lab_disks_*
# cuando ya estará en memoria.
# Doble fallback: sourceado desde lab.sh ($0 = raíz) vale la 1ª
# ruta; en pruebas con otro cwd, la 2ª. '|| true': que la falta de
# disks.sh no tumbe el resto del lab.
# ------------------------------------------------------------
source "$(dirname "$(readlink -f "$0")")/core/disks.sh" 2>/dev/null \
  || source core/disks.sh 2>/dev/null || true
