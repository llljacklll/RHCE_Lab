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
        if generate_random_exam "$1" "${2:-mixed}"; then
            # FIX B2 (bug webui #2): un examen nuevo nace SIN cronómetro.
            # Antes 'generate' no tocaba exam_status.yml y un timer viejo
            # (running o expired) sobrevivía al examen nuevo: el reloj
            # seguía "por donde iba" y un expired viejo bloqueaba el
            # grade del examen nuevo indefinidamente. Ahora se mata el
            # cronómetro anterior y se limpia el estado; sin fichero de
            # estado, grade.sh corrige en modo práctica libre hasta un
            # --start explícito (semántica ya documentada en grade.sh).
            _stop_timer
            rm -f "$EXAM_STATUS_FILE"
            echo ""
            echo -e "${YELLOW}=========================================${NC}"
            echo -e "${CYAN}[!] Examen guardado en: state/current_exam.yml${NC}"
            echo -e "${CYAN}[!] Cronómetro anterior detenido y estado limpiado.${NC}"
            echo -e "${CYAN}[!] Para comenzar el examen y el cronómetro:${NC}"
            echo -e "${GREEN}    ./lab.sh exam --start${NC}"
            echo -e "${YELLOW}=========================================${NC}"
        fi
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

    # ---------- V-2 (14C-b): guardianes antes del parseo ----------
    # Si el parseo de abajo muere (PyYAML ausente o YAML corrupto),
    # py_out llega vacio y el 'read' reparte tres cadenas vacias:
    # el heredoc de exam_status.yml (unas lineas mas abajo) escribiria
    # un status "running" medio arrancado y sin cronometro. Dos
    # cortes LIMPIOS antes de tocar estado:
    #   1. require_pyyaml: python3 + PyYAML presentes, con mensaje
    #      accionable en vez de traceback.
    #   2. pre-flight: YAML parseable, NO vacio y raiz mapping
    #      (dictamen #8: una lista/escalar pasaria safe_load y romperia
    #      d.get mas abajo -> half-start). Cubre
    #      el caso --start y el residuo vacio que deja un --random
    #      fallido (el [ -f ] de --start acepta ficheros vacios).
    require_pyyaml "exam"
    if ! python3 -c "import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); sys.exit(0 if isinstance(d,dict) and d else 1)" "$CURRENT_EXAM_FILE" >/dev/null 2>&1; then
        echo -e "${RED}Error: $CURRENT_EXAM_FILE no es YAML valido (o vacio); no se inicia el examen.${NC}"
        echo -e "${YELLOW}       Vuelve a generarlo: ./lab.sh exam --random${NC}"
        exit 1
    fi

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

    # ---------- FIX B3: no reiniciar un cronómetro en marcha ----------
    # 'exam --start' era reiniciable en silencio: un segundo arranque
    # sobreescribía start_time y el reloj volvía a cero sin aviso (era
    # el doble clic accidental de la web). Se rechaza mientras exista
    # un examen corriendo; 'expired' SÍ permite reiniciar (vía de
    # recuperación natural, verificada en el repro del propietario).
    if [ -f "$EXAM_STATUS_FILE" ]; then
        local st s_start s_limit elapsed
        st=$(grep "^status:" "$EXAM_STATUS_FILE" | awk '{print $2}')
        if [ "$st" = "running" ]; then
            s_start=$(grep "^start_time:" "$EXAM_STATUS_FILE" | awk '{print $2}')
            s_limit=$(grep "^time_limit:" "$EXAM_STATUS_FILE" | awk '{print $2}')
            elapsed=0
            if [[ "$s_start" =~ ^[0-9]+$ ]]; then
                elapsed=$(( ($(date +%s) - s_start) / 60 ))
            fi
            echo -e "${RED}Error: ya hay un examen en marcha (lleva ${elapsed} min de ${s_limit:-?}).${NC}"
            echo -e "${YELLOW}       Corrígelo con ./lab.sh grade o espera a que expire antes de iniciar otro.${NC}"
            exit 1
        fi
    fi

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
# _stop_timer → mata el cronómetro en background si sigue vivo
#   Única fuente de verdad de la limpieza del timer. La usa
#   _start_timer (solo puede haber un cronómetro) y, desde el
#   FIX B2, también el --random: un examen nuevo nace sin reloj.
# ------------------------------------------------------------
function _stop_timer() {
    if [ -f "$TIMER_PID_FILE" ]; then
        # hijos primero (sleep del timer anterior), luego el padre:
        # el kill del padre deja el sleep como huerfano
        pkill -P "$(cat "$TIMER_PID_FILE")" 2>/dev/null || true
        kill "$(cat "$TIMER_PID_FILE")" 2>/dev/null || true
        rm -f "$TIMER_PID_FILE"
    fi
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
    _stop_timer

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
