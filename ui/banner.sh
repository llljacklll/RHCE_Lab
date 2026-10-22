#!/bin/bash
# ============================================================
#  ui/banner.sh — panel de estado del laboratorio (print_banner)
# ============================================================
#  RESPONSABILIDAD:
#    Pintar el estado general: logo, versión, nodos levantados,
#    estado nodo a nodo y un MUESTREO de servicios clave.
#    Es la "cara" del lab: lo primero que ve el usuario.
#
#  DEPENDENCIAS:
#    - ui/colors.sh sourceado (GREEN/RED/CYAN/YELLOW/NC)
#    - docker accesible (si no, simplemente pinta todo en DOWN)
#
#  NOTA DE DISEÑO:
#    - Es un VISTAZO, no un diagnóstico: muestrea solo node1 y solo
#      sshd/httpd/firewalld. El diagnóstico completo es './lab.sh doctor'.
#    - Se sourcea desde lab.sh (en la raíz del repo), por eso
#      'dirname $0' apunta a la raíz: ahí vive .git, que es de donde
#      'git describe' saca la versión.
# ============================================================

function print_banner() {

    # ---------- Metadatos ----------
    # La versión sale de GIT, no de una constante: el tag si existe
    # (git tag -a v1.3.3), o el hash corto del commit si no hay tags.
    # El fallback 'v1.3.3' solo aparece si git no está disponible.
    local version="$(git -C "$(dirname "$(readlink -f "$0")")" describe --tags --always 2>/dev/null || echo "v1.3.3")"
    local date_now
    date_now=$(date '+%Y-%m-%d %H:%M:%S')

    # ---------- Estado del nodo control ----------
    # El control manda: sin control no hay lab. grep -q "^control$" es
    # match EXACTO de nombre (que no cuelen 'control2' o 'xcontrol').
    local status
    local control_status
    if docker ps --format '{{.Names}}' | grep -q "^control$"; then
        status="${GREEN}UP${NC}"
        control_status="${GREEN}[OK]${NC} control (master)"
    else
        status="${RED}DOWN${NC}"
        control_status="${RED}[X]${NC} control (down)"
    fi

    # ---------- Nodos managed levantados ----------
    # -c cuenta; -E '^node[0-9]+$' acepta cualquier nodeN (si algún día
    # crece el inventario, el banner no hay que tocarlo). 'tr' junta
    # los nombres en una sola línea para el panel.
    local nodes
    nodes=$(docker ps --format '{{.Names}}' | grep -cE '^node[0-9]+$')
    local nodes_list
    nodes_list=$(docker ps --format '{{.Names}}' | grep -E '^node[0-9]+$' | tr '\n' ' ')
    local running="${control_status} | ${nodes_list}"

    # ---------- Logo ----------
    # Arte ASCII en cian: reconocible a golpe de ojo. echo -e porque
    # las variables de colors.sh llevan escapes \033.
    echo -e "${CYAN}"
    echo "██████╗ ██╗  ██╗ ██████╗ ███████╗"
    echo "██╔══██╗██║  ██║██╔════╝ ██╔════╝"
    echo "██████╔╝███████║██║      █████╗  "
    echo "██╔══██╗██║  ██║██║      ██╔══╝  "
    echo "██║  ██║██║  ██║╚██████╗ ███████╗"
    echo "╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝"
    echo ""
    echo "        RHCE AUTOMATION LAB"
    echo -e "${NC}"

    # ---------- Panel de estado ----------
    echo -e "${YELLOW}----------------------------------------${NC}"
    echo -e " Version : ${version}"
    echo -e " Status  : ${status}"
    echo -e " Nodes   : ${nodes}"
    echo -e " Running : ${running}"
    echo -e " Date    : ${date_now}"
    echo -e "${YELLOW}----------------------------------------${NC}"

    # ---------- Estado nodo a nodo ----------
    # Bucle fijo node1..node3 (inventario estable del lab). Si algún
    # día el inventario fuera dinámico, iterar sobre nodes_list.
    echo -e "${CYAN}Node Status:${NC}"
    for node in node1 node2 node3; do
        if docker ps --format '{{.Names}}' | grep -q "^${node}$"; then
            echo -e " ${GREEN}[OK]${NC} ${node} (running)"
        else
            echo -e " ${RED}[X]${NC} ${node} (down)"
        fi
    done
    echo ""

    # ---------- Muestreo de servicios (solo con laboratorio arriba) ----------
    # Si control está caído, no hay docker exec posible: return seco.
    if ! docker ps --format '{{.Names}}' | grep -q "^control$"; then
        return
    fi

    # Sample en node1: sshd (conectividad base) y httpd (servicio de
    # práctica). --quiet: is-active responde con exit-code, sin output.
    echo -e "${CYAN}Service Checks (node1 - sample):${NC}"
    for svc in sshd httpd; do
        if docker exec node1 systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e " ${GREEN}[OK]${NC} $svc running"
        else
            echo -e " ${RED}[X]${NC} $svc stopped"
        fi
    done
    # firewalld: se comprueba INSTALACIÓN (rpm -q), no estado del
    # servicio — de ahí el "offline-mode": el paquete está presente,
    # pero el servicio no se gestiona dentro de los contenedores.
    if docker exec node1 rpm -q firewalld >/dev/null 2>&1; then
        echo -e " ${GREEN}[OK]${NC} firewalld (offline-mode)"
    else
        echo -e " ${RED}[X]${NC} firewalld not installed"
    fi
    echo ""

    # ---------- Pie: autoría y licencia ( Visible siempre ) ----------
    echo -e "${YELLOW}----------------------------------------${NC}"
    echo -e " RHCE PRACTICE EXAM © 2026 llljacklll"
    echo -e " Licencia: CC BY-NC-SA 4.0"
    echo -e "${YELLOW}----------------------------------------${NC}"
    echo ""
}
