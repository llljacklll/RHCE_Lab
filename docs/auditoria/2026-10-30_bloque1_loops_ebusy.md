# Ficha — Bloque 1: EBUSY en fake-disks (incidente 16/17) — CERRADA
2026-10-30 · v1.12.3 (0c30163) · Recuperación B 12:40 · Re-gate 17/17 · running x3

## Cronología probada
1. ~08:04 UTC: fake-disks falla en node2/3 (EBUSY re-adjuntando loops ya ocupados).
2. 10:26:17-33: restart manual node1 → convergencia 10s sin liberar loop0/1 → losetup EBUSY → status=1. Muerte ANTES de wipefs.
3. 12:08: firma LVM2_member intacta en disk1.img (SCiDqb-...-uHTFE0); node1 sin loops; node2/3 loops correctos con unidad failed.
4. 12:40: guard → attach loop0/loop1 → vgchange -ay → PV UUID = SCiDqb (= P1) → re-aplicar exam_003 → 17/17.

## Veredictos
- I1  EBUSY antes de wipefs .................. confirmada y cerrada
- N1  failed node2/3 ......................... cerrada: cosmético, loops ya adjuntados
- N2  AUTOCLEAR .............................. refutada (autoclear=0; detach explicito posterior)
- B1  wipefs incondicional del nodo .......... confirmada (P0)
- B2  setup_docker_dns borra daemon.json ..... confirmada
- B3  fake-disks no idempotente (nueva) ...... confirmada (P0)
- R1  wipefs silencia errores ................ confirmada (P1)
- N3  sin rescate host tras restart manual ... confirmada (P2)
- N4  contenedores privilegiados ven /dev .... riesgo documentado
- O1  VG recuperado sin LVs (VFree=VSize=1020M); solución re-aplicada completó
- O2  lab_disks_release no desactiva DM → fuga de loop N+ en down/up (nueva, P1)
- R1b residual: transición "VG con LV activa" → "VG sin LVs" sin traza; no afecta veredictos

## Hechos clave
- DM y loops son globales al host: sobreviven al contenedor. Titular patrón demostrado (Q2):
  vg_node2-lv_datos→7:2, vg_node3-lv_datos→7:4 (linear 1024000 sect = 500M).
- Identidad: loop0 [0049]:26864664, loop1 [0049]:26864665 = pares node1 (P4). Seis slots correctos.
- Evidencia: evidencia-20261030/{disk1,disk2}_head.img, md5 d45c02cf... / b2d1236c...

## Backlog v1.12.4 (sin tocar v1.13.0)
P0 quitar wipefs del nodo (borrado fresh solo en anfitrión, tras marcador y verificación)
P0 attach idempotente: loop ya apuntando al fichero correcto (dev:inode) → no tocar; mal backing → liberar (con DM) y re-adjuntar; nunca borrar
P1 lab_disks_release: desactivar LVs/DM antes del detach; exigir losetup -a vacío
P1 errores del borrado fresh visibles (sin || true); éxito solo verificado
P2 doctor: pista de rescate tras docker restart manual
