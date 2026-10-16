#!/bin/bash
# ============================================================
#  🐳 CORE/DOCKER.SH — Ciclo de vida del laboratorio
# ============================================================
#  RESPONSABILIDAD:
#    Construir, levantar, parar, destruir y entrar en los
#    contenedores del laboratorio (control + node1..node3).
#
#  FUNCIONES (llamadas desde lab.sh):
#    lab_up / lab_start / lab_stop / lab_down / lab_reset / lab_shell
#
#  AUXILIARES:
#    setup_docker_dns, _wait_for_ssh, _setup_ssh_keys,
#    _finalize_startup
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

    echo -e "${YELLOW}[!] Configurando DNS forzado de Docker (${dns1}, ${dns2})...${NC}"
    sudo mkdir -p /etc/docker
    echo "{\"dns\": [\"${dns1}\", \"${dns2}\"]}" | sudo tee /etc/docker/daemon.json > /dev/null
    echo -e "${YELLOW}[!] Reiniciando servicio Docker...${NC}"
    sudo systemctl restart docker
    echo -e "${GREEN}[+] DNS configurado correctamente en Docker.${NC}"
}

# ------------------------------------------------------------
# _wait_for_ssh <nodo>
#   Espera (máx 30s) a que systemd tenga sshd activo en el nodo
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
#   Genera la clave RSA de root en 'control' y la reparte a los
#   3 nodos para que Ansible conecte sin contraseña.
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
    docker exec control bash -c \
        'if [ ! -f /root/.ssh/id_rsa ]; then ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa -q; fi'

    # 3) Copiar la clave pública a cada nodo (con reintentos)
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
#   Últimos pasos tras levantar: claves SSH + tabla de
#   contenedores + ping de Ansible a los 3 nodos.
# ------------------------------------------------------------
function _finalize_startup() {
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
# ------------------------------------------------------------
function lab_up() {
    prepare_local_env
    setup_docker_dns "$DNS_CONFIG"
    echo -e "${GREEN}[+] Levantando laboratorio (Construyendo imágenes)...${NC}"
    cd "$DOCKER_DIR" || exit 1
    docker compose up -d --build
    _finalize_startup
}

# ------------------------------------------------------------
# lab_start → levantar SIN recompilar (rápido)
# ------------------------------------------------------------
function lab_start() {
    echo -e "${GREEN}[+] Levantando laboratorio (sin recompilar)...${NC}"
    cd "$DOCKER_DIR" || exit 1
    docker compose up -d
    _finalize_startup
}

# ------------------------------------------------------------
# lab_stop → detener contenedores (conserva imágenes y datos)
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
# lab_down → destruir contenedores, red, volúmenes e imágenes
#   (usa ps -aq para detectar también contenedores parados)
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
}

# ------------------------------------------------------------
# lab_reset → regeneración limpia (down + up)
# ------------------------------------------------------------
function lab_reset() {
    lab_down
    echo "-----------------------------------"
    lab_up
}

# ------------------------------------------------------------
# lab_shell → entrar interactivo al nodo control
# ------------------------------------------------------------
function lab_shell() {
    require_control_running
    echo -e "${CYAN}[+] Entrando al nodo de control...${NC}"
    echo -e "${YELLOW}------------------------------------------------${NC}"
    echo -e "${YELLOW}Tip: para salir del contenedor, escribe 'exit'.${NC}"
    docker exec -it control bash
}
