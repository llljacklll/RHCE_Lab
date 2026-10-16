#!/bin/bash
# ============================================================
#  🧪 RHCE LAB — BATERÍA DE PRUEBAS AUTOMÁTICA  (./lab.sh test)
# ------------------------------------------------------------
#  Valida de principio a fin que el laboratorio está sano:
#    Fase 1 → Infraestructura y Sistema Operativo
#    Fase 2 → Conectividad y Seguridad (claves SSH)
#    Fase 3 → Motor de Automatización (Ansible 2.16)
#    Fase 4 → Ejecución real de site.yml contra los nodos
#    Fase 5 → Motor de exámenes (exam_001 + grade end-to-end)
#
#  Sale con código 0 si TODO pasa, 1 si algo falla (útil para
#  verificar el entorno tras un 'up' limpio o en CI).
# ============================================================

PASS_COUNT=0
FAIL_COUNT=0

# ------------------------------------------------------------
# Helper de aserciones: busca 'expected' dentro de 'actual'
# ------------------------------------------------------------
function _assert_contains() {
    local test_name="$1"; local expected="$2"; local actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo -e "  [${GREEN}PASS${NC}] $test_name"
        ((PASS_COUNT++))
    else
        echo -e "  [${RED}FAIL${NC}] $test_name (Esperaba: '$expected', Obtenido: '$actual')"
        ((FAIL_COUNT++))
    fi
}

function lab_test() {
    require_control_running

    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       RHCE LAB - TEST SUITE v1.1       ${NC}"
    echo -e "${CYAN}========================================${NC}"

    # ========================================================
    # FASE 1 :: Infraestructura y Sistema Operativo
    # ========================================================
    echo -e "\n${YELLOW}[+] Fase 1: Infraestructura y Sistema Operativo${NC}"

    local pid1; pid1=$(docker exec control cat /proc/1/comm 2>/dev/null)
    _assert_contains "Systemd es PID 1" "systemd" "$pid1"

    local sshd_status; sshd_status=$(docker exec node2 systemctl is-active sshd 2>/dev/null)
    _assert_contains "SSH activo en nodos" "active" "$sshd_status"

    local fw_status; fw_status=$(docker exec node1 systemctl is-enabled firewalld 2>/dev/null)
    _assert_contains "Firewalld habilitado (modo offline)" "enabled" "$fw_status"

    # ========================================================
    # FASE 2 :: Conectividad y Seguridad
    # ========================================================
    echo -e "\n${YELLOW}[+] Fase 2: Conectividad y Seguridad${NC}"

    local inv; inv=$(docker exec control printenv ANSIBLE_INVENTORY 2>/dev/null)
    _assert_contains "Inventario Ansible cargado" "/opt/ansible/inventory/hosts.ini" "$inv"

    local ssh_host
    ssh_host=$(docker exec control ssh -o StrictHostKeyChecking=no -o BatchMode=yes \
               ansible@node3 "hostname" 2>/dev/null)
    _assert_contains "SSH sin contraseña a nodos" "node3" "$ssh_host"

    # ========================================================
    # FASE 3 :: Motor de Automatización
    # ========================================================
    echo -e "\n${YELLOW}[+] Fase 3: Motor de Automatización${NC}"

    local ansible_ver; ansible_ver=$(docker exec control ansible --version 2>/dev/null | head -n 1)
    _assert_contains "Versión Ansible Core 2.16" "ansible [core 2.16" "$ansible_ver"

    # ========================================================
    # FASE 4 :: Ejecución real de playbooks (flujo RHEL)
    # ========================================================
    echo -e "\n${YELLOW}[+] Fase 4: Ejecución de Playbooks (RHEL)${NC}"

    local tmp_file; tmp_file=$(mktemp)
    echo -e "  ${CYAN}[...] Ejecutando site.yml (salida en vivo):${NC}"
    docker exec -w /opt/ansible control ansible-playbook \
        -i /opt/ansible/inventory/hosts.ini \
        -e "ansible_become_password=ansible" \
        --ssh-common-args="-o StrictHostKeyChecking=no" \
        playbooks/site.yml 2>&1 | tee "$tmp_file"
    local playbook_out; playbook_out=$(cat "$tmp_file"); rm -f "$tmp_file"

    # 🔧 FIX BUG 1: antes se afirmaba "ok=5" (hardcodeado al nº de
    # tareas de site.yml → fallaba al haber solo 4). Ahora solo
    # exigimos CERO fallos: robusto ante cambios del playbook.
    _assert_contains "Playbook site.yml sin fallos" "failed=0" "$playbook_out"

    local rpm_httpd; rpm_httpd=$(docker exec node1 rpm -q httpd 2>/dev/null | head -c 4)
    _assert_contains "httpd instalado via RPM" "http" "$rpm_httpd"

    local httpd_status; httpd_status=$(docker exec node1 systemctl is-active httpd 2>/dev/null)
    _assert_contains "httpd activo via Systemd" "active" "$httpd_status"

    # ========================================================
    # FASE 5 :: Motor de exámenes (carga → resuelve → corrige)
    # ========================================================
    echo -e "\n${YELLOW}[+] Fase 5: Motor de Exámenes${NC}"

    ensure_state_dir
    cp "$SCENARIOS_DIR/easy/exam_001.yml" "$CURRENT_EXAM_FILE"
    echo -e "  ${CYAN}[...] Forzando solución del examen 001...${NC}"
    docker exec -w /opt/ansible control ansible-playbook \
        -i /opt/ansible/inventory/hosts.ini \
        -e "ansible_become_password=ansible" \
        --ssh-common-args="-o StrictHostKeyChecking=no" \
        playbooks/exam_001.yml >/dev/null 2>&1

    local grade_out; grade_out=$( "$PROJECT_DIR/lab.sh" grade 2>&1 )
    _assert_contains "Examen 001 Aprobado" "¡ENHORABUENA, EXAMEN APROBADO!" "$grade_out"

    # ========================================================
    # RESUMEN FINAL
    # ========================================================
    echo -e "${CYAN}========================================${NC}"
    if [ "$FAIL_COUNT" -eq 0 ]; then
        echo -e " Resultado Final: ${GREEN}${PASS_COUNT} PASADOS${NC} | ${FAIL_COUNT} FALLIDOS"
        echo -e "${GREEN}¡ENTORNO DE LABORATORIO PERFECTO!${NC}"
    else
        echo -e " Resultado Final: ${PASS_COUNT} PASADOS | ${RED}${FAIL_COUNT} FALLIDOS${NC}"
        echo -e "${RED}Revisa los puntos fallidos arriba.${NC}"
    fi
    echo -e "${CYAN}========================================${NC}"
    [ "$FAIL_COUNT" -gt 0 ] && exit 1
}
