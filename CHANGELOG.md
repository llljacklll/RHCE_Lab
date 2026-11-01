# CHANGELOG — RHCE Lab

Registro de cambios notables del proyecto. Formato basado en
Keep a Changelog; versionado SemVer (vMAYOR.MENOR.PARCHE).
Las versiones anteriores a v1.3.4 son pre-historia del repo.

## [v1.12.4] — 2026-11-01

### Added
- **core/v1124.sh**: overrides del dictamen de auditoría (2026-10-30), condiciones
  C-A..C-F: attach idempotente por sysfs (C-A), lvm_off sin --force con verificación
  de montajes (C-B), down = lvm_off (contenedores vivos) → compose down → liberar
  solo loops libres (C-C), daemon.json por Python preservando claves (C-D), fresh
  verificado en anfitrión (C-E) y doctor con detección de residuos device-mapper
  y pistas de rescate (C-F).
- **tests/**: arnés de pruebas r3/r4/r5, harness del parche (r5: doble run 130/0
  en MV real, pre-activación).
- Doctor: nueva línea de diagnóstico `[!!] device-mapper residual` con remedio
  sugerido (`./lab.sh reset`).

### Changed
- **core/docker.sh**: source de core/v1124.sh SIEMPRE al final, tras core/disks.sh
  (fallback dual de ruta) — los overrides pisan al código base sin tocarlo.

### Fixed
- **docker/setup-disks.sh**: pre-check exacto por par de discos (OK/FREE/GHOST/
  CONFLICT; conflicto ⇒ diagnóstico, cero auto-reparación), rescate no destructivo
  y verificación del borrado fresh en anfitrión.

### Verificación (MV real, 2026-11-01)
- Batería `./lab.sh test`: 17/17 en tres ejecuciones sobre código activado
  (post-up, post-restart y sobre el árbol etiquetado); idempotencia entre pasadas
  (RECAP changed=0 sobre residuos de la pasada anterior).
- Restart de los 4 contenedores: loops y filtros LVM sobreviven sin re-ejecutar up.
- Down con residuos DM reales: secuencia C-C íntegra, anfitrión verificado limpio
  (0 vg_*, 0 loops, 0 contenedores).
- Almacenamiento: las imágenes (2 × 1 GiB por nodo) viven dentro de cada nodo
  (`/opt/lvm_disks` en su namespace); el anfitrión no guarda nada fuera de docker.
- Evidencia íntegra en `hitos/` (commit f0fbfec); dictamen de diseño en 47d665e.

### Notas operativas (dictamen #6, 2026-11-01)
- Restart: los loops y filtros LVM de cada nodo sobreviven al reinicio de los
  contenedores; no hace falta re-ejecutar `up` para recuperarlos.
- Down: desactiva el LVM dentro de los nodos ANTES de retirar contenedores y
  libera únicamente los loops sin holders; verifica el estado final.
- Docker DNS: se conserva en `daemon.json` la configuración ajena al laboratorio
  y solo se gestiona la clave `dns`.
- Alcance del gate: los escenarios del banco se validan funcionalmente (batería);
  las reglas de transporte/formato del banco quedan fuera de v1.12.4 y pasan al
  backlog de v1.13.0 (parser YAML propio, reglas UTF-8, comprobaciones de los
  activos didácticos). Nunca mezclar gate de transporte con gate funcional.

## [v1.12.3] — 2026-10-30

### Fixed
- **saneo httpd reubicado a su sitio real**: el guard de v1.12.2 acabó dentro de
  `print_help()` en `lab.sh` (las anclas "Ejecutando / salida en vivo" no existen en
  `lab.sh` y el fallback `site.yml` pescó la línea de la ayuda). Reubicado donde de
  verdad se ejecuta el playbook: `core/test.sh`, dentro de `lab_test()`, justo antes
  de la llamada a `playbooks/site.yml` (la Fase que revienta con el 8080 ocupado por
  haproxy).
- La entrada de v1.12.2 prometía también un saneo "al cierre de `./lab.sh test`":
  esa segunda colocación nunca existió y se retira la promesa. El saneo pre-site.yml
  es idempotente y cubre el caso real (veneno `Listen 8080` residual).

### Notas
- **check_repo: sin bug**. El FAIL del smoke de v1.12.2 fue un uso incorrecto de la
  firma standalone del wrapper: `$1` es el NODO (`run_check.sh repo node1
  docker-ce-stable` devuelve OK), no el task_id. El contrato con grade.sh
  ($1=nodo, $2=name, $3=path) es correcto.
- Lección de gates: el wrapper standalone devuelve rc=0 aunque el checker falle;
  la validación SIEMPRE por la primera palabra del mensaje (OK/FAIL).
- El gate E2E de este release cazó además una primera colocación defectuosa del
  guard: quedó incrustado en la continuación de `\` del comando ansible-playbook,
  que se quedó sin playbook (16/17 antes del tag). Reubicado antes del inicio del
  comando y re-verificado; el veneno se limpió igualmente en esa corrida.

## [v1.12.2] — 2026-10-30

### Corregido
- **galaxy offline**: `redhat.rhel_system_roles` no se sirve en galaxy.ansible.com (API v3 `count=0`). `hard_timesync_role` construye un stub vendor mínimo (mismo FQCN + rol `timesync`, 1.22.1) con `ansible-galaxy collection build` y lo instala vía `requirements.yml` (`type: file`) — 100% offline.
- **exam_002 re-puertado a 8081**: forzar `http_port: 8080` choca con haproxy (0.0.0.0:8080 en los 3 nodos) y el handler de `role_webserver` dejaba httpd caído; sus checks (`package: httpd` + `index.html` con "Victor") no verifican el puerto, así que el cambio no afecta a la corrección.
- **saneo httpd en `test`**: los restos de `Listen 8080` con httpd caído reventaban la Fase 4 de la siguiente corrida. Saneo automático antes de ejecutar `site.yml` y al cierre de `./lab.sh test`.
- **LVM resiliente**: `setup-disks.sh` re-ejecutable revive loop devices/PV; los VG/LV del exam_003 se reconstruyen al re-forzar su solución.

### Añadido
- `core/checkers/run_check.sh`: wrapper standalone para depurar checkers fuera de `grade.sh` (replica el contrato de `_run_check`).
## [v1.12.1] — 2026-10-29

### Fixed

- fix(galaxy): PATH de la CLI bajo sudo (secure_path RHEL): symlinks ansible* en imagen + environment en soluciones

## [v1.12.0] — 2026-10-29

- feat(checkers): 6 plugins nuevos — repo, vault, timesync, firewall (dual), galaxy y symlink
- feat(pool): 9 tareas nuevas alineadas con el intel EX294 (repos, galaxy/requirements, vault create/rekey, timesync config y rol real, firewall, symlink, haproxy)
- fix(imagen): symlinks /usr/local/bin/ansible* -> /usr/bin (RUN find en Dockerfile + hot-patch live): soluciones del alumno con become no mueren por secure_path
- fix(soluciones): PATH explicito (environment) + become:false en las 4 soluciones CLI (galaxy x2, vault x2): sudo resetea el PATH a secure_path de RHEL sin /usr/local/bin y el modulo command caia con [Errno 2] ansible-galaxy (repro en sandbox con core 2.16.19)
- docs: 9 soluciones comentadas + filas del mapa en soluciones/README.md

## [v1.11.0] - 2026-10-29 — LOTE 39

- docs: INTEL_EX294.md (intel del examen real EX294 y mapa de cobertura) y episodio_02 de la serie (roles + Jinja2)

## [1.10.0] — 2026-10-29 (LOTE 38)

### Añadido
- Serie "Resolviendo el EX294": índice (`docs/SERIE_EXAMEN.md`),
  plantilla de episodio y episodio 1 (exam_001 resuelto paso a paso).
- Prácticas guiadas de playbooks (`ansible/playbooks/practicas/`):
  práctica 1 de paquetes/servicios (vsftpd con lineinfile y handlers)
  y práctica 2 de roles con el rol nuevo `role_vsftpd` (feedback de
  la comunidad: Ivan Rivera). Se ejecutan como los exámenes
  (`./lab.sh run practicas/...`) y NO tocan la batería.
- Este registro de cambios (CHANGELOG.md).
- README pulido para release: badge de CI, inicio rápido de 3 comandos,
  sección "Aprende y practica" y roadmap actualizado.

## [v1.9.0] — LOTE 37 + 36-E/36-F

### Añadido
- Tres exámenes estáticos nuevos: exam_004 (EASY: grupos, directorios
  y permisos), exam_005 (MEDIUM: SELinux fcontext persistente con
  semanage) y exam_006 (HARD: block/rescue, cron y storage compartido).
  La batería pasa de 14/14 a 17/17.
- Fase 0 de la batería: bash -n del árbol completo + gate IaC.

### Corregido
- Discos loop con un solo dueño: finalize deja de adjuntar loops en
  el host (raíz del EBUSY de 36-F); setup-disks convergente con
  reintento y eliminación del DM fantasma antes del attach.

### Documentación
- RUNBOOK: la batería es 0-FALLIDOS (17/17) y el banner lee la
  versión por git describe.

## [v1.8.3] — 36-D
- `lab.sh gate`: gate de transporte locale-proof (core/gate.sh) con
  ayuda y despacho.

## [v1.8.2] — 36-C
- `lab.sh wait`: poll SSH triple-usuario desde el control, para saber
  cuándo el laboratorio está realmente listo.

## [v1.8.1] — LOTE 35
- fcontext por semanage; entregable block_rescue; checker 1b.
- `nofail` en el montaje de hard_lvm_full.
- `pkill -P` mata el sleep hijo del cronómetro: sin sleeps huérfanos
  tras grade/down/nuevo examen.
- `run` condicional al TTY: site.yml scriptable sin tocar el modo
  interactivo ni el vault.
- Smoke LVM exigente: cuenta exacta de PV, falla si pvs rompe.

## [v1.8.0] — LOTE 34
- Puerta 5/5 anti-huérfanos en CI (core/lint_pool.sh) + ci.yml v2
  con 5 puertas.

## [v1.7.0] — LOTE 33-A
- 6 tareas nuevas en el banco de tareas.

## [v1.6.0] — LOTE 32
- Consola web en background por defecto; recordatorio de acceso.
- 6 tareas nuevas en el banco de tareas.
- Resolución de rutas del webui sin depender del cwd.

## [v1.5.0] — LOTE 27-30
- Consola web del simulacro (loopback + túnel SSH): terminal del
  nodo de control vía /ws (el examen SE HACE desde la web), enunciado
  siempre visible, vim auto-apuntado, UX del examen completa.
- Documentación completa del proyecto (LOTE 30).
- Guard n>=1 y cap honesto en la generación de exámenes.

## [v1.4.2]
- La batería corrige los tres exámenes fijos (Fase 5), no solo el 001.
- El banner cita el tag real; `grade` acepta la ruta del examen.
- Discos LVM reales de 1G por nodo.

## [v1.4.1]
- RUNBOOK de operación del laboratorio.
- El log de resultados lleva el id del examen.

## [v1.4.0]
- Los 11 checkers restantes hablan: FAIL con razón explicada.
- Contrato posicional del checker de ficheros.
- exam_003 migrado a LVM por nodo (vg_<nodo> + token __NODE__).
- LICENSE con el legalcode oficial de CC BY-NC-SA 4.0 (antes
  contenía el texto de CC0 por error).

## [v1.3.4] — Lote 11
- Higiene de documentación y UI: emojis retirados, scenarios y
  hosts.ini documentados a fondo, CI documentada.
