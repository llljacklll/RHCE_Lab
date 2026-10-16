#!/bin/bash
# ==========================================
# RHCE LAB PRO - Router Principal
# ==========================================

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

ACTION=""
DNS_CONFIG="$DEFAULT_DNS"
PLAYBOOK_FILE=""
EXAM_ARGS=""
VAULT_MODE=false

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
    echo ""
    echo "Modo Examen:"
    echo "  exam                  Mostrar menú de ayuda de exámenes"
    echo "  exam <archivo.yml>    Lanzar examen estático (ej: $0 exam easy/exam_001.yml)"
    echo "  exam --random [N]     Generar examen aleatorio y guardarlo (Defecto: 3 tareas)"
    echo "  exam --start          Iniciar cronómetro y mostrar examen generado"
    echo ""
    echo "Evaluación:"
    echo "  grade    Corregir el examen activo (ej: $0 grade)"
    echo "  test     Ejecutar la batería de pruebas automática completa"
    echo ""
    echo "Opciones:"
    echo "  --dns <ip1,ip2>  Cambiar servidores DNS (Defecto: ${DEFAULT_DNS})"
    echo "  --vault*ult       Pide contraseña para desencriptar Ansible Vault (Usar con 'run')"
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

[[ $# -eq 0 ]] && print_help

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
        up|down|start|stop|reset|shell|test)
            ACTION="$1"
            shift
            ;;
        run|grade)
            ACTION="$1"
            shift
            while [[ "$#" -gt 0 ]]; do
                case "$1" in
                    --vault) VAULT_MODE=true; shift ;;
                    *) PLAYBOOK_FILE="$1"; shift; break ;;
                esac
            done
            ;;
        exam)
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

case "$ACTION" in
    up)    print_banner; lab_up ;;
    down)  lab_down; reset_exam_state ;;
    start) lab_start ;;
    stop)  lab_stop ;;
    reset) print_banner; lab_reset ;;
    shell) lab_shell ;;
    run)   lab_run ;;
    exam)  lab_exam $EXAM_ARGS ;; 
    grade) lab_grade ;;
    test)  print_banner; lab_test ;;
    *)
        echo -e "${RED}Error: Falta la acción principal.${NC}"
        print_help
        ;;
esac
