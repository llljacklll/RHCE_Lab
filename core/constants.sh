#!/bin/bash
# ============================================================================
#  core/constants.sh — la "placa base" del laboratorio
# ----------------------------------------------------------------------------
#  RESPONSABILIDAD:
#    Único sitio donde viven las rutas y valores fijos. El resto de módulos
#    NO hardcodea: usa estas constantes. Mover algo de sitio = tocarlo
#    aquí y en ningún otro sitio más.
#
#  POR QUÉ readonly:
#    Este fichero se sourcea desde muchos sitios (lab.sh, tests, scripts).
#    readonly hace imposible que un módulo pise una constante por
#    accidente y el resto del lab apunte a un directorio fantasma.
#
#  CONVENCIONES:
#    - MAYÚSCULAS = constante inmutable durante toda la ejecución.
#    - state/ es TODO regenerable por el propio lab (examen en curso,
#      cronómetro, resultados): nunca se commitea.
# ============================================================================

# Raíz del proyecto: BASH_SOURCE[0] = este fichero (core/), /.. sube un
# nivel y 'pwd' lo vuelve absoluto. El mismo truco tolerante a symlinks
# y cwd que usa lab.sh — así el lab se puede lanzar desde cualquier sitio.
readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- Subdirectorios del proyecto ----
readonly DOCKER_DIR="$PROJECT_DIR/docker"          # compose + Dockerfile + discos
readonly ANSIBLE_DIR="$PROJECT_DIR/ansible"        # área del ALUMNO: playbooks + inventario
readonly SCENARIOS_DIR="$PROJECT_DIR/scenarios"    # banco de tareas + exámenes predefinidos
readonly STATE_DIR="$PROJECT_DIR/state"           # estado regenerable (nunca en git)
readonly INVENTORY_DIR="$ANSIBLE_DIR/inventory"    # hosts.ini del inventario local
readonly PLAYBOOKS_DIR="$ANSIBLE_DIR/playbooks"     # donde el alumno escribe sus .yml
readonly CHECKERS_DIR="$PROJECT_DIR/core/checkers" # un checker por tipo de tarea

# ---- Banco de tareas y resultados de corrección ----
readonly RESULTS_DIR="$STATE_DIR/results"             # historial de 'grade'
readonly TASK_POOL_FILE="$SCENARIOS_DIR/task_pool.yml" # el banco de donde se sortea

# ---- Estado del examen en curso (trío ANTI-TRAMPAS) ----
# TIMER_PID_FILE   : PID del cronómetro en background -> reset_exam_state
#                    (core/utils.sh) puede matarlo al hacer down/reset.
# CURRENT_EXAM_FILE: examen sorteado de ESTA sesión (tareas + enunciados).
# EXAM_STATUS_FILE : hora de inicio y de expiración; 'grade' lo consulta
#                    y se NIEGA a corregir si el tiempo expiró.
readonly TIMER_PID_FILE="$STATE_DIR/timer.pid"
readonly DEFAULT_DNS=""
readonly CURRENT_EXAM_FILE="$STATE_DIR/current_exam.yml"
readonly EXAM_STATUS_FILE="$STATE_DIR/exam_status.yml"

# ---- Red ----
# Vacío A PROPÓSITO = "usa el DNS del sistema" (setup_docker_dns elimina
# daemon.json y no fuerza nada). Solo se rellena vía './lab.sh up --dns'.

# Inventario fijo del lab: control + 3 nodos managed. Al ser array de bash
# se itera con:  for node in "${LAB_NODES[@]}"
readonly LAB_NODES=(node1 node2 node3)
