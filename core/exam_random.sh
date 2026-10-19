#!/bin/bash
# ==========================================
# Generación de exámenes aleatorios
# ==========================================
function generate_random_exam() {
    local num_tasks="${1:-3}"
    local difficulty="${2:-mixed}"
    # Permite: --random hard  ==  --random 3 hard
    case "$num_tasks" in
        easy|medium|hard|mixed)
            local swap="$difficulty"; difficulty="$num_tasks"; num_tasks="${swap:-3}" ;;
    esac
    if ! [[ "$num_tasks" =~ ^[0-9]+$ ]]; then echo -e "${RED}[-] Numero de tareas invalido${NC}"; exit 1; fi
    case "$difficulty" in
        easy|medium|hard|mixed) ;;
        *) echo -e "${RED}[-] Dificultad invalida: $difficulty (easy|medium|hard|mixed)${NC}"; exit 1 ;;
    esac
    require_file_exists "$TASK_POOL_FILE" "No existe task_pool.yml"
    echo -e "${CYAN}[+] Generando examen aleatorio (${num_tasks} tareas, dificultad ${difficulty})...${NC}"
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
    if [ ! -s "$CURRENT_EXAM_FILE" ]; then echo -e "${RED}[-] Error: Python no genero el examen.${NC}"; exit 1; fi
    echo -e "${GREEN}[+] Examen generado correctamente ($(grep -c 'task_id:' "$CURRENT_EXAM_FILE") checks).${NC}"
}
