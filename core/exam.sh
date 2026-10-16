#!/bin/bash
# ============================================================
#  📝 CORE/EXAM.SH — Flujo de exámenes y cronómetro
# ============================================================
#  RESPONSABILIDAD:
#    - Listar los exámenes disponibles (scenarios/)
#    - Cargar un examen (estático o aleatorio) en state/
#    - Mostrar el examen al alumno por pantalla
#    - Arrancar el cronómetro anti-trampas en background
#
#  FLUJO DE lab_exam (según el primer argumento):
#    (vacío)             → lista de exámenes disponibles
#    --random [N]        → genera examen aleatorio y lo guarda
#                          (NO arranca cronómetro todavía)
#    --start             → muestra el examen generado y arranca
#                          el cronómetro
#    easy/exam_001.yml   → carga un examen estático y arranca
#                          el cronómetro directamente
#
#  ESTADO DEL EXAMEN (state/):
#    current_exam.yml → examen activo (lo lee grade.sh)
#    exam_status.yml  → status: running|expired + tiempos
#    timer.pid        → PID del cronómetro en segundo plano
# ============================================================

function lab_exam() {
    ensure_state_dir
    local mode="$1"

    # ---------- Sin argumentos: listar exámenes ----------
    if [ -z "$mode" ]; then
        _list_available_exams
        return
    fi

    # ---------- --random [N]: generar y guardar ----------
    if [ "$mode" = "--random" ]; then
        shift
        generate_random_exam "$1"
        echo ""
        echo -e "${YELLOW}=========================================${NC}"
        echo -e "${CYAN}[!] Examen guardado en: state/current_exam.yml${NC}"
        echo -e "${CYAN}[!] Para comenzar el examen y el cronómetro:${NC}"
        echo -e "${GREEN}    ./lab.sh exam --start${NC}"
        echo -e "${YELLOW}=========================================${NC}"
        return
    fi

    # ---------- --start: reanudar el examen generado ----------
    if [ "$mode" = "--start" ]; then
        if [ ! -f "$CURRENT_EXAM_FILE" ]; then
            echo -e "${RED}Error: No hay examen activo.${NC}"
            exit 1
        fi
    else
        # ---------- estático: copiar desde scenarios/ ----------
        local exam_path="$SCENARIOS_DIR/$mode"
        require_file_exists "$exam_path" "No se encontró el examen"
        cp "$exam_path" "$CURRENT_EXAM_FILE"
    fi

    require_control_running

    # ---------- Parsear metadatos (difficulty|title|tiempo) ----------
    local py_out
    py_out=$(python3 << PYEOF
import yaml
with open("$CURRENT_EXAM_FILE") as f: d = yaml.safe_load(f)
print(f"{d.get('difficulty','unknown')}|{d.get('title','Sin título')}|{d.get('time_limit',0)}")
PYEOF
)
    local difficulty title time_limit
    IFS='|' read -r difficulty title time_limit <<< "$py_out"

    # ---------- Escribir el estado (arranca el reloj lógico) ----------
    local start_time
    start_time=$(date +%s)
    cat > "$EXAM_STATUS_FILE" << STATUSEOF
status: running
start_time: $start_time
time_limit: $time_limit
STATUSEOF

    # ---------- Mostrar el examen por pantalla ----------
    clear
    print_banner
    _print_exam_header "$difficulty" "$time_limit" "$title"
    _print_exam_tasks "$CURRENT_EXAM_FILE"
    _print_exam_instructions "$mode"

    # ---------- Lanzar cronómetro en segundo plano ----------
    if [[ "$time_limit" =~ ^[0-9]+$ ]] && [ "$time_limit" -gt 0 ]; then
        _start_timer "$time_limit"
    fi
}

# ------------------------------------------------------------
# _list_available_exams → menú de exámenes y comandos
# ------------------------------------------------------------
function _list_available_exams() {
    echo -e "${CYAN}[+] Exámenes disponibles:${NC}"
    find "$SCENARIOS_DIR" -name "*.yml" -type f ! -name "task_pool.yml" \
        | sed "s|$SCENARIOS_DIR/||"
    echo ""
    echo -e "${CYAN}[+] Comandos de examen:${NC}"
    echo "  ./lab.sh exam --random [numero_tareas]  (Genera y guarda)"
    echo "  ./lab.sh exam --start                   (Muestra y arranca cronómetro)"
    echo "  ./lab.sh exam easy/exam_001.yml          (Carga estática directamente)"
}

# ------------------------------------------------------------
# _print_exam_header <dificultad> <minutos> <título>
# ------------------------------------------------------------
function _print_exam_header() {
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${RED}   RHCE PRACTICE EXAM${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo -e " Dificultad : $1"
    echo -e " Tiempo     : $2 minutos"
    echo -e " Título     : $3"
    echo -e "${YELLOW}=========================================${NC}"
}

# ------------------------------------------------------------
# _print_exam_tasks <fichero_yaml> → lista las tareas
# ------------------------------------------------------------
function _print_exam_tasks() {
    echo -e "${CYAN}TAREAS:${NC}"
    python3 << PYEOF2
import yaml
with open("$1") as f: d = yaml.safe_load(f)
for t in d.get("tasks", []):
    print("  *", t.get("description"))
PYEOF2
}

# ------------------------------------------------------------
# _print_exam_instructions <modo> → cómo trabajar el examen
# ------------------------------------------------------------
function _print_exam_instructions() {
    echo -e "${CYAN}INSTRUCCIONES:${NC}"
    echo "  1. Escribe tu playbook en ansible/playbooks/ (ej: mi_solucion.yml)"
    echo "  2. Ejecútalo:   ./lab.sh run mi_solucion.yml"
    echo "     Con vault:   ./lab.sh run --vault mi_solucion.yml"
    echo "  3. Corrige con: ./lab.sh grade"
    echo ""
    echo "  El cronómetro corre en segundo plano. Si el tiempo"
    echo "  expira, la corrección queda BLOQUEADA (anti-trampas)."
    echo -e "${YELLOW}=========================================${NC}"
    echo ""
}

# ------------------------------------------------------------
# _start_timer <minutos>
#   Cronómetro en background: al expirar marca el examen como
#   'expired' en exam_status.yml (grade.sh lo bloqueará).
#   Guarda su PID en timer.pid para que reset_exam_state
#   (invocado por 'down' y 'grade') pueda matarlo.
#
#   ⚠️ BUG CORREGIDO: la versión anterior llamaba aquí a
#   reset_exam_state, que BORRABA el examen y el estado recién
#   escritos (grade moriría con "No hay examen activo").
#   Ahora solo se mata el cronómetro anterior, si existiera.
# ------------------------------------------------------------
function _start_timer() {
    local minutes="$1"

    # Mata un cronómetro anterior si sigue vivo (sin tocar estado)
    if [ -f "$TIMER_PID_FILE" ]; then
        kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null
        rm -f "$TIMER_PID_FILE"
    fi

    # Subshell en background que expira el examen al agotarse
    (
        sleep $((minutes * 60))
        if [ -f "$EXAM_STATUS_FILE" ]; then
            s
        fi
    ) &
    echo $! > "$TIMER_PID_FILE"

    echo -e "${GREEN}[+] Cronómetro iniciado: ${minutes} minutos.${NC}"
    echo -e "${GREEN}[+] Examen iniciado. ¡A trabajar!${NC}"
}
