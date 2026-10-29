#!/bin/bash
# ============================================================
#  core/checkers/check_vault.sh — plugin: Ansible Vault
# ------------------------------------------------------------
#  QUÉ VALIDA: que un fichero esté cifrado con Ansible Vault,
#  que descifre con la contraseña del laboratorio y que
#  contenga la variable pedida (huecos #7 y #9 del intel:
#  crear un vault y hacerle rekey).
#
#  CONTRATO con _run_check (grade.sh), igual que TODA la
#  familia de core/checkers/:
#    $1 = node .. sin uso: el vault vive en control (ahí está
#                  la contraseña del lab y el entregable).
#    $2 = name ... variable que debe existir dentro.
#    $3 = path ... ruta del vault DENTRO de control.
#    SALIDA: UNA línea en stdout, "OK" o "FAIL <razón>".
#
#  DETALLES:
#   - La contraseña del lab vive en ansible/files/.vault_pass
#     (montada en control:/opt/ansible/files/); el checker es
#     root y la lee sin problemas de permisos.
#   - 'ansible-vault view' hace el doble trabajo: si el
#     fichero no está cifrado falla, y si está cifrado con
#     otra contraseña también. Un comando, veredicto honesto.
# ============================================================
local vaultvar="$2"; local vpath="$3"
local plain
if [ -z "$vpath" ]; then
    echo "FAIL falta la ruta del vault ('path:' en el YAML)"
elif ! docker exec control test -f "$vpath" 2>/dev/null; then
    echo "FAIL el vault $vpath no existe en control"
elif ! docker exec control grep -q "ANSIBLE_VAULT" "$vpath" 2>/dev/null; then
    echo "FAIL $vpath existe pero NO está cifrado con vault"
elif ! plain=$(docker exec control ansible-vault view "$vpath" \
        --vault-password-file /opt/ansible/files/.vault_pass 2>/dev/null); then
    echo "FAIL $vpath no descifra con la contraseña del lab"
elif printf '%s\n' "$plain" | grep -q -- "$vaultvar"; then
    echo "OK"
else
    echo "FAIL el vault no contiene la variable $vaultvar"
fi
