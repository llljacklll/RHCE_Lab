#!/bin/bash
# ============================================================
#  core/ansible.sh — ejecutor de playbooks del alumno
# ============================================================
#  RESPONSABILIDAD (una sola, y bien hecha):
#    Lanzar un playbook del alumno DENTRO del contenedor
#    'control', contra el inventario estático de los 3
#    nodos, con soporte opcional de Ansible Vault.
#
#  QUIÉN LO LLAMA: el dispatch de lab.sh, con dos globales
#    ya fijadas según los flags del usuario:
#      PLAYBOOK_FILE ... nombre del .yml a ejecutar
#      VAULT_MODE ...... true si se pasó --vault
#
#  FLUJO:
#    1. Valida que se pasó un playbook y que existe en
#       $PLAYBOOKS_DIR (ansible/playbooks/).
#    2. Comprueba que el laboratorio está arriba (control
#       es quien tiene la clave ssh de los nodos).
#    3. Monta el comando docker exec (inventario, become,
#       ssh relajado).
#    4. Si VAULT_MODE=true añade --ask-vault-pass.
#    5. Ejecuta y reporta el código de salida al usuario.
#
#  DECISIONES DE DISEÑO (por qué es así):
#    - docker exec -it: el terminal es INTERACTIVO para
#      que --ask-vault-pass (y cualquier prompt de ansible)
#      pueda preguntar en pantalla. Sin -t, el ask muere.
#    - ansible_become_password viaja por -e: las creds del
#      lab son públicas del repo (ansible/ansible, en el
#      README); --ask-become-pass obligaría a teclearlas
#      en cada run sin añadir ni un ápice de seguridad.
#    - StrictHostKeyChecking=no: los nodos regeneran su
#      host key en cada 'lab.sh reset' y el known_hosts de
#      control arranca vacío; pedir confirmación rompería
#      la automatización en el primer run de cada reset.
#    - -w /opt/ansible: el WORKDIR estándar de control; el
#      playbook se pasa RELATIVO ("playbooks/foo.yml") y el
#      directorio ansible/ del repo está montado justo en
#      /opt/ansible, así que host y contenedor ven el
#      MISMO fichero.
# ============================================================

function lab_run() {

    # ---------- Validaciones previas ----------
    # Sin playbook no hay nada que ejecutar. $0 va en el
    # mensaje (cómo invocaste el lab) para que el remedio
    # sea literalmente copiable.
    if [ -z "$PLAYBOOK_FILE" ]; then
        echo -e "${RED}Error: Debes especificar un playbook. Ej: $0 run site.yml${NC}"
        exit 1
    fi

    require_control_running   # El contenedor 'control' debe estar arriba

    # La ruta se monta contra $PLAYBOOKS_DIR (constante de
    # constants.sh), no contra el cwd: 'run' funciona igual
    # desde el directorio donde esté el usuario.
    local playbook_path="$PLAYBOOKS_DIR/${PLAYBOOK_FILE}"
    require_file_exists "$playbook_path" "No se encontró $playbook_path"

    # ---------- Construcción del comando ----------
    echo -e "${CYAN}[+] Lanzando playbook ${PLAYBOOK_FILE}...${NC}"
    echo -e "${YELLOW}------------------------------------------------${NC}"
    # NOTE: se usa 'eval' porque las comillas anidadas de
    # --ssh-common-args no sobreviven a una expansión
    # normal: sin eval, bash pasaría las comillas COMO
    # PARTE del valor a ssh y la opción rompería. El cmd
    # completo (larga línea de abajo) es un solo string.
    # -t solo con TTY en stdin: interactivo igual que hoy y ademas scriptable (bateria/CI)
    local tty_flag=""
    if [ -t 0 ]; then tty_flag="-t"; fi
    local cmd="docker exec -i $tty_flag -w /opt/ansible control ansible-playbook -i /opt/ansible/inventory/hosts.ini -e \"ansible_become_password=ansible\" --ssh-common-args=\"-o StrictHostKeyChecking=no\""

    # Modo Vault: pide por pantalla la contraseña de
    # desencriptado (interactivo gracias al -it de arriba).
    # VAULT_MODE lo fija lab.sh con el flag --vault.
    if [ "$VAULT_MODE" = true ]; then
        cmd+=" --ask-vault-pass"
    fi

    # Ruta RELATIVA dentro de control: /opt/ansible es el
    # working directory (-w) y el punto de montaje del repo.
    cmd+=" \"playbooks/${PLAYBOOK_FILE}\""

    # ---------- Ejecución ----------
    eval "$cmd"
    local exit_code=$?

    # ---------- Resultado ----------
    # El exit code de ansible-playbook resume la corrida
    # (0 = todos los hosts ok; 2+ = hubo tareas failed).
    # Se propaga como exit 1 para que un script o un cron
    # que envuelva al lab pueda detectar el fallo.
    echo -e "${YELLOW}------------------------------------------------${NC}"
    if [ "$exit_code" -ne 0 ]; then
        echo -e "${RED}[-] El playbook falló (Código: $exit_code).${NC}"
        exit 1
    else
        echo -e "${GREEN}[+] Playbook finalizado con éxito.${NC}"
    fi
}
