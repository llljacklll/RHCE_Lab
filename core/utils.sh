#!/bin/bash
# ============================================================
#  core/utils.sh — utilidades comunes del motor
# ============================================================
#  RESPONSABILIDAD:
#    Funciones de apoyo reutilizadas por el resto de módulos:
#    estado de contenedores, validación de ficheros, preparación
#    del entorno local y limpieza del estado de exámenes.
#
#  DEPENDENCIAS (sourceadas ANTES que este fichero):
#    - ui/colors.sh ......... RED/GREEN/CYAN/YELLOW/NC
#    - core/constants.sh .... INVENTORY_DIR, STATE_DIR, ficheros de estado
#
#  CONVENCIONES:
#    - is_*      -> preguntas silenciosas: exit-code, sin output.
#    - require_* -> precondiciones: fallan RUIDOSOSAMENTE (exit 1)
#                   si la acción no puede continuar.
#    - Aquí NO hay lógica de exámenes: solo se limpia su estado.
#      La lógica vive en core/exam*.sh y core/grade.sh.
# ============================================================

# ------------------------------------------------------------
# is_control_running → true si el contenedor 'control' está arriba
# (grep "^control$": match EXACTO de nombre, que no cuelen
#  'control2' ni 'xcontrol'; el espacio de nombres de docker es plano)
# ------------------------------------------------------------
function is_control_running() {
    docker ps --format '{{.Names}}' | grep -q "^control$"
}

# ------------------------------------------------------------
# require_control_running → aborta si el laboratorio está caído
# El mensaje usa $0 = cómo invocaste el lab ("./lab.sh"), así el
# remedio que imprime siempre es literalmente ejecutable.
# ------------------------------------------------------------
function require_control_running() {
    if ! is_control_running; then
        echo -e "${RED}[-] El nodo 'control' no está corriendo. Ejecuta '$0 up' primero.${NC}"
        exit 1
    fi
}

# ------------------------------------------------------------
# require_file_exists <ruta> [mensaje_error]
# ${error_msg:-...}: si no se pasa mensaje, se fabrica uno con la
# propia ruta. Guarda típico antes de leer YAML de examen/vault.
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
# DEFENSIVO: el repo ya trae ansible/inventory/hosts.ini; esto es la
# red de seguridad para el alumno que lo borre (sin inventario no hay
# lab). Las IPs fijas tienen que casar con la red que define
# docker/docker-compose.yml — si cambia la red, cambia esto también.
# Credenciales ansible/ansible en claro: es un lab LOCAL de práctica,
# no producción (en producción, Ansible Vault y claves).
# El heredoc va con 'EOF' entrecomillado: nada se expande dentro.
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
# (mkdir -p es idempotente: llámalo cuantas veces quieras)
# ------------------------------------------------------------
function ensure_state_dir() {
    mkdir -p "$STATE_DIR"
    mkdir -p "$RESULTS_DIR"
}

# ------------------------------------------------------------
# reset_exam_state → limpia TODO el estado de un examen:
# mata el cronómetro si vive y borra los YAML de sesión.
# QUIÉN LO LLAMA: lab.sh en 'down' (un examen a medias no debe
# sobrevivir a la destrucción del lab) y grade tras una expiración
# (cronómetro muerto + ficheros fuera = no queda rastro del intento).
# 'kill ... 2>/dev/null': si el PID ya murió (VM reiniciada, etc.)
# el error se silencia y limpiamos igualmente el pidfile.
# ------------------------------------------------------------
function reset_exam_state() {
    if [ -f "$TIMER_PID_FILE" ]; then
        # mata primero a los HIJOS (el sleep del cronometro) mientras
        # el padre vive: el kill del padre deja el sleep huerfano
        pkill -P "$(cat "$TIMER_PID_FILE")" 2>/dev/null || true
        kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null
        rm -f "$TIMER_PID_FILE"
    fi
    rm -f "$CURRENT_EXAM_FILE"
    rm -f "$EXAM_STATUS_FILE"
}

# ============================================================================
# require_pyyaml <comando> -- guardian V-2 (14C-b): PyYAML perezoso
# ----------------------------------------------------------------------------
# QUE: comprueba que python3 puede importar yaml ANTES de que cualquier
#      consumidor de YAML toque estado. Si falta, aborta con mensaje
#      accionable (exit 1).
# POR QUE: desde 14C-b, lab.sh ya NO corta el arranque por PyYAML: el aviso
#      inicial pasa a ser no bloqueante y el corte real ocurre AQUI, solo
#      cuando se pide una funcion que de verdad necesita YAML (exam, grade,
#      lint...). Asi up/down/logs/ps (BASH puro) siguen funcionando sin el.
# USO: require_pyyaml "exam --random"
# ============================================================================
function require_pyyaml() {
    if python3 -c "import yaml" >/dev/null 2>&1; then
        return 0
    fi
    echo -e "${RED}[-] PyYAML no disponible: '${1:-?}' lo necesita.${NC}"
    echo -e "${YELLOW}    Reparalo con el auto-instalador del lab y reintenta:${NC}"
    echo -e "${YELLOW}        bash scripts/vm_bootstrap.sh   (instala python3-pyyaml)${NC}"
    exit 1
}
