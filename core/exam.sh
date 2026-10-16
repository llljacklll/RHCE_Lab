#!/bin/bash
# ==========================================
# Gestión de exámenes (v5 - Estado y Timer)
# ==========================================
function lab_exam() {
    ensure_state_dir
    local mode="$1"
    if [ -z "$mode" ]; then _list_available_exams; return; fi

    if [ "$mode" = "--random" ]; then
        shift
        generate_random_exam "$1"
        echo ""; echo -e "${YELLOW}=========================================${NC}"
        echo -e "${CYAN}[!] Examen guardado en: state/curren
        echo -e "${CYAN}[!] Para comenzar el examen y el cronómetro:${NC}"
        echo -e "${GREEN}    ./lab.sh exam --start${NC}"
        echo -e "${YELLOW}=========================================${NC}"
        return
    fi

    if [ "$mode" = "--start" ]; then
        if [ ! -f "$CURRENT_EXAM_FILE" ]; then echo -e "${RED}Error: No hay examen activo.${NC}"; exit 1; fi
    else
        local exam_path="$SCENARIOS_DIR/$mode"
        require_file_exists "$exam_path" "No se encontró el examen"
        cp "$exam_path" "$CURRENT_EXAM_FILE"
    fi

    require_control_running
    local py_out
    py_out=$(python3 << PYEOF
import yaml
with open("$CURRENT_EXAM_FILE") as f: d = yaml.safe_load(f)
print(f"{d.get('difficulty','unknown')}|{d.get('title','Sin título')}|{d.get('time_limit',0)}")
PYEOF
)
    local difficulty title time_limit
    IFS='|' read -r difficulty title time_limit <<< "$py_out"

    local start_time=$(date +%s)
    cat > "$EXAM_STATUS_FILE" << STATUSEOF
status: running
start_time: $start_time
time_limit: $time_limit
STATUSEOF

    clear; print_banner; _print_exam_header "$difficulty" "$time_limit" "$title"; _print_exam_tasks "$CURRENT_EXAM_FILE"; _print_exam_instructions "$1"
    if [[ "$time_limit" =~ ^[0-9]+$ ]] && [ "$time_limit" -gt 0 ]; then _start_timer "$time_limit"; fi
}

function _list_available_exams() {
    echo -e "${CYAN}[+] Exámenes disponibles:${NC}"; find "$SCENARIOS_DIR" -name "*.yml" -type f ! -name "task_pool.yml" | sed "s|$SCENARIOS_DIR/||"
    echo ""; echo -e "${CYAN}[+] Comandos de examen:${NC}"
    echo "  ./lab.sh exam --random [numero_tareas]  (Genera y guarda)"
    echo "  ./lab.sh exam --start                   (Muestra y arranca cronómetro)"
    echo "  ./lab.sh exam easy/exam_001.yml          (Carga estática directamente)"
}

function _print_exam_header() { echo -e "${YELLOW}=========================================${NC}"; echo -e "${RED}   RHCE PRACTICE EXAM${NC}"; echo 
function _print_exam_tasks() { python3 << PYEOF2; import yaml; exec("with open(\"$1\") as f:\n d=yaml.safe_load(f)\nfor t in d.get(\"tasks\", []):\n print(\"  *\", t.get(\"description\"))"); PYEOF2; }
function _print_exam_instructions() { local exam_arg="

function _start_timer() {
    local minutes=$1
    reset_exam_state 2>/dev/null
    ( sleep $((minutes * 60)); if [ -f "$EXAM_STATUS_FILE" ]; then sed -i 's/status: running/sta

    echo -e "${GREEN}[+] Examen iniciado. ¡A trabajar!${NC}"
}
