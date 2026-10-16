#!/bin/bash
# ==========================================
# Banner e información de estado
# ==========================================

function print_banner() {
    local version="v1.0"; local date_now; date_now=$(date '+%Y-%m-%d %H:%M:%S')
    local status; if docker ps | grep -q "control"; then status="${GREEN}UP${NC}"; else status="${RED}DOWN${NC}"; fi
    local nodes; nodes=$(docker ps --format '{{.Names}}' | grep -E '^node[0-9]$' | wc -l)
    local control_status="✖ control (down)"; if docker ps --format '{{.Names}}' | grep -q "^control$"; then control_status="${GREEN}✔${NC} control (master)"; fi
    local nodes_list; nodes_list=$(docker ps --format '{{.Names}}' | grep -E '^node[0-9]$' | tr '\n' ' ')
    local running="${control_status} | ${nodes_list}"

    echo -e "${CYAN}"; echo "██████╗ ██╗  ██╗ ██████╗ ███████╗"; echo "██╔══██╗██║  ██║██╔════╝ ██╔════╝"; echo "██████╔╝███████║██║      █████╗  "; echo "██╔══██╗██║  ██║██║      ██╔══╝  "; echo "██║  
    echo -e "${YELLOW}----------------------------------------${NC}"; echo -e " Version : ${version}"; echo -e " Status  : ${status}"; echo -e " Nodes   : ${nodes}"; echo -e " Running : ${running}"; echo -e " Date    : ${date_now}"; echo -e "${YELLOW}----------------------------------------${NC}"

    echo -e "${CYAN}Node Status:${NC}"
    for node in node1 node2 node3; do
        if docker ps --format '{{.Names}}' | grep -q "^${node}$"; then echo -e " ${GREEN}✔${NC} ${node} (running)"; else echo -e " ${RED}✖${NC} ${node} (down)"; fi
    done; echo ""

    if ! docker ps | grep -q "control"; then return; fi
    echo -e "${CYAN}Service Checks (node1 - sample):${NC}"
    for svc in sshd httpd; do if docker exec node1 systemctl is-active --quiet $svc >/dev/null 2>&1; then echo " ✔ $svc running"; else echo " ✖ $svc stopped"; fi; done
    if docker exec node1 rpm -q firewalld >/dev/null 2>&1; then echo " ✔ firewalld (offline-mode)"; else echo " ✖ firewalld not installed"; fi
    echo ""

    echo -e "${YELLOW}----------------------------------------${NC}"; echo -e " RHCE PRACTICE EXAM © 2026 llljacklll"; echo -e " Proyecto educativo desarrollado con ayuda de IA"; echo -e " Licencia: CC BY-NC-SA 4.0"; echo -e "$
}
