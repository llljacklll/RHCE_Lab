#!/bin/bash
# ============================================================
#  core/grade.sh — EL MOTOR DE CORRECCIÓN  (./lab.sh grade)
# ============================================================
#  RESPONSABILIDADES (en el orden en que las ejecuta
#  lab_grade):
#    1. ANTI-TRAMPAS: verifica el tiempo del examen contra
#       exam_status.yml. Si expiró → bloquea y aborta.
#    2. RESOLUCIÓN: decide QUÉ examen corregir (un escenario
#       explícito o el activo de state/).
#    3. PARSEO + EJECUCIÓN: lee el YAML línea a línea y
#       delega cada check en su plugin de
#       core/checkers/check_<tipo>.sh, contra TODOS los nodos.
#    4. RESULTADO: imprime el resumen y guarda un log SIN
#       colores en state/results/exam_<id>_<timestamp>.log.
#    5. LIMPIEZA: resetea el estado del examen (la próxima
#       corrección empieza de cero; el log sí permanece).
#
#  EL TOKEN __NODE__:
#    Los checks pueden llevar el literal __NODE__ en 'name' y
#    'path'. _run_check lo expande al nombre de CADA nodo
#    antes de invocar el plugin: así un único YAML puede
#    exigir nombres por nodo (vg_node1, vg_node2, vg_node3...)
#    sin que los checkers sepan nada del token — ellos
#    reciben siempre rutas concretas.
#
#  LA TRAMPA DEL 0/0 (anti-falso-aprobado):
#    Si el parser no encuentra ningún check (YAML corrupto o
#    vacío), passed == total == 0 y el resumen diría
#    "APROBADO". El guard explícito total==0 aborta antes de
#    mostrar un aprobado falso.
# ============================================================

# ------------------------------------------------------------
# Punto de entrada (la invoca lab.sh)
# ------------------------------------------------------------
function lab_grade() {
    local exam_file
    # QUÉ corregir: escenario explícito (si lab.sh lo trajo)
    # o el examen activo. Ver en _resolve_exam_file el detalle
    # de por qué el error va a stderr.
    exam_file=$(_resolve_exam_file)
    # _resolve_exam_file aborta por stderr desde la subshell del $(...)
    # y deja stdout VACIO: sin este guard el flujo seguiria con
    # exam_file="" hasta chocar con el anti-falso-aprobado, que
    # imprimiria "0 checks / YAML corrupto" cuando lo real es que
    # NO HAY examen activo (la verruga conocida de la bateria).
    if [ -z "$exam_file" ]; then
        exit 1
    fi
    # Los checks hacen docker exec contra los nodos: sin el
    # lab arriba no hay nada que verificar.
    require_control_running

    # ========================================================
    # 1) ANTI-TRAMPAS :: verificación del cronómetro
    #    Dos barreras redundantes (doble de exam.sh):
    #    A) el cronómetro ya marcó expired, o
    #    B) los sellos temporales dicen que se pasó.
    # ========================================================
    echo -e "${CYAN}[+] Verificando estado del examen...${NC}"
    if [ -f "$EXAM_STATUS_FILE" ]; then
        local status start_time time_limit current_time elapsed
        # elapsed=0: si los sellos no son numéricos, el
        # reporte dice "0 min" en vez de variable vacía.
        elapsed=0

        # -- Parseo del fichero de estado (clave: valor) --
        # grep "^clave:" localiza la línea; awk '{print $2}'
        # toma el segundo campo = el valor. Frágil A PROPÓSITO:
        # exam_status.yml lo escribe NOSOTROS con formato fijo.
        status=$(grep     "^status:"     "$EXAM_STATUS_FILE" | awk '{print $2}')
        start_time=$(grep "^start_time:" "$EXAM_STATUS_FILE" | awk '{print $2}')
        time_limit=$(grep "^time_limit:" "$EXAM_STATUS_FILE" | awk '{print $2}')
        current_time=$(date +%s)

        # -- Caso A: ya estaba marcado como expirado --
        # (el cronómetro de fondo llegó antes que el alumno)
        if [ "$status" = "expired" ]; then
            _print_expired_error "$time_limit"; exit 1
        fi

        # -- Caso B: comprobar sobre la marcha si se pasó --
        # Se re-computa en vez de fiarse del cronómetro: si lo
        # mataron (reboot, kill -9) el examen QUEDA bloqueado
        # igualmente. División entera → elapsed en minutos.
        # Si se pasó, se marca expired para que los próximos
        # intentos caigan en el Caso A sin re-computar nada.
        if [[ "$start_time" =~ ^[0-9]+$ ]] && [[ "$time_limit" =~ ^[0-9]+$ ]]; then
            elapsed=$(( (current_time - start_time) / 60 ))
            if [ "$elapsed" -gt "$time_limit" ]; then
                sed -i 's/status: running/status: expired/' "$EXAM_STATUS_FILE"
                _print_expired_error "$time_limit"; exit 1
            fi
        fi
        echo -e "${GREEN}[+] Estado OK (Tiempo transcurrido: ${elapsed} min de ${time_limit} permitidos)${NC}"
    else
        # Sin fichero de estado: no se empezó con 'exam'.
        # Se permite corregir (práctica libre fuera de examen)
        # pero con aviso, para que no sorprenda el bloqueo el
        # día que SÍ haya cronómetro.
        echo -e "${YELLOW}[!] Advertencia: No se encuentra el estado del examen. Se permite la corrección.${NC}"
    fi

    # ========================================================
    # 2) EJECUCIÓN de todos los checks del examen
    #    El reporte va a un temporal para que el resultado
    #    quede limpio y reutilizable (se imprime y se loguea).
    #    'total' y 'passed' vuelven del parser por NAMEREF
    #    (local -n): bash pasa "la variable misma", no una
    #    copia — el parser las incrementa y lab_grade las ve.
    # ========================================================
    echo "-----------------------------------"
    local total=0
    local passed=0
    local tmp_out
    tmp_out=$(mktemp)

    _parse_and_check_exam "$exam_file" total passed > "$tmp_out"

    # ========================================================
    # 3) ANTI-FALSO-APROBADO
    #    Si no se parseó ningún check, el YAML del examen está
    #    corrupto o vacío → abortar. Sin esto, 0/0 evalúa como
    #    "APROBADO" porque passed == total (0 == 0).
    # ========================================================
    if [ "$total" -eq 0 ]; then
        echo -e "${RED}[-] ERROR CRÍTICO: 0 checks parseados. El YAML del examen está corrupto o vacío.${NC}"
        rm -f "$tmp_out"
        exit 1
    fi

    # ========================================================
    # 4) RESULTADO + PERSISTENCIA + LIMPIEZA
    # ========================================================
    cat "$tmp_out"
    echo "-----------------------------------"
    _print_grade_result "$passed" "$total"
    _save_results "$exam_file" "$tmp_out" "$passed" "$total"
    rm -f "$tmp_out"

    # El examen se consume: status, cronómetro y examen
    # actual quedan limpios (reset_exam_state, utils.sh).
    # El log de state/results/ sí sobrevive.
    reset_exam_state
    echo -e "${CYAN}[+] Estado del examen limpiado.${NC}"
}

# ------------------------------------------------------------
# Banner de error cuando el cronómetro ha expirado
# ------------------------------------------------------------
function _print_expired_error() {
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}  EXAMEN EXPIRADO${NC}"
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED} El tiempo límite de $1 minutos ha sido superado.${NC}"
    echo -e "${RED} Simulador detenido para evitar trampas.${NC}"
    echo -e "${RED}=========================================${NC}"
}

# ------------------------------------------------------------
# _resolve_exam_file → decide qué examen corregir:
#   a) Si lab.sh recibió un escenario como argumento → ese.
#      NOTA: reutiliza PLAYBOOK_FILE como transporte del
#      escenario; en grade significa "ruta del examen a
#      corregir", históricamente comparte el nombre.
#   b) Si no, el examen activo (state/current_exam.yml).
#   c) Si nada: error POR STDERR. El stdout de esta función
#      es DATO (la ruta que captura el $(...) de lab_grade):
#      mezclarlo imprimiría basura dentro de exam_file. El
#      exit 1 cierra la SUBSHELL del $(...); el mensaje sí
#      llega a pantalla y el flujo termina tropezando con el
#      anti-falso-aprobado de 0 checks: sin examen no hay
#      nada que parsear.
# ------------------------------------------------------------
function _resolve_exam_file() {
    if [ -n "$PLAYBOOK_FILE" ]; then
        local file=""
        if [ -f "$PROJECT_DIR/${PLAYBOOK_FILE}" ]; then
            # Ruta relativa al lab tal cual (p.ej. scenarios/hard/exam_003.yml)
            file="$PROJECT_DIR/${PLAYBOOK_FILE}"
        elif [[ "$PLAYBOOK_FILE" = /* ]] && [ -f "$PLAYBOOK_FILE" ]; then
            # Ruta absoluta
            file="$PLAYBOOK_FILE"
        else
            # Historico: nombre pelado o ruta scenarios-relativa (hard/exam_003.yml)
            file="$SCENARIOS_DIR/${PLAYBOOK_FILE}"
        fi
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
# _parse_and_check_exam <fichero> <nameref total> <nameref passed>
#
#   Parser línea a línea del YAML + ejecución de checks.
#   Es una MÁQUINA DE ESTADOS con cuatro acumuladores:
#     task_id / check_type / check_name / check_path
#
#   Mecánica: al ver una línea "- task_id:" se ejecuta el
#   check ANTERIOR (ya completo) y los acumuladores se
#   resetean para el nuevo. El ÚLTIMO check no tiene
#   sucesor: se ejecuta al salir del bucle.
#
#   xargs COMO TRIM+UNQUOTE: `echo "$valor" | xargs` recorta
#   los blancos de alrededor Y las comillas ("vg_datos" →
#   vg_datos). Todos los valores pasan por ahí.
#
#   NAMEREFS (bash >= 4.3): `local -n ref_total="$2"` crea un
#   ALIAS de la variable del llamador; incrementar ref_total
#   incrementa el 'total' de lab_grade.
#
#   En las líneas PASS/FAIL el token __NODE__ se muestra como
#   <nodo>: la expansión real es por nodo y solo la conoce
#   _run_check; en pantalla basta la forma genérica.
#
#   Un check sin type o sin name se descuenta (no cuenta ni
#   como fallo): es ruido del YAML. check_path SÍ puede ir
#   vacío (hay checkers que no necesitan ruta).
# ------------------------------------------------------------
function _parse_and_check_exam() {
    local exam_file="$1"
    local -n ref_total="$2"
    local -n ref_passed="$3"

    local task_id="" check_type="" check_name="" check_path=""

    # IFS= preserva la línea tal cual; read -r no interpreta
    # backslashes. El sed normaliza la indentación inicial
    # para que ^type:, ^name:... casen a cualquier nivel.
    while IFS= read -r line; do
        # -- Normaliza espacios de inicio de línea --
        line=$(echo "$line" | sed 's/^[[:space:]]*//')

        # -- Nueva entrada de check ("- task_id: ...") --
        #    Primero ejecuta el check ANTERIOR acumulado.
        if [[ $line =~ ^-.*task_id:[[:space:]]*(.*) ]]; then
            if [[ -n "$task_id" && -n "$check_type" && -n "$check_name" ]]; then
                if _run_check "$task_id" "$check_type" "$check_name" "$check_path"; then
                    echo -e "  [${GREEN}PASS${NC}] $task_id (${check_type}: ${check_name//__NODE__/<nodo>})"
                    ref_passed=$((ref_passed + 1))
                else
                    echo -e "  [${RED}FAIL${NC}] $task_id (${check_type}: ${check_name//__NODE__/<nodo>})"
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
    #    Es el mismo bloque del bucle, duplicado a propósito:
    #    extraerlo a una función exigiría pasar los namerefs
    #    de nuevo y el intercambio no compensa.
    if [[ -n "$task_id" && -n "$check_type" && -n "$check_name" ]]; then
        if _run_check "$task_id" "$check_type" "$check_name" "$check_path"; then
            echo -e "  [${GREEN}PASS${NC}] $task_id (${check_type}: ${check_name//__NODE__/<nodo>})"
            ref_passed=$((ref_passed + 1))
        else
            echo -e "  [${RED}FAIL${NC}] $task_id (${check_type}: ${check_name//__NODE__/<nodo>})"
        fi
        ref_total=$((ref_total + 1))
    fi
}

# ------------------------------------------------------------
# _run_check <task_id> <tipo> <name> <path>
#   Ejecuta UN check contra TODOS los nodos (node1 Y node2 Y
#   node3: el check es del laboratorio entero, no de un nodo
#   suelto).
#
#   EL CONTRATO DE LOS PLUGINS:
#     core/checkers/check_<tipo>.sh se SOURCEA con tres
#     argumentos: $1=nodo $2=name $3=path. Su stdout viaja
#     dentro del $(...): exactamente "OK" = pasado; cualquier
#     otra cosa = fallo (normalmente, la razón del mismo).
#     Al sourcear DENTRO de $() va a una subshell: las vars
#     del plugin no contaminan el motor.
#
#   POR QUÉ source Y NO ejecutar: los checkers usan colores y
#   constantes del lab ya cargados en memoria; ejecutarlos
#   como scripts obligaría a sourcear medio lab por check.
# ------------------------------------------------------------
function _run_check() {
    local task_id="$1" check_type="$2" check_name="$3" check_path="$4"
    local all_ok=true

    # -- ¿Existe el plugin de corrección? --
    #    Un tipo sin checker es un error de configuración del
    #    YAML: se reporta como WARN y cuenta como fallo (mejor
    #    fallar a la vista que aprobar en silencio).
    if [ ! -f "$CHECKERS_DIR/check_${check_type}.sh" ]; then
        echo -e "  [${YELLOW}WARN${NC}] $task_id (Checker desconocido: $check_type)"
        return 1
    fi

    # -- Ejecución en cada nodo (source del plugin) --
    for node in "${LAB_NODES[@]}"; do
        local result
        # __NODE__ → nombre del nodo: los checks de LVM llevan
        # /dev/vg___NODE__ y aquí se convierte en la ruta real
        # de CADA nodo (vg_node1, vg_node2...). El // replacea
        # TODAS las apariciones del token, no solo la primera.
        local cname cpath
        cname="${check_name//__NODE__/$node}"
        cpath="${check_path//__NODE__/$node}"
        result=$(source "$CHECKERS_DIR/check_${check_type}.sh" "$node" "$cname" "$cpath")
        if [ "$result" != "OK" ]; then
            all_ok=false
            # La razon del fallo viaja en $result (stdout del checker):
            # 2 primeras lineas, indentadas y con el nodo. Sin esto el
            # reporte dice FAIL sin explicar POR QUE.
            echo "$result" | head -2 | sed "s/^/       [$node] /"
            break              # Con un fallo basta: no iterar más
        fi
    done

    $all_ok                    # 'true'/'false' como exit status
}

# ------------------------------------------------------------
# _print_grade_result <passed> <total> → resumen final
#   Aprobar exige passed == total. El caso degenerado 0 == 0
#   nunca llega aquí: lab_grade aborta antes con el
#   anti-falso-aprobado.
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
# _save_results <examen> <output> <passed> <total>
#   Persiste el resultado en state/results/exam_<id>_<timestamp>.log.
#
#   POR QUÉ SIN COLORES: el log se lee en un editor/less y las
#   secuencias ANSI (ESC[32m...) se ven como jeroglíficos.
#   El sed elimina TODAS las secuencias "ESC [ ... m" del
#   reporte; \x1b es el ESC en GNU sed.
#
#   El { ... } > fichero agrupa los echo SIN subshell (las
#   vars del entorno siguen visibles). El "Estado:" se computa
#   inline con el && / || del echo.
# ------------------------------------------------------------
function _save_results() {
    local exam_file="$1" output_file="$2" passed="$3" total="$4"
    ensure_state_dir

    # Timestamp al segundo: dos grades en el mismo minuto no
    # se pisan entre sí.
    local timestamp; timestamp=$(date '+%Y%m%d_%H%M%S')
    local log_file="$RESULTS_DIR/$(basename "$exam_file" .yml)_${timestamp}.log"
    # Solo el nombre base: en el log se lee mejor y da igual
    # si el examen venía de state/ o de scenarios/.
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
