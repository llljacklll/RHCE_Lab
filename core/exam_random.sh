#!/bin/bash
# ==========================================
# Generación de exámenes aleatorios
# ==========================================
function generate_random_exam() {
    local num_tasks="${1:-3}"
    if ! [[ "$num_tasks" =~ ^[0-9]+$ ]]; then echo -e "${RED}[-] Número de tareas inválido${NC}"; exit 1; fi
    require_file_exists "$TASK_POOL_FILE" "No existe task_pool.yml"
    echo -e "${CYAN}[+] Generando examen aleatorio (${num_tasks} tareas)...${NC}"
    python3 << PYEOF > "$CURRENT_EXAM_FILE"
import yaml, random, sys
try:
    with open("$TASK_POOL_FILE") as f: pool = yaml.safe_load(f)
except Exception as e: print(f"ERROR: {e}", file=sys.stderr); sys.exit(1)
tasks = pool.get("tasks", [])
if not tasks: print("ERROR: No hay tareas", file=sys.stderr); sys.exit(1)
selected = random.sample(tasks, min($num_tasks, len(tasks)))
exam = {"id": "random_exam", "difficulty": "mixed", "title": "Examen Aleatorio RHCE", "time_limit": 15 * len(selected), "tasks": [], "checks": []}
for t in selected:
    exam["tasks"].append({"id": t["id"], "description": t["description"]})
    for c in t.get("checks", []): item = {"task_id": t["id"]}; item.update(c); exam["checks"].append(item)
print(yaml.d
PYEOF
    if [ ! -s "$CURRENT_EXAM_FILE" ]; then echo -e "${RED}[-] Error: Python no generó el examen.${NC}"; exit 1; fi
    echo -e "${GREEN}[+] Examen generado correctamente.${NC}"
}
