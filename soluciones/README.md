# Soluciones de referencia — RHCE Lab

Una solución por tarea del banco (`scenarios/task_pool.yml`), nombrada con
su `task_id` para ir directo a la que necesitas.

Cada playbook está **comentado a fondo**:

- **Cabecera**: el enunciado que resuelve, los conceptos EX294 que
  practica, las advertencias ("detalles finos") y qué valida el checker
  del lab.
- **Cuerpo**: comentarios línea a línea con el *porqué* de cada módulo y
  cada parámetro — el *qué* ya lo ves en el propio YAML.

> **Regla de uso**: resiste al menos 15 minutos antes de mirar. La solución
> se lee mejor DESPUÉS de intentarlo — el examen real no trae chuleta.

## Cómo ejecutar una solución

~
docker cp soluciones/<task_id>.yml control:/home/ansible/<task_id>.yml
docker exec -u ansible control ansible-playbook /home/ansible/<task_id>.yml
~

**Excepción — `hard_block_rescue`**: el enunciado exige la ruta exacta
`control:/home/ansible/block_rescue.yml`:

~
docker cp soluciones/hard_block_rescue.yml control:/home/ansible/block_rescue.yml
docker exec -u ansible control ansible-playbook /home/ansible/block_rescue.yml
~

## Mapa de tareas

| task_id | Tarea | Dificultad | Practica |
|---|---|---|---|
| rand_pkg_httpd | Instalar el servidor web httpd | easy | `package` genérico + idempotencia |
| rand_svc_httpd | Habilitar y arrancar el servicio httpd | easy | encadenar `package` -> `service` |
| rand_user_deploy | Crear el usuario `deployer` | easy | `user` básico |
| rand_pkg_vsftpd | Instalar el servidor FTP vsftpd | easy | `package` genérico |
| rand_pkg_mariadb | Instalar `mariadb-server` | easy | precisión de nombres de paquete |
| rand_user_webmaster | Crear el usuario `webmaster` | easy | `user` básico |
| rand_group_devs | Crear el grupo `developers` con GID 3000 | easy | `group` + GID fijo |
| med_pkg_svc_chrony | Instalar chrony y dejar `chronyd` activo | medium | patrón paquete + servicio |
| med_pkg_svc_vsftpd | Instalar vsftpd y dejar el servicio activo | medium | patrón paquete + servicio |
| med_user_app | Crear el usuario `appuser` con UID 2500 | medium | `user` + UID fijo |
| medium_fcontext_web | SELinux: `/web` + regla fcontext + restorecon | medium | `sefcontext` + `command`/`changed_when` |
| hard_lvm_vg | Volume Group `vg_<nodo>` en el disco extra | hard | `lvg` + mapeo por `inventory_hostname` |
| hard_lvm_full | VG + LV `lv_data` 300MB + ext4 + `/mnt/datos` | hard | cadena `lvg`->`lvol`->`filesystem`->`mount` |
| hard_cron | Cron para `ansible`: `/usr/bin/echo backup` | hard | `cron` con `user` + `special_time` |
| hard_cron_root | Cron para `root`: `/usr/local/bin/backup.sh` | hard | `cron` root + stub ejecutable |
| hard_block_rescue | `block`/`rescue`/`always` contra todos los nodos | hard | control de errores declarativo |

En el listado del examen ves la descripción; en `./lab.sh grade` ves el
`task_id` de cada check — ambos te llevan al fichero.

---
RHCE PRACTICE EXAM © 2026 llljacklll — Licencia CC BY-NC-SA 4.0
