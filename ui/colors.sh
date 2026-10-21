#!/bin/bash
# ============================================================
#  ui/colors.sh — paleta ANSI de toda la CLI del laboratorio
# ============================================================
#  RESPONSABILIDAD:
#    Un único sitio donde viven los colores. Todo el lab se sourcea
#    este fichero y pinta con:  echo -e "${GREEN}texto${NC}"
#
#  POR QUÉ 'readonly':
#    Estos ficheros se sourcean varias veces por sesión (lab.sh, scripts
#    de prueba...). readonly garantiza que NADIE redefina un color por
#    accidente y despinte media CLI (bash daría error de solo-lectura).
#
#  CÓDIGOS (formato \033[<estilo>;<color>m):
#    0;31 rojo    -> errores, estado DOWN, checks fallidos
#    0;32 verde   -> éxitos, estado UP, checks OK
#    0;36 cian    -> logo, títulos, secciones informativas
#    1;33 amarillo (negrita) -> paneles, avisos, bordes
#    0m   reset   -> OBLIGATORIO al final de cada fragmento de color:
#                    sin él, el color "sangra" al resto de la línea y a
#                    las siguientes (el clásico terminal medio verde).
#
#  NOTA: todo el lab estandariza 'echo -e' para interpretar \033.
# ==========================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'
