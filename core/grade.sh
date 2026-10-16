#!/bin/bash
# ============================================================
#  🎓 RHCE LAB — MOTOR DE CORRECCIÓN  (./lab.sh grade)
# ------------------------------------------------------------
#  RESPONSABILIDADES:
#    1. ANTI-TRAMPAS: verifica el cronómetro (exam_status.yml).
#       Si el tiempo expiró → bloquea la corrección y aborta.
#    2. PARSEO: lee el YAML del examen línea a línea y extrae
#       los 'checks' (task_id / type / name / path / contains).
#    3. EJECUCIÓN: delega cada check a su plugin en
#       core/checkers/check_<type>.sh contra TODOS los nodos.
#    4. PERSISTENCIA: guarda un log limpio (sin colores) en
#       state/results/ con la traza de aciertos y fallos.
#    5. LIMPIEZA: resetea el estado del examen al terminar.
# ============================================================

# ------------------------------------------------------------
# Punto de entrada (la invoca lab.sh)
# ------------------------------------------------------------
function lab_grade() {
    local exam_file
    exam_file=$(_resolve_exam_file)
    require_control_running

    # ========================================================
    # 1) ANTI-TRAMPAS :: verificación del cronómetro
    # ========================================================
    echo -e "${CYAN}[+] Verificando estado del examen...${NC}"
    if [ -f "$EXAM_STATUS_FILE" ]; then
        local status start_time time_limit current_time elapsed
        elapsed=0

        # -- Parseo del fichero de estado (clave: valor) --
        status=$(grep     "^status:"     "$EXAM_STATUS_FILE" | awk '{print $2}')
        start_time=$(grep "^start_time:" "$EXAM_STATUS_FILE" | awk '{print $2}')
        time_limit=$(grep "^time_limit:" "$EXAM_STATUS_FILE" | awk '{print $2}')
        current_time=$(date +%s)

        # -- Caso A: ya estaba marcado como expirado --
        if [ "$status" = "expired" ]; then
            _print_expired_error "$time_limit"; exit 1
        fi

        # -- Caso B: comprobar sobre la marcha si se pasó --
        if [[ "$start_time" =~ ^[0-9]+$ ]] && [[ "$time_limit" =~ ^[0-9]+$ ]]; then
            elapsed=$(( (current_time - start_time) / 60 ))
            if [ "$elapsed" -gt "$time_limit" ]; then
                # Se marca expired para bloquear intentos futuros
                sed -i 's/status: running/status: expired/' "$EXAM_STATUS_FILE"
                _print_expired_error "$time_limit"; exit 1
            fi
        fi
        echo -e "${GREEN}[+] Estado OK (Tiempo transcurrido: ${elapsed} min de ${time_limit} permitidos)${NC}"
    else
        echo -e "${YELLOW}[!] Advertencia: No se encuentra el estado del examen. Se permite la corrección.${NC}"
    fi

    # ========================================================
    # 2) EJECUCIÓN de todos los checks del examen
    # ========================================================
    echo "-----------------------------------"
    local total=0
    local passed=0
    local tmp_out
    tmp_out=$(mktemp)

    _parse_and_check_exam "$exam_file" total passed > "$tmp_out"

    # ========================================================
    # 🔧 FIX BUG 3 :: ANTI-FALSO-APROBADO
    # Si no se parseó ningún check, el YAML del examen está
    # corrupto o vacío → abortar. Sin esto, 0/0 evalúa como
    # "APROBADO" porque passed == total (0 == 0).
    # ========================================================
    if [ "$total" -eq 0 ]; then
        echo -e "${RED}[-] ERROR CRÍTICO: 0 checks parseados. El YAML del examen está corrupto o vacío.${NC}"
        rm -f "$tmp_out"
        exit 1
    fi

    # ========================================================
    # 3) RESULTADO + PERSISTENCIA + LIMPIEZA
    # ========================================================
    cat "$tmp_out"
    echo "-----------------------------------"
    _print_grade_result "$passed" "$total"
    _save_results "$exam_file" "$tmp_out" "$passed" "$total"
    rm -f "$tmp_out"

    reset_exam_state
    echo -e "${CYAN}[+] Estado del examen limpiado.${NC}"
}

# ------------------------------------------------------------
# Banner de error cuando el cronómetro ha expirado
# ------------------------------------------------------------
function _print_expired_error() {
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}  ❌ EXAMEN EXPIRADO${NC}"
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED} El tiempo límite de $1 minutos ha sido superado.${NC}"
    echo -e "${RED} Simulador detenido para evitar trampas.${NC}"
    echo -e "${RED}=========================================${NC}"
}

# ------------------------------------------------------------
# Decide qué examen corregir:
#   a) Si lab.sh recibió un escenario como argumento → ese
#   b) Si no, el examen activo (state/current_exam.yml)
# ------------------------------------------------------------
function _resolve_exam_file() {
    if [ -n "$PLAYBOOK_FILE" ]; then
        local file="$SCENARIOS_DIR/${PLAYBOOK_FILE}"
        require_file_exists "$file" "No se encontró $file"
        echo "$file"
    elif [ -f "$CURRENT_EXAM_FILE" ]; then
        echo "$CURRENT_EXAM_FILE"
    else
        echo -e "${RED}Error: No hay examen activo.${NC}" >&2
        exit 1
    fi
}

# ------------------------------------------------------------
# Parser línea a línea del YAML + ejecución de checks
#   $1 = fichero de examen
#   $2 = nameref del contador total
#   $3 = nameref del contador de aprobados
# ------------------------------------------------------------
function _parse_and_check_exam() {
    local exam_file="$1"
    local -n ref_total="$2"
    local -n ref_passed="$3"

    local task_id="" check_type="" check_name="" check_path=""

    while IFS= read -r line; do
        # -- Normaliza espacios de inicio de línea --
        line=$(echo "$line" | sed 's/^[[:space:]]*//')

        # -- Nueva entrada de check ("- task_id: ...") --
        #    Primero ejecuta el check ANTERIOR acumulado.
        if [[ $line =~ ^-.*task_id:[[:space:]]*(.*) ]]; then
            if [[ -n "$task_id" && -n "$check_type" && -n "$check_name" ]]; then
                if _run_check "$task_id" "$check_type" "$check_name" "$check_path"; then
                    echo -e "  [${GREEN}PASS${NC}] $task_id (${check_type}: $check_name)"
                    ref_passed=$((ref_passed + 1))
                else
                    echo -e "  [${RED}FAIL${NC}] $task_id (${check_type}: $check_name)"
                fi
                ref_total=$((ref_total + 1))
            fi
            # -- Reset de acumuladores para el nuevo check --
            task_id=""; check_type=""; check_name=""; check_path=""
            task_id=$(echo "${BASH_REMATCH[1]}" | xargs)

        elif [[ $line =~ ^type:[[:space:]]*(.*) ]]; then
            check_type=$(echo "${BASH_REMATCH[1]}" | xargs)

        elif [[ $line =~ ^name:[[:space:]]*(.*) ]]; then
            check_name=$(echo "${BASH_REMATCH[1]}" | xargs)

        elif [[ $line =~ ^path:[[:space:]]*(.*) ]]; then
            check_path=$(echo "${BASH_REMATCH[1]}" | xargs)

        elif [[ $line =~ ^contains:[[:space:]]*(.*) ]]; then
            # En los checks tipo 'file', 'contains' viaja en la
            # posición de 'name' (patrón a buscar dentro del fichero)
            check_name=$(echo "${BASH_REMATCH[1]}" | xargs)
        fi
    done < "$exam_file"

    # -- El ÚLTIMO check no tiene sucesor: se ejecuta al salir --
    if [[ -n "$task_id" && -n "$check_type" && -n "$check_name" ]]; then
        if _run_check "$task_id" "$check_type" "$check_name" "$check_path"; then
            echo -e "  [${GREEN}PASS${NC}] $task_id (${check_type}: $check_name)"
            ref_passed=$((ref_passed + 1))
        else
            echo -e "  [${RED}FAIL${NC}] $task_id (${check_type}: $check_name)"
        fi
        ref_total=$((ref_total + 1))
    fi
}

# ------------------------------------------------------------
# Ejecuta un check contra TODOS los nodos (node1 Y node2 Y node3)
#   $1 = task_id (informativo)   $2 = tipo → check_<tipo>.sh
#   $3 = name (paquete/usuario/servicio/patrón/LV...)
#   $4 = path (ruta de fichero o usuario del cron)
# ------------------------------------------------------------
function _run_check() {
    local task_id="$1" check_type="$2" check_name="$3" check_path="$4"
    local all_ok=true

    # -- ¿Existe el plugin de corrección? --
    if [ ! -f "$CHECKERS_DIR/check_${check_type}.sh" ]; then
        echo -e "  [${YELLOW}WARN${NC}] $task_id (Checker desconocido: $check_type)"
        return 1
    fi

    # -- Ejecución en cada nodo (source del plugin) --
    for node in "${LAB_NODES[@]}"; do
        local result
        result=$(source "$CHECKERS_DIR/check_${check_type}.sh" "$node" "$check_name" "$check_path")
        if [ "$result" != "OK" ]; then
            all_ok=false
            break              # Con un fallo basta: no iterar más
        fi
    done

    $all_ok                    # 'true'/'false' como exit status
}

# ------------------------------------------------------------
# Resumen final del examen
# ------------------------------------------------------------
function _print_grade_result() {
    local passed="$1"; local total="$2"
    echo -e "Resultado Final: ${passed}/${total}"
    if [ "$passed" -eq "$total" ]; then
        echo -e "${GREEN}¡ENHORABUENA, EXAMEN APROBADO!${NC}"
    else
        echo -e "${RED}Examen suspendido. Revisa los puntos fallidos.${NC}"
    fi
}

# ------------------------------------------------------------
# Persistencia del resultado en state/results/<timestamp>.log
# Se limpian los códigos de color ANSI para que el log sea
# legible en cualquier editor (sed elimina las secuencias ESC).
# ------------------------------------------------------------
function _save_results() {
    local exam_file="$1" output_file="$2" passed="$3" total="$4"
    ensure_state_dir

    local timestamp; timestamp=$(date '+%Y%m%d_%H%M%S')
    local log_file="$RESULTS_DIR/exam_${timestamp}.log"
    local exam_id;  exam_id=$(basename "$exam_file")

    {
        echo "======================================"
        echo "RHCE LAB - RESULTADO DE EXAMEN"
        echo "======================================"
        echo "Fecha : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Examen: $exam_id"
        echo "Nota  : ${passed}/${total}"
        echo "Estado: $([ "$passed" -eq "$total" ] && echo "APROBADO" || echo "SUSPENDIDO")"
        echo "======================================"
        echo ""
        # -- Strip de códigos de color ANSI (ESC[...m) --
        sed 's/\x1b\[[0-9;]*m//g' "$output_file"
        echo ""
    } > "$log_file"

    echo -e "${CYAN}[+] Resultados guardados en: ${log_file}${NC}"
}
