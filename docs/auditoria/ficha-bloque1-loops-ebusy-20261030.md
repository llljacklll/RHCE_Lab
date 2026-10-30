
## Visto bueno de diseño v1.12.4 (segunda opinión, 2026-10-30)
- Dictamen por cambio: wipefs del nodo fuera (P0) · attach idempotente por sysfs (P0) · setup_docker_dns preserva daemon.json (P0) · rescate no destructivo + diagnóstico fake-disks (P1) · verificación del borrado fresh (P1) · LVM off antes de liberar loops (P1 condicionado) · doctor detecta unidad failed (P2).
- Condiciones vinculantes: C-A pre-check exacto por par (OK/FREE/GHOST/CONFLICT; conflicto ⇒ diagnóstico, cero auto-reparación, no sacrificar LV activo) · C-B lvm_off verifica montajes y vgchange sin --force · C-C down = lvm_off (contenedores vivos) → compose down → liberar solo loops libres · C-D daemon.json por Python (conservar claves, dns vacío ⇒ retirar solo la clave, 1–2 IP, JSON inválido ⇒ abortar, atómico, reiniciar solo si cambia, octetos 0–255) · C-E fresh solo en anfitrión con verificación · C-F doctor con unidades failed + pistas de rescate.
- Enmienda al backlog: «si apunta a otro, liberar y re-adjuntar» queda sustituido por C-A.
- O1 parcialmente cerrado; R1b no cosmético → evidencia en evidencia-20261030/r1b/ (archivo LVM, seqno, journal, historiales) antes del próximo down/up.
- Gate de 12 escenarios aprobado; el release no se declara hasta demostrar restart, down y recreación.
- Alcance congelado: bootstrap.sh fuera de v1.12.4; v1.13.0 y PyYAML separados.
