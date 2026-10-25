#!/bin/bash
# ============================================================================
#  lab.sh — ROUTER PRINCIPAL y único punto de entrada de la CLI del lab
# ----------------------------------------------------------------------------
#  QUÉ HACE: comprueba prerrequisitos del host, carga los módulos (ui/ +
#  core/) y despacha la acción pedida (up, run, exam, grade...) a la
#  función que la implementa en core/*.sh. Aquí NO vive lógica de negocio:
#    [1] preflight de dependencias (auto-reparable)
#    [2] secreto local .vault_pass si falta   [3] carga de módulos (source x10)
#    [4] estado global del router             [5] ayuda (print_help)
#    [6] parser de argumentos                 [7] dispatch final
#
#  MAPA DE MÓDULOS (todo lo que se sourcea abajo):
#    ui/colors.sh ........ paleta ANSI (RED/GREEN/CYAN/YELLOW/NC)
#    ui/banner.sh ........ panel de estado (print_banner)
#    core/constants.sh ... constantes: DNS por defecto, rutas, etc.
#    core/utils.sh ........ helpers genéricos (logging, esperas)
#    core/docker.sh ....... up/down/start/stop/reset/shell/doctor/autostart
#    core/ansible.sh ...... 'run': ejecutar playbooks del alumno
#    core/exam_random.sh .. sorteo de tareas desde scenarios/task_pool.yml
#    core/exam.sh ......... 'exam': generar/presentar/iniciar examen
#    core/grade.sh ........ 'grade': corrección + anti-trampas (cronómetro)
#    core/test.sh ......... 'test': batería de humo automática
#    webui/webui.py ....... 'web': consola web del simulacro (LOTE 26)
#
#  USO: ./lab.sh <acción> [opciones]  (sin argumentos = menú de ayuda)
# ============================================================================

# ----------------------------------------------------------------------------
# [1] PREFLIGHT — dependencias del HOST (no de los contenedores)
# ----------------------------------------------------------------------------
# Necesita: docker CLI + plugin 'docker compose' v2 (no el viejo
# docker-compose), python3 con PyYAML (los generadores leen YAML) y
# /dev/loop0 (los discos de las tareas LVM son loops del host). Si falta
# ALGO, auto-repara con scripts/vm_bootstrap.sh (idempotente).
command -v docker >/dev/null 2>&1 || DEP_MISSING=1
docker compose version >/dev/null 2>&1 || DEP_MISSING=1
python3 -c "import yaml" >/dev/null 2>&1 || DEP_MISSING=1
[ -e /dev/loop0 ] || DEP_MISSING=1
if [ "${DEP_MISSING:-0}" = "1" ]; then
  echo "[!] Faltan dependencias del host -> ejecutando scripts/vm_bootstrap.sh"
  bash "$(dirname "$(readlink -f "$0")")/scripts/vm_bootstrap.sh" || { echo "[X] vm_bootstrap.sh fallo"; exit 1; }
fi

# Daemon de docker caído -> un intento de arranque vía systemd y seguir
# (|| true: no abortar aquí; quien necesite docker de verdad reportará
# un error claro más adelante, p.ej. doctor).
docker info >/dev/null 2>&1 || systemctl start docker >/dev/null 2>&1 || true

# ----------------------------------------------------------------------------
# [2] SECRETO LOCAL — ansible/files/.vault_pass
# ----------------------------------------------------------------------------
# El password de Vault NO viaja en git (.gitignore A PROPÓSITO: es un
# secreto local de práctica). Pero un clone fresco no lo trae y rompería
# los ejercicios con vault (examen y smoke test), así que se crea al
# vuelo con el password de práctica. chmod 600: es (nominalmente) secreto.
VPASS="$(dirname "$(readlink -f "$0")")/ansible/files/.vault_pass"
if [ ! -f "$VPASS" ]; then
  mkdir -p "$(dirname "$VPASS")"
  printf 'RhceLab2026\n' > "$VPASS"
  chmod 600 "$VPASS"
  echo "[+] Creado $VPASS (gitignored a proposito)"
fi

# ----------------------------------------------------------------------------
# [3] CARGA DE MÓDULOS — el orden importa:
#     colors primero (el resto pinta con colores), constants antes de que
#     nadie use DEFAULT_DNS. BASH_SOURCE (no $0): resistente a symlinks
#     y a lanzar el lab desde cualquier directorio.
# ----------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/ui/colors.sh"
source "$(dirname "${BASH_SOURCE[0]}")/core/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/core/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ui/banner.sh"
source "$(dirname "${BASH_SOURCE[0]}")/core/docker.sh"
source "$(dirname "${BASH_SOURCE[0]}")/core/ansible.sh"
source "$(dirname "${BASH_SOURCE[0]}")/core/exam_random.sh"
source "$(dirname "${BASH_SOURCE[0]}")/core/exam.sh"
source "$(dirname "${BASH_SOURCE[0]}")/core/grade.sh"
source "$(dirname "${BASH_SOURCE[0]}")/core/test.sh"

# ----------------------------------------------------------------------------
# [4] ESTADO GLOBAL del router
# ----------------------------------------------------------------------------
# ACTION        : acción principal que se despachará abajo
# DNS_CONFIG    : DNS que incrustará compose al levantar (default: DEFAULT_DNS)
# PLAYBOOK_FILE : playbook del alumno para 'run'
# EXAM_ARGS     : TODOS los argumentos tras 'exam' (se re-parten al despachar)
# VAULT_MODE    : true => 'run' pedirá el password de Vault
ACTION=""
DNS_CONFIG="$DEFAULT_DNS"
PLAYBOOK_FILE=""
EXAM_ARGS=""
VAULT_MODE=false

# ----------------------------------------------------------------------------
# [5] AYUDA — se muestra sin argumentos, con -h/--help y ante opciones
#     desconocidas. Termina con exit 0 (explorar el lab no es un error).
# ----------------------------------------------------------------------------
function print_help() {
    print_banner
    echo "Uso: $0 <acción> [opciones]"
    echo ""
    echo "Acciones:"
    echo "  up       Construir imágenes y levantar el laboratorio (Lento, requiere internet)"
    echo "  down     Destruir contenedores, red e imágenes (Limpieza total)"
    echo "  start    Levantar contenedores existentes (Rápido, sin recompilar)"
    echo "  stop     Detener contenedores (Mantiene imágenes para usar 'start' luego)"
    echo "  reset    Resetear por completo (down + up)"
    echo "  shell    Entrar al nodo 'control'"
    echo "  run      Ejecutar un playbook (ej: $0 run site.yml)"
    echo "  doctor      Chequeo rápido: docker, contenedores, discos y filtro LVM"
    echo "  autostart   Instalar el autoarranque del lab con la MV (systemd)"
    echo ""
    echo "Modo Examen:"
    echo "  exam                  Mostrar menú de ayuda de exámenes"
    echo "  exam <archivo.yml>    Lanzar examen estático (ej: $0 exam easy/exam_001.yml)"
    echo "  exam --random [N] [dif]  Generar examen aleatorio (Defecto: 3 tareas, mixed)"
    echo "  web [--port P]         Consola web en 127.0.0.1:8888 (acceso por tunel SSH)"
    echo "  exam --start          Iniciar cronómetro y mostrar examen generado"
    echo ""
    echo "Evaluación:"
    echo "  grade    Corregir el examen activo o uno concreto (ej: $0 grade easy/exam_001.yml)"
    echo "  test     Ejecutar la batería de pruebas automática completa"
    echo ""
    echo "Opciones:"
    echo "  --dns <ip1,ip2>  Cambiar servidores DNS (Defecto: ${DEFAULT_DNS})"
    echo "  --vault       Pide contraseña para desencriptar Ansible Vault (Usar con 'run')"
    echo ""
    echo "Ejemplos:"
    echo "  $0 up"
    echo "  $0 up --dns 1.1.1.1,8.8.8.8"
    echo "  $0 run --vault sitio_con_vault.yml"
    echo "  $0 exam --random 4"
    echo "  $0 exam --start"
    echo "  $0 run site.yml"
    echo "  $0 grade"
    exit 0
}

# Sin argumentos -> ayuda (print_help sale con exit 0).
[[ $# -eq 0 ]] && print_help

# ----------------------------------------------------------------------------
# [6] PARSER — bucle while/shift: cada rama consume lo suyo.
#     El orden de opciones y acción es LIBRE ('up --dns x' = '--dns x up').
#     - run/grade: bucle interno que acepta --vault antes del nombre del
#       playbook; tras el NOMBRE el parseo se detiene a propósito (el
#       resto se descarta).
#     - exam: se queda con TODOS los argumentos restantes (su submenú es
#       rico: --random/--start/ficheros/dificultad...).
# ----------------------------------------------------------------------------
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dns)
            [[ -z "$2" ]] && { echo -e "${RED}Error: --dns requiere IP (ej: 8.8.8.8,1.1.1.1)${NC}"; exit 1; }
            DNS_CONFIG="$2"
            shift 2
            ;;
        --vault)
            VAULT_MODE=true
            shift
            ;;
        -h|--help) print_help ;;
        up|down|start|stop|reset|shell|test|doctor|autostart|web)
            ACTION="$1"
            shift
            ;;
        run|grade)
            ACTION="$1"
            shift
            # Bucle interno: recoge --vault y el primer token no-opción
            # (el playbook). El 'break' tras capturarlo es deliberado.
            while [[ "$#" -gt 0 ]]; do
                case "$1" in
                    --vault) VAULT_MODE=true; shift ;;
                    *) PLAYBOOK_FILE="$1"; shift; break ;;
                esac
            done
            ;;
        exam)
            # EXAM_ARGS="$*" junta todo lo restante; en el dispatch se
            # expande SIN comillas (lab_exam $EXAM_ARGS) para re-partirlo
            # en argumentos independientes: el único punto donde la
            # división de palabras es INTENCIONAL (shellcheck diría
            # SC2086 — aquí es a propósito).
            ACTION="$1"
            shift
            EXAM_ARGS="$*"
            break
            ;;
        *)
            echo -e "${RED}Opción desconocida: $1${NC}"
            print_help
            ;;
    esac
done

# ----------------------------------------------------------------------------
# [7] DISPATCH — cada acción a su función (definidas en core/*.sh):
#     up/down/start/stop/reset/shell/doctor/autostart -> core/docker.sh
#     run -> core/ansible.sh · exam -> core/exam.sh · grade -> core/grade.sh
#     test -> core/test.sh. 'down' además resetea el estado del examen:
#     un examen a medias NO debe sobrevivir a la destrucción del lab.
# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# WEB - consola web del simulacro (LOTE 26). La web ES el CLI: lab_web
# solo hace exec de python3 con webui/webui.py; sin logica de negocio aqui.
# ----------------------------------------------------------------------------
function lab_web() {
    local dir webui_py
    dir=$(dirname "$(readlink -f "$0")")
    webui_py="$dir/webui/webui.py"
    command -v python3 >/dev/null 2>&1 || { echo -e "${RED}[-] python3 no disponible${NC}"; exit 1; }
    [ -f "$webui_py" ] || { echo -e "${RED}[-] No existe $webui_py${NC}"; exit 1; }
    exec python3 "$webui_py" "$@"
}
case "$ACTION" in
    up)    print_banner; lab_up ;;
    down)  lab_down; reset_exam_state ;;
    start) lab_start ;;
    stop)  lab_stop ;;
    reset) print_banner; lab_reset ;;
    shell) lab_shell ;;
    doctor)   lab_doctor ;;
    autostart) lab_autostart ;;
    web)    lab_web "$@" ;;
    run)   lab_run ;;
    exam)  lab_exam $EXAM_ARGS ;;
    grade) lab_grade ;;
    test)  print_banner; lab_test ;;
    *)
        # Solo opciones globales sin acción (ej: './lab.sh --dns 1.1.1.1').
        echo -e "${RED}Error: Falta la acción principal.${NC}"
        print_help
        ;;
esac
