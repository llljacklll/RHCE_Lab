# Intel del examen real EX294

Recopilado: 2026-10-29
Fuente: chat interno del equipo de trabajo (abril). Testimonio de Emilio, dos
intentos del examen (suspenso el primero, aprobado el segundo), mas los dos
ficheros de ejercicios que cayeron tal cual en sus examenes (EXAMEN EX294.txt
y EJERCICIOS_EX294.txt).

AVISO IMPORTANTE: esos dos ficheros NO se suben nunca al repo. El contenido
concreto de un examen Red Hat esta cubierto por su NDA y este repo puede
llegar a hacerse publico. Aqui se guarda el analisis y el mapa de temas; si el
repo se abre al publico, revisar (o vaciar) este documento antes.

Nota tecnica: este documento no lleva vallas de codigo a proposito (se paso al
repo por cat); los fragmentos van con sangria de 4 espacios.

## 1. Formato real del examen

- 17 preguntas en 4 horas, en los dos intentos: unos 14 minutos por pregunta de media.
- El voucher da 3 intentos.
- Es la version RHEL 10 (EX294). El curso oficial es RH294 / AU294; el curso en
  espanol del catalogo llega como maximo a RHEL 9.
- La sintaxis YAML y la documentacion de Ansible no cambian entre RHEL 9 y 10;
  lo que cambia es el entorno, y por eso la preparacion con RHEL 9 no se pierde del todo.
- Se puede usar ansible-doc, pero algunas cosas son memoria pura.
- Valoracion de Emilio: no es dificil, pero hay cosas que, si no las dominas,
  te destrozan, y el tiempo es el gran handicap.

## 2. La trampa del entorno (lo más valioso del hilo)

- El examen se hace desde un devcontainer en VS Code.
- NUNCA hacer ssh a las maquinas gestionadas desde el devcontainer: rompe el
  SSH y la unica solucion es rehacer la maquina entera y empezar el examen de
  cero. A Emilio le pillo a las 3 horas (lo hizo por costumbre) y le costo el
  primer intento.
- Si dan un usuario especifico para ssh, pero solo desde la terminal de la
  propia maquina gestionada.
- Vias validas para verificar el trabajo:
  - comandos ad-hoc con ansible
  - ansible-playbook --check (mejor con --diff)
  - la terminal de la maquina con el usuario especifico

## 3. Las 17 preguntas (de memoria, sin orden exacto)

| # | Tema | Notas |
|---|------|-------|
| 1 | Inventory y ansible.cfg | Piden grupos children. En el cfg: inventory, collections_path, roles_path |
| 2 | Repositorios | ansible.builtin.yum_repository; te dan los datos |
| 3 | Paqueteria por grupos de hosts | Enlaza con la 6 |
| 4 | ansible-galaxy con requirements.yml | Lo montas tu; te dan la URL |
| 5 | Rol apache | Se crea con ansible-galaxy; httpd y firewalld started+enabled, excepcion http, index.html.j2 |
| 6 | Rol de balanceo | Usa lo instalado en la 3. Casi solo hay que llamarlo; OJO a los README.md |
| 7 | Cifrar fichero de claves con ansible-vault | Con contrasena |
| 8 | Usuarios y grupos | Segun la maquina, con las contrasenas cifradas de la 7 |
| 9 | Recifrado (rekey) | Cambiar la contrasena del vault |
| 10 | Cron cada 2 minutos | Con un usuario concreto |
| 11 | LVM con Ansible | El mas complejo con diferencia: piden muchas cosas a la vez |
| 12 | Particion normal, sin LVM | |
| 13 | SELinux y contextos | |
| 14 | Informe de hardware | ansible_facts volcados en una plantilla Jinja2 por host |
| 15 | Plantilla Jinja2 para /etc/hosts por grupo | Tambien tiene su complejidad |
| 16 | Directorios, enlaces simbolicos, permisos y contenido | ansible.builtin.copy |
| 17 | Timesync | Con el rol redhat.rhel_system_roles.timesync |

- Dependencias entre preguntas: 3 -> 6 (lo instalado en la 3 se reutiliza) y
  7 -> 8 -> 9 (el vault de la 7 se usa en la 8 y se recifra en la 9).
- Aviso: en un intento pidieron modulos de redhat.rhel_system_roles sin dar el
  .tar.gz para instalarlos. Conviene saber comprobar que hay disponible:

    ansible-galaxy collection list
    ansible-doc -l | grep <tema>

## 4. Mapa de cobertura con RHCE_Lab v1.10.0

| # | Tema | Estado en el lab | Pieza que falta |
|---|------|------------------|-----------------|
| 1 | Inventory + cfg | parcial (inventory propio de containers) | banco: ejer_01 |
| 2 | yum_repository | hueco | checker check_repo |
| 3 | Paqueteria | cubierto (check_package, practica_01) | - |
| 4 | requirements.yml | hueco | banco: ejer_04 + check de roles/colecciones |
| 5 | Rol apache | casi (role_webserver + check_service/file) | firewalld |
| 6 | Rol balanceo | hueco facil (llamar un rol) | banco: ejer_06 |
| 7 | Vault | hueco | checker check_vault |
| 8 | Usuarios y grupos | cubierto (check_user, check_group) | - |
| 9 | Rekey | hueco | variante de check_vault |
| 10 | Cron | cubierto (check_cron) | - |
| 11 | LVM | cubierto (check_lvm) | - |
| 12 | Particion | cubierto (check_filesystem) | - |
| 13 | SELinux | cubierto (check_selinux_fcontext) | - |
| 14 | Informe hw | cubierto (check_file con contains) | - |
| 15 | hosts.j2 | cubierto (check_file) | - |
| 16 | Dirs/symlinks | casi (check_file, check_permissions) | symlink explicito |
| 17 | Timesync | hueco | checker check_timesync |

Balance: 8 de 17 cubiertos de pleno derecho, 3 casi, 6 huecos (2, 4, 6, 7, 9 y 17).
Los huecos se cierran con 4-5 checkers nuevos (repo, vault, timesync, firewall,
symlink/colecciones) y el banco de ejercicios del LOTE 40.

## 5. Higiene de los apuntes (erratas que en examen valen puntos)

Los dos ficheros van escritos a mano y llevan erratas que, tal cual, no parsean:

- groups['dev] sin cerrar la comilla (paqueteria por grupos, primer fichero).
- ansible.builtin.dnf sin los dos puntos finales en un task.
- --vault-pasword-file en vez de --vault-password-file.
- selinux_restore_dirs_ con guion bajo final.

Leccion: en el examen, ansible-playbook --syntax-check antes de ejecutar nada.
Caza este tipo de erratas en segundos y regala la correccion.

## 6. Reglas de oro (memoria de examen)

1. Nunca ssh desde el entorno del examen. Verificar con ad-hoc, con
   --check --diff o desde la terminal de la maquina con el usuario dado.
2. ansible-doc -l | grep <tema> y ansible-doc -s <modulo> antes de escribir de memoria.
3. Leer SIEMPRE los README.md de los roles que dan hechos.
4. --syntax-check antes de ejecutar; --check --diff antes de aplicar.
5. Ritmo: unos 14 minutos por pregunta; LVM y las plantillas se comen el
   margen: marcar y volver.
6. Si una pregunta pide un rol de redhat.rhel_system_roles, comprobar antes
   con ansible-galaxy collection list que la coleccion esta disponible.

## 7. Decisiones para el lab (acordado tras el analisis)

- Clonamos el ESQUEMA del examen (17 tareas encadenadas, dependencias, reloj
  de 4 h), no los enunciados.
- Los dos ficheros originales se quedan fuera del repo (NDA).
- LOTE 40: banco de ejercicios propio, un ejercicio por tema, con las dos
  variantes cuando las hay (hwreport por copy content vs por lineinfile;
  vault con --vault-password-file vs interactivo; issue con condicional
  Jinja2 vs tasks por grupo).
- LOTE 41: modo simulacro completo (inventario servera-serverd con
  dev/test/prod/balancers/webservers, reloj de 4 h, grade final unico).
- Serie: episodio 03 = estrategia de examen (tiempo, entorno, ansible-doc);
  episodio 04 = LVM de principio a fin; episodio 05 = plantillas, loops y hostvars.
