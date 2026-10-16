# 🎭 role_webserver

Rol de referencia del RHCE Lab que despliega un servidor Apache
configurable 100% mediante dos variables.

## Variables

| Variable    | Default | Descripción                            |
|-------------|---------|----------------------------------------|
| `http_port` | `80`    | Puerto de escucha de Apache (`Listen`) |
| `owner`     | `Admin` | Propietario mostrado en `index.html`  |

Ambas viven en `defaults/main.yml`, por lo que cualquier playbook
puede sobrescribirlas desde su bloque `vars`
(precedencia: `playbook vars` > `role defaults`).

## Uso

~~~yaml
- hosts: nodes
  become: true
  vars:
    http_port: 8080
    owner: "Victor"
  roles:
    - role_webserver
~~~

## Tareas (tasks/main.yml)

1. Instala el paquete `httpd` (`ansible.builtin.dnf`).
2. Despliega `/etc/httpd/conf.d/ports.conf` desde `templates/ports.conf.j2`.
3. Despliega `/var/www/html/index.html` desde `templates/index.html.j2`.
4. Habilita y arranca el servicio `httpd`.

## Handlers (handlers/main.yml)

- `reiniciar httpd`: se dispara **solo** si cambia `ports.conf`.
