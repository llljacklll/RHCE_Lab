#!/bin/bash
# ============================================================
#  🧰 CORE/UTILS.SH — Utilidades comunes del motor
# ============================================================
#  RESPONSABILIDAD:
#    Funciones de apoyo reutilizadas por el resto de módulos:
#    estado de contenedores, validación de ficheros, preparación
#    del entorno local y limpieza del estado de exámenes.
# ============================================================

# ------------------------------------------------------------
# is_control_running → true si el contenedor 'control' está arriba
# ------------------------------------------------------------
function is_control_running() {
    docker ps --format '{{.Names}}' | grep -q "^control$"
}

# ------------------------------------------------------------
# require_control_running → aborta si el laboratorio está caído
# ------------------------------------------------------------
function require_control_running() {
    if ! is_control_running; then
        echo -e "${RED}[-] El nodo 'control' no está corriendo. Ejecuta '$0 up' primero.${NC}"
        exit 1
    fi
}

# ------------------------------------------------------------
# require_file_exists <ruta> [mensaje_error]
# ------------------------------------------------------------
function require_file_exists() {
    local filepath="$1"
    local error_msg="$2"
    if [ ! -f "$filepath" ]; then
        echo -e "${RED}Error: ${error_msg:-No se encontró $filepath}${NC}"
        exit 1
    fi
}

# ------------------------------------------------------------
# prepare_local_env → genera el inventario local si no existe
# (defensivo: el repo ya trae hosts.ini, pero blindamos el caso
#  de un alumno que lo borre)
# ------------------------------------------------------------
function prepare_local_env() {
    echo -e "${YELLOW}[!] Verificando entorno local de Ansible...${NC}"
    mkdir -p "$INVENTORY_DIR"
    if [ ! -f "$INVENTORY_DIR/hosts.ini" ]; then
        echo -e "${CYAN}[+] Creando inventario local con IPs fijas...${NC}"
        cat > "$INVENTORY_DIR/hosts.ini" << 'EOF'
[nodes]
node1 ansible_host=172.20.0.11
node2 ansible_host=172.20.0.12
node3 ansible_host=172.20.0.13

[nodes:vars]
ansible_user=ansible
ansible_password=ansible
ansible_become_password=ansible
ansible_python_interpreter=/usr/bin/python3
EOF
    fi
    echo -e "${GREEN}[+] Entorno local listo.${NC}"
}

# ------------------------------------------------------------
# ensure_state_dir → garantiza los directorios de estado
# ------------------------------------------------------------
function ensure_state_dir() {
    mkdir -p "$STATE_DIR"
    mkdir -p "$RESULTS_DIR"
}

# ------------------------------------------------------------
# reset_exam_state → limpia TODO el estado de un examen:
# mata el cronómetro si vive y borra los YAML de sesión
# ------------------------------------------------------------
function reset_exam_state() {
    if [ -f "$TIMER_PID_FILE" ]; then
        kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null
        rm -f "$TIMER_PID_FILE"
    fi
    rm -f "$CURRENT_EXAM_FILE"
    rm -f "$EXAM_STATUS_FILE"
}
