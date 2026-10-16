#!/bin/bash
# ============================================================
#  ⚙️ CORE/ANSIBLE.SH — Ejecutor de playbooks del alumno
# ============================================================
#  RESPONSABILIDAD:
#    Lanzar un playbook DENTRO del contenedor 'control' contra el
#    inventario estático de los 3 nodos, con soporte opcional de
#    Ansible Vault (--vault).
#
#  FLUJO:
#    1. Valida que se pasó un playbook y que existe en disco.
#    2. Comprueba que el laboratorio está levantado.
#    3. Monta el comando docker exec (inventario + become + ssh).
#    4. Si VAULT_MODE=true añade --ask-vault-pass.
#    5. Reporta el código de salida de Ansible al usuario.
# ============================================================

function lab_run() {

    # ---------- Validaciones previas ----------
    if [ -z "$PLAYBOOK_FILE" ]; then
        echo -e "${RED}Error: Debes especificar un playbook. Ej: $0 run site.yml${NC}"
        exit 1
    fi

    require_control_running   # El contenedor 'control' debe estar arriba

    local playbook_path="$PLAYBOOKS_DIR/${PLAYBOOK_FILE}"
    require_file_exists "$playbook_path" "No se encontró $playbook_path"

    # ---------- Construcción del comando ----------
    # Nota: se usa 'eval' porque las comillas anidadas de
    # --ssh-common-args no sobreviven a una expansión normal.
    echo -e "${CYAN}[+] Lanzando playbook ${PLAYBOOK_FILE}...${NC}"
    echo -e "${YELLOW}------------------------------------------------${NC}"

    local cmd="docker exec -it -w /opt/ansible control ansible-playbook -i /opt/ansible/inventory/hosts.ini -e \"ansible_become_password=ansible\" --ssh-common-args=\"-o StrictHostKeyChecking=no\""

    # Modo Vault: pide por pantalla la contraseña de desencriptado
    if [ "$VAULT_MODE" = true ]; then
        cmd+=" --ask-vault-pass"
    fi

    cmd+=" \"playbooks/${PLAYBOOK_FILE}\""

    # ---------- Ejecución ----------
    eval "$cmd"
    local exit_code=$?

    # ---------- Resultado ----------
    echo -e "${YELLOW}------------------------------------------------${NC}"
    if [ "$exit_code" -ne 0 ]; then
        echo -e "${RED}[-] El playbook falló (Código: $exit_code).${NC}"
        exit 1
    else
        echo -e "${GREEN}[+] Playbook finalizado con éxito.${NC}"
    fi
}
