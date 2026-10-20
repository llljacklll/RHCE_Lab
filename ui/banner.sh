#!/bin/bash
# ============================================================
#  🎨 UI/BANNER.SH — Cabecera de estado del laboratorio
# ============================================================
#  RESPONSABILIDAD:
#    Pintar el estado general del laboratorio: logo, versión,
#    nodos levantados y un muestreo de servicios clave.
#
#  DEPENDENCIAS:
#    - ui/colors.sh cargado (RED/GREEN/CYAN/YELLOW/NC)
#    - Docker accesible para consultar contenedores
# ============================================================

function print_banner() {

    # ---------- Metadatos ----------
    local version="$(git -C "$(dirname "$(readlink -f "$0")")" describe --tags --always 2>/dev/null || echo "v1.2.0")"
    local date_now
    date_now=$(date '+%Y-%m-%d %H:%M:%S')

    # ---------- Estado del nodo control ----------
    local status
    local control_status
    if docker ps --format '{{.Names}}' | grep -q "^control$"; then
        status="${GREEN}UP${NC}"
        control_status="${GREEN}✔${NC} control (master)"
    else
        status="${RED}DOWN${NC}"
        control_status="✖ control (down)"
    fi

    # ---------- Nodos managed levantados ----------
    local nodes
    nodes=$(docker ps --format '{{.Names}}' | grep -cE '^node[0-9]+$')
    local nodes_list
    nodes_list=$(docker ps --format '{{.Names}}' | grep -E '^node[0-9]+$' | tr '\n' ' ')
    local running="${control_status} | ${nodes_list}"

    # ---------- Logo ----------
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
    echo -e "${CYAN}Node Status:${NC}"
    for node in node1 node2 node3; do
        if docker ps --format '{{.Names}}' | grep -q "^${node}$"; then
            echo -e " ${GREEN}✔${NC} ${node} (running)"
        else
            echo -e " ${RED}✖${NC} ${node} (down)"
        fi
    done
    echo ""

    # ---------- Muestreo de servicios (solo con laboratorio arriba) ----------
    if ! docker ps --format '{{.Names}}' | grep -q "^control$"; then
        return
    fi

    echo -e "${CYAN}Service Checks (node1 - sample):${NC}"
    for svc in sshd httpd; do
        if docker exec node1 systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e " ${GREEN}✔${NC} $svc running"
        else
            echo -e " ${RED}✖${NC} $svc stopped"
        fi
    done
    if docker exec node1 rpm -q firewalld >/dev/null 2>&1; then
        echo -e " ${GREEN}✔${NC} firewalld (offline-mode)"
    else
        echo -e " ${RED}✖${NC} firewalld not installed"
    fi
    echo ""

    # ---------- Pie ----------
    echo -e "${YELLOW}----------------------------------------${NC}"
    echo -e " RHCE PRACTICE EXAM © 2026 llljacklll"
    echo -e " Licencia: CC BY-NC-SA 4.0"
    echo -e "${YELLOW}----------------------------------------${NC}"
    echo ""
}
