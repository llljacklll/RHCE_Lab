# Prácticas guiadas — paquetes/servicios y roles

QUÉ ES: dos prácticas guiadas nacidas del feedback de la comunidad
(Ivan Rivera): lo que más interesa practicar son los playbooks de
paquetes/servicios y los roles.

DIFERENCIA CON LOS EXÁMENES: aquí no hay cronómetro ni motor de
corrección. El objetivo es aprender el patrón leyendo la solución
comentada DESPUÉS de intentarlo tú. Las prácticas NO entran en la
batería (`./lab.sh test` queda intacto a propósito).

DIFERENCIA CON `soluciones/`: esas son referencias tarea a tarea del
banco del generador; las prácticas son escenarios completos de
principio a fin, con rol incluido en la segunda.

## Protocolo recomendado (15 minutos por práctica)

1. Lee solo el ENUNCIADO (cabecera del playbook correspondiente).
2. Escribe tu playbook desde cero y ejecútalo con `./lab.sh run`.
3. Compara con la solución de este directorio.
4. Ejecuta la solución DOS veces: la segunda debe salir con
   `changed=0` en todo (idempotencia).
5. Verifica a mano como haría el corrector (comandos más abajo).

## Práctica 1 — Paquetes y servicios (sin rol)

Enunciado y solución: `practica_01_paquetes_servicios.yml`

Conceptos EX294: `ansible.builtin.dnf` con lista de paquetes,
`ansible.builtin.lineinfile` con regexp, notify/handlers,
`ansible.builtin.service` (started + enabled), idempotencia.

Checkers del motor que miran lo mismo: `check_package.sh`,
`check_service.sh`, `check_file.sh` (core/checkers/).

## Práctica 2 — Tu primer rol completo

Enunciado y solución: `practica_02_roles.yml` + `roles/role_vsftpd/`

Conceptos EX294: estructura canónica de un rol (defaults, tasks,
handlers, templates, meta), resolución del rol adjunto al playbook,
sobrescritura de defaults desde el play (precedencia), Jinja2 en
templates de rol. Es exactamente el mecanismo que usa
`playbooks/exam_002.yml` con `role_webserver`.

Checkers del motor que miran lo mismo: `check_package.sh`,
`check_service.sh`, `check_file.sh`.

## Cómo ejecutar las soluciones

    ./lab.sh run practicas/practica_01_paquetes_servicios.yml
    ./lab.sh run practicas/practica_02_roles.yml

(el argumento es relativo a ansible/playbooks/, igual que los exámenes)

## Verificación manual (como hace el corrector)

Desde la consola del control (`./lab.sh shell`):

    ansible nodes -m command -a "rpm -q vsftpd tree" -i /opt/ansible/inventory/hosts.ini
    ansible nodes -m command -a "systemctl is-active vsftpd" -i /opt/ansible/inventory/hosts.ini
    ansible nodes -m command -a "systemctl is-enabled vsftpd" -i /opt/ansible/inventory/hosts.ini
    ansible nodes -m shell -a "grep -E '^(anonymous_enable|ftpd_banner)=' /etc/vsftpd/vsftpd.conf" -i /opt/ansible/inventory/hosts.ini

Si `grep` devuelve `anonymous_enable=NO` y el banner del rol, y las
dos comprobaciones de systemd devuelven `active` y `enabled`, las dos
prácticas están verdes.
