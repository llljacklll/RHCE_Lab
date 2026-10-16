#!/bin/bash
# ============================================================
#  🔐 SCRIPTS/CREATE_VAULT.SH — Bootstrap del Ansible Vault
# ============================================================
#  QUÉ HACE (en orden):
#    1. Verifica que estás en la raíz del repo.
#    2. Verifica que el laboratorio está levantado (el binario
#       'ansible-vault' vive DENTRO del contenedor 'control').
#    3. Crea 'ansible/files/secrets.yml' en claro con la variable
#       didáctica db_password y lo ENCRIPTA.
#    4. Verifica el resultado y limpia los temporales.
#
#  CUÁNDO EJECUTARLO:
#    UNA sola vez después de './lab.sh up' (tras clonar el repo
#    o si algún día borras secrets.yml a mano).
#
#  USO:
#    ./scripts/create_vault.sh            # modo normal
#    ./scripts/create_vault.sh --force    # regenerar aunque exista
# ============================================================

# ---------- Configuración del laboratorio (didáctica) ----------
readonly VAULT_PASS="RhceLab2026"                  # Contraseña del VAULT
readonly SECRET_VALUE="SecretPassword123"          # Valor de db_password
readonly SECRET_FILE="ansible/files/secrets.yml"   # Destino (bind mount → /opt/ansible/files/)

# ---------- Colores (autónomos, no dependen de ui/) ----------
readonly RED='\033[0;31m';  readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'; readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# ---------- 1) Guarda: ejecutar desde la raíz del repo ----------
if [ ! -f "./lab.sh" ]; then
    echo -e "${RED}[-] Lanza el script desde la raíz del repo: ./scripts/create_vault.sh${NC}"
    exit 1
fi

# ---------- 2) Guarda: ¿ya existe un vault encriptado? ----------
if [ -f "$SECRET_FILE" ] && grep -q "ANSIBLE_VAULT" "$SECRET_FILE" 2>/dev/null; then
    if [ "$1" != "--force" ]; then
        echo -e "${YELLOW}[!] '$SECRET_FILE' ya existe y está encriptado. Nada que hacer.${NC}"
        # FIX: aunque el vault ya exista, asegurar .vault_pass (no viaja en git)
        PASS_FILE="ansible/files/.vault_pass"
        if [ ! -f "$PASS_FILE" ]; then
            printf '%s\n' "$VAULT_PASS" > "$PASS_FILE"
            chmod 600 "$PASS_FILE"
            echo -e "${GREEN}[+] Creado $PASS_FILE (no viaja en git).${NC}"
        fi
        echo -e "${YELLOW}    Usa --force si quieres regenerarlo.${NC}"
        exit 0
    fi
    echo -e "${YELLOW}[!] Modo --force: se regenerará el vault.${NC}"
fi

# ---------- 3) Guarda: el laboratorio debe estar levantado ----------
if ! docker ps --format '{{.Names}}' | grep -q "^control$"; then
    echo -e "${RED}[-] El contenedor 'control' no está corriendo.${NC}"
    echo -e "${RED}    ansible-vault vive ahí dentro. Ejecuta antes: ./lab.sh up${NC}"
    exit 1
fi

# ---------- 4) Generar contenido en claro (temporal) ----------
echo -e "${CYAN}[+] Escribiendo contenido en claro (temporal)...${NC}"
mkdir -p "$(dirname "$SECRET_FILE")"
printf 'db_password: %s\n' "$SECRET_VALUE" > "$SECRET_FILE"

# ---------- 5) Encriptar DENTRO del contenedor ----------
# El password file vive SOLO dentro del contenedor (/root/) para no
# dejar rastros en el host. El secrets.yml resultante sí queda en el
# host gracias al volumen ../ansible:/opt/ansible.
echo -e "${CYAN}[+] Encriptando con ansible-vault (dentro de control)...${NC}"
if ! docker exec control bash -c "echo '$VAULT_PASS' > /root/.vault_pass && chmod 600 /root/.vault_pass && ansible-vault encrypt --vault-password-file /root/.vault_pass /opt/ansible/files/secrets.yml && rm -f /root/.vault_pass"; then
    echo -e "${RED}[-] Falló el encriptado. Se elimina el contenido en claro por seguridad.${NC}"
    rm -f "$SECRET_FILE"
    exit 1
fi

# ---------- 6) Verificación final ----------
if ! grep -q "ANSIBLE_VAULT" "$SECRET_FILE"; then
    echo -e "${RED}[-] El fichero no parece encriptado. Revisa el bind mount de /opt/ansible.${NC}"
    exit 1
fi

docker exec control bash -c "echo '$VAULT_PASS' > /root/.vault_pass && ansible-vault view --vault-password-file /root/.vault_pass /opt/ansible/files/secrets.yml && rm -f /root/.vault_pass"

echo ""
echo -e "${GREEN}[+] Vault listo: $SECRET_FILE${NC}"
echo -e "${GREEN}    Contraseña del vault : $VAULT_PASS      (la pide --ask-vault-pass)${NC}"
echo -e "${GREEN}    Valor de db_password  : $SECRET_VALUE (lo que buscan los checks)${NC}"
echo ""
echo -e "${CYAN}[i] Exam 003 se ejecuta así: ./lab.sh run --vault exam_003.yml${NC}"
