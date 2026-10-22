#!/bin/bash
# ============================================================
#  core/test.sh — BATERÍA DE PRUEBAS AUTOMÁTICA  (./lab.sh test)
# ------------------------------------------------------------
#  RESPONSABILIDAD:
#    Validar de principio a fin que el laboratorio está sano.
#    No es un framework de unit-tests: es una batería de humo
#    END-TO-END que lanza comandos reales contra los
#    contenedores (docker exec) y comprueba RESULTADOS, no
#    intenciones. Si las 5 fases pasan, el entorno puede
#    sostener un examen completo de verdad.
#
#  LAS 5 FASES (cada una depende de la anterior):
#    Fase 1 -> Infraestructura y Sistema Operativo
#              (systemd como PID 1, sshd activo, firewalld)
#    Fase 2 -> Conectividad y Seguridad
#              (inventario cargado, SSH sin contraseña)
#    Fase 3 -> Motor de Automatización (Ansible Core 2.16)
#    Fase 4 -> Ejecución real de site.yml contra los nodos
#    Fase 5 -> Motor de exámenes (carga -> resuelve -> corrige)
#
#  CONTRATO DE SALIDA (importante para CI):
#    Sale con código 0 si TODO pasa, 1 si algo falla (útil
#    para verificar el entorno tras un 'up' limpio o en CI).
#    ARREGLO de esta pasada: históricamente la función
#    devolvía 1 TAMBIÉN al aprobarlo todo, porque su último
#    comando era "[ ... ] && exit 1" (condición falsa =>
#    estatus 1). Ahora cierra con "return 0" explícito. Es la
#    única línea funcional añadida en toda la documentación.
#
#  POR QUÉ "$PROJECT_DIR/lab.sh grade" Y NO "lab_grade" (Fase 5):
#    La corrección se lanza como proceso aparte por dos
#    motivos: (1) aislamiento — grade hace reset_exam_state y
#    su exit mataría el flujo de la batería; (2) realismo —
#    se prueba EXACTAMENTE lo que ejecutaría el alumno.
#
#  DETALLE ANTI-TRAMPAS (Fase 5): el test NO arranca el
#    cronómetro (no escribe exam_status.yml). No es un olvido:
#    el anti-trampas de grade.sh solo aplica si existen sellos
#    de tiempo; sin ellos, corrige en modo libre. Así la
#    batería corrige sin esperar N minutos de reloj.
# ============================================================

# Contadores globales del módulo: las aserciones los suben y
# el resumen final los lee. Globales a propósito — algo tan
# simple no merece namerefs.
PASS_COUNT=0
FAIL_COUNT=0

# ------------------------------------------------------------
# Helper de aserciones: busca 'expected' dentro de 'actual'
# ------------------------------------------------------------
# PATRÓN COMÚN A TODAS LAS PRUEBAS: "contiene", no "igualdad
# exacta". Los comandos devuelven salidas con ruido variable
# (versiones, timestamps, anchos de columna); exigir el
# fragmento clave es robusto donde la igualdad exacta rompería
# con cualquier actualización menor.
#    $1 = nombre legible de la prueba (sale en el informe)
#    $2 = fragmento que DEBE aparecer en la salida real
#    $3 = salida real capturada del sistema
# Notita: ((N++)) devuelve estatus 1 cuando N valía 0; da
# igual aquí porque lab.sh no usa set -e, pero es el clásico
# gotcha si algún día se añade.
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
    # El laboratorio debe estar levantado: si no, cada docker
    # exec fallará en cadena y las 5 fases harían ruido sin
    # valor diagnóstico.
    require_control_running

    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       RHCE LAB - TEST SUITE v1.1       ${NC}"
    echo -e "${CYAN}========================================${NC}"

    # ========================================================
    # FASE 1 :: Infraestructura y Sistema Operativo
    # ========================================================
    # Sin systemd vivo como PID 1 nada de lo demás importa:
    # estos contenedores son "máquinas RHEL completas", no
    # simples procesos. sshd y firewalld son la base que todo
    # examen asume presente.
    #   - PID 1:     /proc/1/comm = nombre del proceso 1.
    #   - sshd:      is-active prueba el SERVICIO, no el puerto.
    #   - firewalld: is-enabled (no is-active) porque en modo
    #     contenedor basta el enlace de arranque: la unidad
    #     queda "enabled" aunque systemd aún no la haya
    #     levantado en ese instante (de ahí "modo offline").
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
    # La automatización depende de DOS cimientos: que control
    # tenga el inventario en su entorno (lo inyecta el
    # bootstrap) y que la clave SSH funcione SIN contraseña ni
    # interacción. BatchMode la vuelve no-interactiva: si
    # pidiera contraseña, FALLA en vez de quedarse colgado.
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
    # Comprobación de versión PUNTUAL: el RHCE se examina (y
    # este lab se ha construido) contra ansible-core 2.16.
    # Otra versión no es "también válida": es otro entorno.
    # ========================================================
    echo -e "\n${YELLOW}[+] Fase 3: Motor de Automatización${NC}"

    local ansible_ver; ansible_ver=$(docker exec control ansible --version 2>/dev/null | head -n 1)
    _assert_contains "Versión Ansible Core 2.16" "ansible [core 2.16" "$ansible_ver"

    # ========================================================
    # FASE 4 :: Ejecución real de Playbooks (flujo RHEL)
    # ========================================================
    # Ya no inspeccionamos configuración: EJECUTAMOS el
    # playbook maestro, con salida en vivo (tee a un temporal
    # para asertar después sin perder lo visible). El estatus
    # del pipeline es el de tee, no el de ansible: por eso se
    # aserta sobre el RESUMEN del playbook, no sobre $?.
    # Y luego se confirman los EFECTOS reales en node1:
    # httpd instalado (RPM) y corriendo (systemd). Estado,
    # no promesas del playbook.
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

    # ARREGLO HISTÓRICO: antes se afirmaba "ok=5" (hardcodeado
    # al número de tareas de site.yml -> reventaba al haber
    # solo 4). Ahora solo se exige CERO fallos: robusto ante
    # cualquier cambio futuro del playbook.
    _assert_contains "Playbook site.yml sin fallos" "failed=0" "$playbook_out"

    local rpm_httpd; rpm_httpd=$(docker exec node1 rpm -q httpd 2>/dev/null | head -c 4)
    _assert_contains "httpd instalado via RPM" "http" "$rpm_httpd"

    local httpd_status; httpd_status=$(docker exec node1 systemctl is-active httpd 2>/dev/null)
    _assert_contains "httpd activo via Systemd" "active" "$httpd_status"

    # ========================================================
    # FASE 5 :: Motor de exámenes (carga -> resuelve -> corrige)
    # ========================================================
    # Prueba el circuito COMPLETO del examen en modo forzado:
    #   1. instala el examen 001 como activo (copiarlo a
    #      CURRENT_EXAM_FILE es justo lo que hace lab_exam
    #      con un escenario estático),
    #   2. ejecuta su SOLUCIÓN (el playbook resuelto existe en
    #      el control para esto),
    #   3. llama a ./lab.sh grade como haría el alumno: la
    #      corrección debe encontrar todos los checks en OK y
    #      cantar el APROBADO.
    # Si esta fase pasa, el motor completo (parser -> plugins
    # -> veredicto) está sano de extremo a extremo.
    # NOTA: grade termina con reset_exam_state, así que deja
    # el state/ limpio y la batería es repetible.
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
    # Con fallos: exit 1 — el shell entero (lab.sh test debe
    # ser "ruidosamente" no-cero para un humano o para CI).
    # Sin fallos: el "[ ] && exit 1" deja estatus 1 por ser su
    # condición falsa; el return 0 explícito de abajo SOSTIENE
    # el contrato documentado (0 = todo OK). Es la única
    # línea funcional añadida en la pasada de documentación.
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
    return 0
}
