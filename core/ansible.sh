#!/bin/bash
# ==========================================
# Ejecución de playbooks (Soporte Vault)
# ==========================================
function lab_run() {
    if [ -z "$PLAYBOOK_FILE" ]; then echo -e "${RED}Error: Debes especificar un playbook. Ej: $0 run site.yml${NC}"; exit 1; fi
    require_control_running
    local playbook_path="$PLAYBOOKS_DIR/${PLAYBOOK_FILE}"
    require_file_exists "$playbook_path" "No se encontró $playbook_path"
    echo -e "${CYAN}[+] Lanzando playbook ${PLAYBOOK_FILE}...${NC}"
    echo -e "${YELLOW}------------------------------------------------${NC}"
    local cmd="docker exec -it -w /opt/ansible control ansible-playbook -i /opt/ansible/inventory/hosts.ini -e \"ansible_become_password=ansible\" --ssh-common-args=\"-o StrictHostKeyChecking=n
    if [ "$VAULT_MODE" = true ]; then cmd+=" --ask-vault-pass"; fi
    cmd+=" \"playbooks/${PLAYBOOK_FILE}\""
    eval "$cmd"
    local exit_code=$?
    echo -e "${YEL
    if [ $exit_code -ne 0 ]; then echo -e "${RED}[-] El playbook falló (Código: $exit_code).${NC}"; exit 1; else echo -e "${GREEN}[+] Playbook finalizado con éxito.${NC}"; fi
}
