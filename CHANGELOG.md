# CHANGELOG — RHCE Lab

Registro de cambios notables del proyecto. Formato basado en
Keep a Changelog; versionado SemVer (vMAYOR.MENOR.PARCHE).
Las versiones anteriores a v1.3.4 son pre-historia del repo.

## v1.15.0 - saga 15B: G5/G6/G7 en el anti-huerfanos y play 0 explicito

Fecha: 2026-11-04. Cierra la saga 15B: tres puertas nuevas
en core/lint_pool.sh y una enmienda de explicitud en el banco.

- core/lint_pool.sh: G5 valida cabeceras canonicas de soluciones/*.yml
  (37 ficheros, sobre el canon de la v1.14.1); G6 valida el esquema de
  scenarios/task_pool.yml (ids, prefijos de dificultad, checks y
  checkers alineados: 37 tareas, 51 checks); G7 exige hosts y become
  explicitos dentro de la allowlist en los 37 plays del banco.
  G1-G4 sin cambios.
- Bateria hermetica de 16 fixtures via LINT_POOL_ROOT (P00, N01-N12,
  R01-R03), sin lab, sin docker y sin tocar el state/ real.
- soluciones/hard_block_rescue.yml: become: false explicito en play 0
  con comentario veraz (Opcion A: decision didactica explicita, sin
  excepcion en G7); play 1 y entregable literal intactos.
- CI: .github/workflows/ci.yml ya invocaba core/lint_pool.sh en su
  puerta 5/5 Anti-huerfanos; el workflow no cambia y, al ganar G5-G7
  el script, corren en CI desde este commit.
- Evidencia: hitos/15B_cierre_saga.txt.

## v1.14.1 - canon de cabeceras del banco (precondicion de la puerta G5)

Fecha de aplicacion: 2026-11-03. Fecha de documentacion: 2026-11-04.
Entrada retroactiva: el canon de cabeceras de la tarde del 3 no tuvo
entrada propia; se documenta para que el registro cubra la cadena
completa de la saga 15B.

- soluciones/*.yml: cabeceras normalizadas al formato canonico (37/37,
  695f8f6); canon de longitud de cabecera - familia 78 (12 ficheros,
  b57da1c); L3 canonico en los 13 ficheros con anotacion Task Pack
  (0f8357c; 13 files changed, 13 insertions, 13 deletions).
- Solo cabeceras: el contenido didactico de los plays queda intacto.

## v1.14.0 - saga 15A: webui con PyYAML perezoso y regla UTF-8

Fecha: 2026-11-03. Cierra los dos pendientes de hitos/14E_cierre_saga.txt (webui
require_pyyaml propio con pruebas que no tocan el arranque del lab,
dictamen #10 R3; y la parte del backlog historico de parser YAML propio y
reglas UTF-8, dictamen #6).

- webui/webui.py: muere el parser regex propio; lab_state y exam_tasks
  leen con yaml.safe_load perezoso (raiz mapping, dictamen #8; raiz no
  mapping, YAML roto o vacio -> vacio seguro sin traceback). Mueren
  _num_with_key, TASK_ID_RE y DESC_RE; read_solution y SCORE_RE intactos.
- Guardia PyYAML propia: sin el paquete la web NO se cae; degrada la
  tarjeta de examen y avisa con el remedio canonico (JSON warning una
  vez por proceso + stderr): bash scripts/vm_bootstrap.sh
- core/exam_random.sh: yaml.dump(..., allow_unicode=True) (regla UTF-8,
  dictamen #6); retrocompatible via safe_load con el formato escapado.
- tests/pruebas_webui.sh (nueva): bateria hermetica de 16 casos, sin
  lab, sin docker y sin tocar el state/ real (dictamen #10, R3).

Sigue en backlog: comprobaciones de los activos didacticos (sin fecha).

## v1.13.0 (14C-a, V-1): Validador del banco y puerta CI 6/6
- Nuevo `core/valida_banco.sh`: formato, esquema y cruces del banco de tareas (capas A/B/C).
- Nueva puerta `6/6 Banco` en `.github/workflows/ci.yml`, junto a la `5/5 Anti-huerfanos`.
- Evidencia: `hitos/14Ca_positivo.txt`, `hitos/14Ca_negativos.txt`, `hitos/14Ca_lint.txt`.

## v1.13.1 (14C-b, V-2): PyYAML como dependencia de consumidores perezosos
- `lab.sh` deja de exigir PyYAML en el arranque (aviso no bloqueante): `up`/`down`/`ps`/`logs`/ayuda operan sin el.
- Guardias `require_pyyaml` en los consumidores reales (`exam`, `exam_random`, `lint_pool`), con remedio unico: `bash scripts/vm_bootstrap.sh`.
- Preflight anti half-start en `exam.sh`: YAML parseable y no vacio antes de tocar `state/current_exam.yml`.
- Evidencia: `hitos/14Cb_*.txt` (baterias 11/11 y 7/7, con shim y con el lab arriba/abajo).

## v1.13.2 (14C-c, V-3): Verificacion real de importacion en el bootstrap
- La fase 6 de `scripts/vm_bootstrap.sh` verifica `import yaml` (rpm instalado no implica importable); el `fail` apunta a la instalacion canonica.
- Aceptacion con ciclo completo: `rpm -e --nodeps python3-pyyaml` -> bootstrap -> import OK -> segunda corrida idempotente.
- Evidencia: `hitos/14Cc_2_pyyaml_en_bootstrap.txt`.

## v1.13.3 (14C-d, dictamen #8): Raiz mapping exigida en los preflights
- La guardia exige documento YAML con raiz tipo mapping: lista/escalar/vacio se rechazan de forma segura (antes, un `current_exam.yml` en lista pasaba `safe_load` y rompia `d.get` -> half-start).
- `time_limit` vacio sigue admitido (practica libre legitima); `require_pyyaml` se mantiene como control de disponibilidad, no como validador.
- Evidencia: `hitos/14Cd_dictamen8_mapping.txt` (9/9, E2E con el lab arriba).

**Pruebas globales (14D):** bateria cruzada V-1/V-2/V-3 + auditoria Q4 sobre el arbol final (perimetros por commit, alcance total, name-status, modos git, whitelist de 10 consumidores YAML, gates 5/6, guardias con shim, bootstrap idempotente, `state/` byte a byte): 14/14 VERDE. Detalle reproducible en `hitos/14D_informe_cruzado.txt`. Etiqueta de release: `v1.13.4`.

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
