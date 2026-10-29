# CHANGELOG — RHCE Lab

Registro de cambios notables del proyecto. Formato basado en
Keep a Changelog; versionado SemVer (vMAYOR.MENOR.PARCHE).
Las versiones anteriores a v1.3.4 son pre-historia del repo.

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
