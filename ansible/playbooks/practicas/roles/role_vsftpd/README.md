# role_vsftpd — rol didáctico del RHCE Lab

Rol de la Práctica 2 (feedback de la comunidad): despliega vsftpd
con el patrón RHEL completo (paquete -> config con template ->
servicio) y handler de reinicio.

## Estructura (la canónica del EX294)

- `defaults/main.yml`  - variables con la precedencia MÍNIMA
- `tasks/main.yml`     - el flujo del rol
- `handlers/main.yml`  - reinicio solo si cambió la config
- `templates/`         - vsftpd.conf.j2 (Jinja2)
- `meta/main.yml`      - metadatos estilo ansible-galaxy

## Cómo consumirlo

Desde un playbook (ver ../practica_02_roles.yml):

    vars:
      vsftpd_anonymous_enable: "NO"
      vsftpd_banner: "Servidor FTP del curso RHCE"
    roles:
      - role_vsftpd

## Variables (defaults/main.yml)

| Variable | Por defecto | Qué controla |
|----------|-------------|--------------|
| vsftpd_pkg | vsftpd | paquete a instalar |
| vsftpd_anonymous_enable | "NO" | línea anonymous_enable de la config |
| vsftpd_banner | Servidor FTP gestionado por Ansible | ftpd_banner de la config |
