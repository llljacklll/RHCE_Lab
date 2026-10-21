# Soluciones de referencia — RHCE Lab

Una solución por tarea del banco (`scenarios/task_pool.yml`), nombrada con su
`task_id` para ir directo a la que necesitas.

> **Regla de uso**: resiste al menos 15 minutos antes de mirar. La solución se
> lee mejor DESPUÉS de intentarlo — el examen real no trae chuleta.

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

| task_id | Tarea | Dificultad |
|---|---|---|
| rand_pkg_httpd | Instalar el servidor web httpd | easy |
| rand_svc_httpd | Habilitar y arrancar el servicio httpd | easy |
| rand_user_deploy | Crear el usuario `deployer` | easy |
| rand_pkg_vsftpd | Instalar el servidor FTP vsftpd | easy |
| rand_pkg_mariadb | Instalar `mariadb-server` | easy |
| rand_user_webmaster | Crear el usuario `webmaster` | easy |
| rand_group_devs | Crear el grupo `developers` con GID 3000 | easy |
| med_pkg_svc_chrony | Instalar chrony y dejar `chronyd` activo | medium |
| med_pkg_svc_vsftpd | Instalar vsftpd y dejar el servicio activo | medium |
| med_user_app | Crear el usuario `appuser` con UID 2500 | medium |
| medium_fcontext_web | SELinux: `/web` + regla fcontext `httpd_sys_content_t` + restorecon | medium |
| hard_lvm_vg | Volume Group `vg_<nodo>` en el disco extra del nodo | hard |
| hard_lvm_full | VG por nodo + LV `lv_data` 300MB + ext4 + `/mnt/datos` | hard |
| hard_cron | Cron para `ansible`: `/usr/bin/echo backup` | hard |
| hard_cron_root | Cron para `root`: `/usr/local/bin/backup.sh` | hard |
| hard_block_rescue | `block`/`rescue`/`always` contra todos los nodos | hard |

En el listado del examen ves la descripción; en `./lab.sh grade` ves el
`task_id` de cada check — ambos te llevan al fichero.

---
RHCE PRACTICE EXAM © 2026 llljacklll — Licencia CC BY-NC-SA 4.0
