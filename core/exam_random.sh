#!/bin/bash
# ============================================================
#  core/exam_random.sh — generador de exámenes aleatorios
# ============================================================
#  RESPONSABILIDAD:
#    Montar un YAML de examen "a medida" desde el banco de
#    tareas (scenarios/task_pool.yml): elige N tareas al
#    azar, opcionalmente filtradas por dificultad, y lo
#    vuelca en $CURRENT_EXAM_FILE con el MISMO formato que
#    los exámenes predefinidos de scenarios/. El resto del
#    lab (arranque, cronómetro, grade) no distingue un
#    examen aleatorio de uno fijo: mismo esquema, mismas
#    correcciones.
#
#  QUIÉN LO LLAMA: core/exam.sh, cuando el usuario hace
#    ./lab.sh exam --random [N] [easy|medium|hard|mixed]
#
#  POR QUÉ PYTHON (y no bash+grep):
#    task_pool.yml es YAML anidado (tareas → checks). PyYAML
#    lee el banco, copia los checks de cada tarea elegida
#    COMPLETOS y regenera un documento siempre válido con
#    yaml.dump; con grep/sed quedaríamos atados a la
#    indentación exacta del fichero.
#
#  EL TRUCO DEL SWAP DE ARGUMENTOS (el case de abajo):
#    El usuario puede escribir los argumentos en cualquier
#    orden:
#        --random hard      → solo dificultad, 3 tareas
#        --random 3 hard    → número + dificultad
#        --random hard 3    → lo mismo, intercambiado
#    $1 se lee primero como "número"; si resulta ser una
#    dificultad, el case intercambia $1 y $2. El ${swap:-3}
#    cubre el caso "--random hard" (no hay $2 → el número
#    sale por defecto a 3).
# ============================================================

function generate_random_exam() {
    # Argumentos opcionales con valores por defecto: 3
    # tareas de cualquier dificultad (mixed). ${var:-x} =
    # "var, y si está vacía/sin definir, x".
    local num_tasks="${1:-3}"
    local difficulty="${2:-mixed}"

    # Permite: --random hard == --random 3 hard ==
    # --random hard 3. Si $1 es en realidad una dificultad
    # (no un número), se intercambian $1 y $2; el número
    # que llega del swap cae a 3 si $2 venía vacío.
    case "$num_tasks" in
        easy|medium|hard|mixed)
            local swap="$difficulty"; difficulty="$num_tasks"; num_tasks="${swap:-3}" ;;
    esac

    # Validar el número DESPUÉS del swap. =~ con ^[0-9]+$     # en vez de un case: acepta cualquier cantidad (5, 7...)
    # sin enumerarlas una a una.
    if ! [[ "$num_tasks" =~ ^[0-9]+$ ]]; then echo -e "${RED}[-] Numero de tareas invalido${NC}"; exit 1; fi

    # Validar la dificultad contra la lista cerrada. La
    # primera rama está vacía a propósito: es el "válido,
    # sigue" de este case de validación.
    case "$difficulty" in
        easy|medium|hard|mixed) ;;
        *) echo -e "${RED}[-] Dificultad invalida: $difficulty (easy|medium|hard|mixed)${NC}"; exit 1 ;;
    esac

    # El banco es la fuente de verdad del lab: sin él no
    # hay nada que generar. require_* aborta ruidosamente
    # con el mensaje indicado.
    require_file_exists "$TASK_POOL_FILE" "No existe task_pool.yml"

    echo -e "${CYAN}[+] Generando examen aleatorio (${num_tasks} tareas, dificultad ${difficulty})...${NC}"

    # ------------------------------------------------------------
    # El trabajo pesado lo hace Python (tiene YAML de verdad).
    # Qué hace el script, paso a paso:
    #   1. lee el banco desde $TASK_POOL_FILE;
    #   2. si se pidió una dificultad CONCRETA (no mixed),
    #      se queda solo con las tareas de esa dificultad;
    #   3. random.sample elige N tareas DIFERENTES: es un
    #      muestreo SIN reemplazo, una tarea no se repite
    #      nunca dentro del mismo examen;
    #   4. min(N, len(tasks)): pedir 5 no explota si solo
    #      hay 4 disponibles de esa dificultad;
    #   5. time_limit = 15 min por tarea, el mismo baremo
    #      que los exámenes predefinidos;
    #   6. copia los checks de cada tarea elegida COMPLETOS
    #      y etiqueta cada uno con su task_id (grade lo
    #      necesita para saber de qué tarea viene cada
    #      check);
    #   7. yaml.dump con width=1000: las descripciones
    #      largas NO se parten en varias líneas y el YAML
    #      generado sigue siendo greppable.
    #
    # NOTA de heredoc: el delimitador PYEOF2 va SIN comillas
    # → bash expande $TASK_POOL_FILE, $difficulty y
    # $num_tasks ANTES de entregar el script a python. Los
    # errores de python van a stderr, así que llegan a
    # pantalla aunque el stdout esté redirigido al fichero.
    # ------------------------------------------------------------
    python3 << PYEOF2 > "$CURRENT_EXAM_FILE"
import yaml, random, sys
try:
    with open("$TASK_POOL_FILE") as f: pool = yaml.safe_load(f)
except Exception as e: print(f"ERROR: {e}", file=sys.stderr); sys.exit(1)
tasks = pool.get("tasks", [])
if not tasks: print("ERROR: No hay tareas", file=sys.stderr); sys.exit(1)
dif = "$difficulty"
if dif in ("easy", "medium", "hard"):
    tasks = [t for t in tasks if str(t.get("difficulty", "easy")).lower() == dif]
if not tasks: print("ERROR: No hay tareas de dificultad " + dif, file=sys.stderr); sys.exit(1)
selected = random.sample(tasks, min($num_tasks, len(tasks)))
exam = {"id": "random_exam", "difficulty": dif, "title": "Examen Aleatorio RHCE", "time_limit": 15 * len(selected), "tasks": [], "checks": []}
for t in selected:
    exam["tasks"].append({"id": t["id"], "description": t["description"]})
    for c in t.get("checks", []): item = {"task_id": t["id"]}; item.update(c); exam["checks"].append(item)
print(yaml.dump(exam, default_flow_style=False, sort_keys=False, width=1000))
PYEOF2

    # Post-condición: si Python falló (PyYAML ausente, banco
    # corrupto...) el fichero queda vacío o ni existe. -s =
    # "existe Y pesa más de 0 bytes". Se comprueba ANTES de
    # presumir de éxito.
    if [ ! -s "$CURRENT_EXAM_FILE" ]; then echo -e "${RED}[-] Error: Python no genero el examen.${NC}"; exit 1; fi

    # grep -c 'task_id:' cuenta las LÍNEAS con task_id:
    # exactamente una por check → el total de puntos de
    # corrección sobre los que correrá grade.
    echo -e "${GREEN}[+] Examen generado correctamente ($(grep -c 'task_id:' "$CURRENT_EXAM_FILE") checks).${NC}"
}
