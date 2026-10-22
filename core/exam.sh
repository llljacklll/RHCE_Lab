#!/bin/bash
# ============================================================
#  core/exam.sh — flujo de exámenes y cronómetro anti-trampas
# ============================================================
#  RESPONSABILIDAD:
#    Orquestar el flujo COMPLETO del examen de cara al alumno:
#    listar lo que hay, cargarlo en state/, mostrarlo en
#    pantalla y arrancar el cronómetro que lo limita.
#
#  FLUJO DE lab_exam (según el primer argumento):
#    (vacío)             → lista los exámenes disponibles
#    --random [N] [dif]  → genera examen aleatorio y lo GUARDA,
#                          pero NO arranca nada: el reloj no
#                          corre hasta --start. POR QUÉ en dos
#                          pasos: "generar" no es "empezar";
#                          puedes regenerar hasta que te guste
#                          la mezcla sin gastar tiempo de reloj.
#    --start             → reanuda el examen generado: lo
#                          muestra y arranca el cronómetro.
#    easy/exam_001.yml   → estático: lo copia de scenarios/
#                          y lo arranca directamente.
#
#  ESTADO DE UN EXAMEN (todo bajo state/, regenerable):
#    current_exam.yml . el examen ACTIVO (grade.sh lo lee
#                      para saber qué corregir)
#    exam_status.yml .. status: running|expired + start_time
#                      + time_limit. Es LA fuente de verdad
#                      anti-trampas: aunque el cronómetro muera
#                      (reboot, kill), grade.sh re-computa el
#                      tiempo transcurrido desde estos sellos.
#    timer.pid ........ PID del cronómetro en background;
#                      reset_exam_state (utils.sh) lo usa para
#                      matarlo en 'down' y en 'grade'.
#
#  DOBLE BARRERA ANTI-TRAMPAS (defensa en profundidad):
#    1. El cronómetro (_start_timer): subshell en background
#       que, al expirar, invierte status: running → expired.
#    2. grade.sh: re-computa el transcurrido desde los sellos
#       de exam_status.yml y bloquea si se pasó.
#    Ninguna depende de la otra: matar el cronómetro no
#    regala ni un minuto extra.
# ============================================================

function lab_exam() {
    # state/ es prerrequisito de todo lo que sigue (allí viven
    # current_exam.yml y exam_status.yml).
    ensure_state_dir
    local mode="$1"

    # ---------- Sin argumentos: listar exámenes ----------
    if [ -z "$mode" ]; then
        _list_available_exams
        return
    fi

    # ---------- --random [N] [dif]: generar y guardar ----------
    # Dos fases a propósito: generar NO toca el estado de
    # cronómetro (solo escribe current_exam.yml).
    if [ "$mode" = "--random" ]; then
        shift
        # Tras el shift, $1/$2 son los argumentos de --random
        # (número y/o dificultad, en cualquier orden: el swap
        # lo hace generate_random_exam).
        generate_random_exam "$1" "${2:-mixed}"
        echo ""
        echo -e "${YELLOW}=========================================${NC}"
        echo -e "${CYAN}[!] Examen guardado en: state/current_exam.yml${NC}"
        echo -e "${CYAN}[!] Para comenzar el examen y el cronómetro:${NC}"
        echo -e "${GREEN}    ./lab.sh exam --start${NC}"
        echo -e "${YELLOW}=========================================${NC}"
        return
    fi

    # ---------- --start: reanudar el examen generado ----------
    # Reutiliza current_exam.yml; si no existe es que no se
    # hizo --random antes (o el estado lo limpió un down/grade).
    if [ "$mode" = "--start" ]; then
        if [ ! -f "$CURRENT_EXAM_FILE" ]; then
            echo -e "${RED}Error: No hay examen activo.${NC}"
            exit 1
        fi
    else
        # ---------- estático: copiar desde scenarios/ ----------
        # $mode trae la ruta RELATIVA a scenarios/
        # ("easy/exam_001.yml"). Se COPIA (no se referencia):
        # a partir de aquí state/current_exam.yml es el punto
        # único de verdad aunque el original cambie después.
        local exam_path="$SCENARIOS_DIR/$mode"
        require_file_exists "$exam_path" "No se encontró el examen"
        cp "$exam_path" "$CURRENT_EXAM_FILE"
    fi

    # Empezar un examen implica ejecutar playbooks contra los
    # nodos: sin el lab levantado no tiene sentido seguir.
    require_control_running

    # ---------- Parsear metadatos (difficulty|title|tiempo) ----------
    # Python (PyYAML) extrae los tres campos y los devuelve
    # SEPARADOS POR | en una sola línea: una sola llamada
    # en vez de tres greps (el YAML tiene estructura anidada
    # y safe_load es más fiable que parsearlo a mano).
    # El heredoc va SIN comillas → $CURRENT_EXAM_FILE expande
    # en bash antes de entrar en Python.
    local py_out
    py_out=$(python3 << PYEOF
import yaml
with open("$CURRENT_EXAM_FILE") as f: d = yaml.safe_load(f)
print(f"{d.get('difficulty','unknown')}|{d.get('title','Sin título')}|{d.get('time_limit',0)}")
PYEOF
)
    # IFS='|' + read: reparte la línea en las tres variables.
    # El here-string <<< evita consumir el stdin del script
    # (un pipe lo cerraría para futuros comandos).
    local difficulty title time_limit
    IFS='|' read -r difficulty title time_limit <<< "$py_out"

    # ---------- Escribir el estado (arranca el reloj lógico) ----------
    # date +%s = epoch en segundos: robusto ante reboots y
    # cambios de hora. Este fichero es en quien confía grade.
    local start_time
    start_time=$(date +%s)
    cat > "$EXAM_STATUS_FILE" << STATUSEOF
status: running
start_time: $start_time
time_limit: $time_limit
STATUSEOF

    # ---------- Mostrar el examen por pantalla ----------
    # clear -x limpia SIN borrar el scrollback (la salida
    # previa de la sesión sigue accesible hacia arriba).
    clear -x
    print_banner
    _print_exam_header "$difficulty" "$time_limit" "$title"
    _print_exam_tasks "$CURRENT_EXAM_FILE"
    _print_exam_instructions "$mode"

    # ---------- Lanzar cronómetro en segundo plano ----------
    # Solo si time_limit es numérico > 0: un examen sin
    # tiempo es práctica libre (sin reloj, y grade tampoco
    # bloqueará porque elapsed nunca supera a 0).
    if [[ "$time_limit" =~ ^[0-9]+$ ]] && [ "$time_limit" -gt 0 ]; then
        _start_timer "$time_limit"
    fi
}

# ------------------------------------------------------------
# _list_available_exams → menú de exámenes y comandos
# El find excluye task_pool.yml: el BANCO de tareas no es un
# examen (es la materia prima de los aleatorios). El sed
# recorta el prefijo para mostrar "easy/exam_001.yml", el
# formato exacto que lab_exam acepta como argumento.
# ------------------------------------------------------------
function _list_available_exams() {
    echo -e "${CYAN}[+] Exámenes disponibles:${NC}"
    find "$SCENARIOS_DIR" -name "*.yml" -type f ! -name "task_pool.yml" \
        | sed "s|$SCENARIOS_DIR/||"
    echo ""
    echo -e "${CYAN}[+] Comandos de examen:${NC}"
    echo "  ./lab.sh exam --random [N] [easy|medium|hard|mixed]  (Genera y guarda)"
    echo "  ./lab.sh exam --start                   (Muestra y arranca cronómetro)"
    echo "  ./lab.sh exam easy/exam_001.yml          (Carga estática directamente)"
}

# ------------------------------------------------------------
# _print_exam_header <dificultad> <minutos> <título>
# Puramente cosmético: la "portada" del examen. $1/$2/$3
# respetan el orden de la llamada de lab_exam.
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
# Lee el examen con PyYAML e imprime cada descripción.
# `or ""` blinda contra una description ausente; rstrip()
# quita blancos finales para que la lista salga pareja.
# Heredoc sin comillas → $1 expande en bash (la ruta).
# ------------------------------------------------------------
function _print_exam_tasks() {
    echo -e "${CYAN}TAREAS:${NC}"
    python3 << PYEOF2
import yaml
with open("$1") as f: d = yaml.safe_load(f)
for t in d.get("tasks", []):
    print("  *", str(t.get("description") or "").rstrip())
PYEOF2
}

# ------------------------------------------------------------
# _print_exam_instructions <modo> → cómo trabajar el examen
# La línea "Atascado?" apunta a soluciones/<task_id>.yml:
# la solución de referencia existe para cada tarea, pero
# consultarla es ya autoevaluación, no práctica. El $1 (el
# modo) no se usa dentro: es un gancho para futuras
# variantes (p.ej. más instrucciones en los aleatorios).
# ------------------------------------------------------------
function _print_exam_instructions() {
    echo -e "${CYAN}INSTRUCCIONES:${NC}"
    echo "  1. Escribe tu playbook en ansible/playbooks/ (ej: mi_solucion.yml)"
    echo "  2. Ejecútalo:   ./lab.sh run mi_solucion.yml"
    echo "     Con vault:   ./lab.sh run --vault mi_solucion.yml"
    echo "  3. Corrige con: ./lab.sh grade"
    echo "  Atascado? Solución de referencia: soluciones/<task_id>.yml"
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
#   HISTORIA (bug corregido): una versión anterior llamaba aquí
#   a reset_exam_state, que BORRABA el examen y el estado
#   recién escritos (grade moriría con "No hay examen
#   activo"). Ahora solo se mata el cronómetro ANTERIOR, si
#   existiera, sin tocar el estado.
#
#   POR QUÉ una subshell & y no cron/at: no necesita root ni
#   persistencia — su única misión es voltear un flag tras N
#   minutos. Sobrevive al exit de lab.sh (bash no manda
#   SIGHUP a los hijos de un script), pero NO a un reboot de
#   la máquina: por eso grade re-verifica con los sellos.
# ------------------------------------------------------------
function _start_timer() {
    local minutes="$1"

    # Mata un cronómetro anterior si sigue vivo: solo puede
    # haber uno; ocurre si se arranca un segundo examen sin
    # pasar por down/grade entre medias.
    if [ -f "$TIMER_PID_FILE" ]; then
        kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null
        rm -f "$TIMER_PID_FILE"
    fi

    # Subshell en background: duerme todo el examen y, al
    # despertar, invierte status: running → expired. Si el
    # fichero ya no existe (examen limpiado), no hace nada y
    # muere en silencio.
    (
        sleep $((minutes * 60))
        if [ -f "$EXAM_STATUS_FILE" ]; then
            sed -i 's/status: running/status: expired/' "$EXAM_STATUS_FILE"
        fi
    ) &
    # $! = PID del último proceso lanzado en background (la
    # subshell). Se guarda para poder matarlo sin rastrear ps.
    echo $! > "$TIMER_PID_FILE"

    echo -e "${GREEN}[+] Cronómetro iniciado: ${minutes} minutos.${NC}"
    echo -e "${GREEN}[+] Examen iniciado. ¡A trabajar!${NC}"
}
