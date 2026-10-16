#!/bin/bash
# ==========================================
# Gestión del ciclo de vida Docker
# ==========================================
function setup_docker_dns() {
    local dns_string="$1"
    if [ -z "$dns_string" ]; then
        echo -e "${YELLOW}[!] Usando DNS del sistema (Recomendado en redes corporativas).${NC9}"
        if [ -f /etc/docker/daemon.json ]; then sudo rm -f /etc/docker/daemon.json; sudo systemctl restart docker >/dev/null 2>&1; echo -e "${GREEN}[+] Fichero daemon.json eliminado.${NC}"; fi
        return
    fi
    if ! echo "$dns_string" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}(,([0-9]{1,3}\.){3}[0-9]{1,3})?$'; then echo -e "${RED}Error: El DNS no es válido.${NC}"; exit 1; fi
    local dns1=$(echo "$dns_string" | cut -d',' -f1); local dns2=$(echo "$dns_string" | cut -d',' -f2)
    echo -e "${YELLOW}[!] Configurando DNS forzado (${dns1}, ${dns2})...${NC}"
    sudo mkdir -p /etc/docker; echo "{\"dns\": [\"${dns1}\", \"${dns2}\"]}" | sudo tee /etc/docker/daemon.json > /dev/null
    sudo systemctl restart docker; echo -e "${GREEN}[+] DNS configurado.${NC}"
}

function _wait_for_ssh() { local node="$1"; local max_retries=30; local count=0; while [ $count -lt $max_retries ]; do if docker exec "$node" systemctl is-active --quiet sshd 2>/dev/null; then return 0; fi; count=$((count+1)); sleep 1; done; return 1; }

function _setup_ssh_keys() {
    echo -e "${CYAN}[+] Configurando claves SSH...${NC}"
    for node in control node1 node2 node3; do if ! _wait_for_ssh "$node"; then echo -e "  ${RED}[FAIL] ${node}${NC}"; return 1; fi; done
    docker exec control bash -c 'if [ ! -f /root/.ssh/id_rsa ]; then ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa 
    for node in node1 node2 node3; do
        local max_retries=20 count=0 success=false
        while [ $count -lt $max_retries ]; do if docker exec control sshpass -p ansible ssh-copy-id -o StrictHostKeyChecking=no -o ConnectTimeo
        $success && echo -e "  ${GREEN}[OK]${NC} Clave -> ${node}" || echo -e "  ${RED}[FAIL]${NC} ${node}"
    done
}

function _finalize_startup() {
    echo -e "${YELLOW}[!] Esperando systemd...${NC}"; _setup_ssh_keys; sleep 2
    echo -e "${GREEN}[+] Entorno listo.${NC}"; cd "$DOCKER_DIR" && docker compose ps
    echo -e "\n${CYAN}[+] Verificando conectividad Ansible...${NC}"
    docker exec -w /opt/ansible control ansible nodes -m ping -i /opt/ansible/inventory/hosts.ini --ssh-common-args="-o StrictHostKeyChecking=no" 2>/dev/null
}

function lab_up() { prepare_local_env; setup_docker_dns "$DNS_CONFIG"; echo -e "${GREEN}[+] Levantando laboratorio (Construyendo)...${NC}"; cd 
function lab_down() { cd "$DOCKER_DIR" || exit 1; if [ -z "$(docker compose ps -q 2>/dev/null)" ]; then echo -e "${YELLOW}[!] Ya está 

function lab_stop() { cd "$DOCKER_DIR" || exit 1; if [ -z "$(docker compose ps -q 2>
function lab_reset() { lab_down; echo "-----------------------------------"; lab_up; }

function lab_shell() {
    require_control_running
    echo -e "${CYAN}[+] Entrando al nodo de control...${NC}"
    echo -e "${YELLOW}------------------
    docker exec -it control bash
}
