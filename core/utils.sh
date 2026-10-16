#!/bin/bash
# ==========================================
# Funciones utilitari
# ==========================================
function is_control_running() { docker ps --format '{{.Names}}' | grep -q "^control$"; }
function require_control_running() { if ! is_control_running; then echo -e "${RED}[-] El nodo 'control' no está corriendo. Ejecuta '$0 up' primero.${NC}"; exit 1; fi }
function require_file_exists() { local filepath="$1"; local error_msg="$2"; if [ ! -f "$filepath" ]; then echo -e "${RED}Error: ${error_msg:-No se encontró $filepath}${NC}"; exit 1; fi }

function prepare_local_env() {
    echo -e "${YELLOW}[!] Verificando entorno local de Ansible...${NC}"

    if [ ! -f "$INVENTORY_DIR/hosts.ini" ]; then
        echo -e "${CYAN}[+]" 1: Creando inventario local con IPs fijas...${NC}"
        cat > "$INVENTORY_DIR/hosts.ini" << 'EOFINV'
[nodes]
node1 ansible_host=172.20.0.11
node2 ansible_host=172.20.0.12
node3 ansible_host=172.20.0.13

[nodes:vars]
ansible_user=ansible
ansible_password=ansible
ansible_become_password=ansible
ansible_python_interpreter=/usr/bin/python3
EOFINV
    fi
    echo -e "${GREEN}[+] Entorno local listo.${NC}"
}

function ensure_state_dir() { mkdir -p "$STATE_DIR"; mkdir -p "$RESULTS_DIR"; }

function reset_exam_state() {
    if [ -f "$TIMER_PID_FILE" ]; then kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null; rm -f "$TIMER_PID_FILE"; fi
    rm -f "$CURRENT_EXAM_FILE"
    rm -f "$EXAM_STATUS_FILE"
}
