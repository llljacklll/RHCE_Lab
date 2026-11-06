# RHCE Lab — Simulador del examen EX294 (Red Hat Certified Engineer)

[![CI](https://github.com/llljacklll/RHCE_Lab/actions/workflows/ci.yml/badge.svg)](https://github.com/llljacklll/RHCE_Lab/actions/workflows/ci.yml)
[![Licencia: CC BY-NC-SA 4.0](https://img.shields.io/badge/Licencia-CC%20BY--NC--SA%204.0-lightgrey.svg)](LICENSE)

Simulador completo del examen de certificación **RHCE (EX294)** basado en
**Ansible Automation**, ejecutado 100% sobre contenedores Docker para ofrecer
un entorno aislado, reproducible y sin riesgo para tu máquina.

- **1 nodo control** (Ansible Core 2.16) + **3 nodos managed** (AlmaLinux 10 con systemd real)
- Motor de exámenes con **cronómetro y anti-trampas**
- Corrección automática por **plugins** (paquetes, usuarios, servicios, ficheros, LVM, cron...)
- Generador de **exámenes aleatorios** desde un banco de tareas
- **Consola web** (`./lab.sh web`): genera el examen, cronómetro, enunciados, terminal del nodo de control y corrección, todo desde el navegador
- **Aprende y practica**: prácticas guiadas comentadas y una serie que resuelve los exámenes del lab paso a paso

## Inicio rápido

```bash
git clone https://github.com/llljacklll/RHCE_Lab.git && cd RHCE_Lab
./lab.sh up     # levantar el lab; auto-prepara el host si faltan dependencias
./lab.sh test   # batería del motor → TODO PASS (0 FALLIDOS)
./lab.sh web    # (opcional) consola web en http://127.0.0.1:8888
```

¿Primera instalación en una MV limpia? Ve a
[Instalación desde cero](#instalación-desde-cero-mv-limpia-o-snapshot-revertido).
¿Quieres practicar sin examinarte? Ve a [Aprende y practica](#aprende-y-practica).

## Características

| Pilar | Descripción |
|---|---|
| Infraestructura real | 4 contenedores con systemd, IPs fijas (172.20.0.10-13) y red dedicada |
| Corrección modular | Plugins en `core/checkers/` validan cada tarea en los 3 nodos |
| Exámenes aleatorios | `./lab.sh exam --random N` genera exámenes únicos desde `scenarios/task_pool.yml` |
| Anti-trampas | Cronómetro persistente en `state/exam_status.yml`: si expira, `grade` se bloquea |
| Logs persistentes | Cada corrección deja un informe en `state/results/` |
| Discos LVM | Cada nodo arranca con **su propia pareja** de discos de 1GB (2GB por nodo): node1 → `/dev/loop0-1`, node2 → `/dev/loop2-3`, node3 → `/dev/loop4-5` |
| Autoarranque total | `lab.sh` auto-prepara el host si faltan dependencias; cada contenedor monta sus discos y aplica su filtro LVM solo, al arrancar (systemd) |
| Consola web | `./lab.sh web` sirve el panel en `127.0.0.1:8888` (acceso remoto por túnel SSH, cero firewalld): generar, cronometrar, resolver con vim y terminal real, y corregir — [docs/WEBUI.md](docs/WEBUI.md) |
| Prácticas guiadas | Playbooks comentados en `ansible/playbooks/practicas/` (paquetes/servicios y roles): ejecución real contra los 3 nodos, sin cronómetro ni corrección |
| Serie didáctica | [docs/SERIE_EXAMEN.md](docs/SERIE_EXAMEN.md): cada examen del lab resuelto paso a paso, con plantilla para tus propios episodios |

## Aprende y practica

El material de aprendizaje del LOTE 38 **no toca** la batería de exámenes ni
el estado del lab: se ejecuta con el `run` de siempre y se corrige leyendo la
salida de Ansible, sin cronómetro ni `grade`.

### Prácticas guiadas (`ansible/playbooks/practicas/`)

Playbooks comentados, pensados para leerlos **antes y después** de ejecutarlos:

```bash
./lab.sh run practicas/practica_01_paquetes_servicios.yml   # dnf + lineinfile + service + handler
./lab.sh run practicas/practica_02_roles.yml                # rol role_vsftpd + precedencia de variables
```

- **practica_01 — paquetes y servicios**: instala `vsftpd` y `tree` con
  `dnf`, configura el acceso anónimo con `lineinfile`, deja el servicio
  `started + enabled` y reinicia mediante un **handler** solo cuando la
  configuración cambió.
- **practica_02 — roles**: lo mismo empaquetado como **rol** completo
  (`role_vsftpd`: defaults, tasks, template y handlers) y la lección clave
  para el examen: las `vars` del play **sobrescriben** los `defaults` del rol.

Ejecuta cada una **dos veces**: la primera debe salir con `changed > 0`
(instala, configura y dispara el handler) y la segunda con `changed=0` —
esa es la **idempotencia**, la propiedad que define a un playbook bien
escrito. Protocolo de 15 minutos y verificación manual de cada estado:
[ansible/playbooks/practicas/README.md](ansible/playbooks/practicas/README.md)

### Serie "Resolviendo el EX294" (`docs/serie/`)

Cada episodio resuelve un examen del laboratorio como lo harías el día del
examen: análisis del enunciado → esqueleto del playbook → solución comentada
→ comprobación → errores típicos → variaciones.

- [docs/SERIE_EXAMEN.md](docs/SERIE_EXAMEN.md) — índice de la serie y cómo usarla
- [docs/serie/episodio_01.md](docs/serie/episodio_01.md) — exam_001 (Apache + usuarios) resuelto de principio a fin
- [docs/serie/plantilla_episodio.md](docs/serie/plantilla_episodio.md) — plantilla de 8 secciones para tus propios episodios

> **Consejo**: resuelve primero y lee después. Los `exam_00X.yml` de
> `ansible/playbooks/` y las soluciones de la serie son spoilers.

## Prerrequisitos del host (MV Rocky / Alma / RHEL / CentOS 9-10)

El escenario soportado es una **MV de la familia EL 9-10** con:

- Docker Engine 24+ y plugin **compose v2**
- `python3` + `python3-pyyaml` (generador de exámenes aleatorios)
- `git` (para clonar y contribuir)
- ~4GB de RAM libres (las imágenes pesan ~1.2GB)

**Todo se prepara con un solo comando** (idempotente, re-lanzable):

    sudo bash scripts/vm_bootstrap.sh

Detecta la familia EL, escribe el repo oficial de Docker CE, instala
engine + compose + pyyaml, habilita docker.service, **registra los
`/dev/loop0-15` del kernel** (EL10 no los crea al arrancar y son
imprescindibles para los discos LVM del lab) y los deja **persistentes**
con la unidad `rhce-lab-loop.service` (sobreviven a reinicios de la MV).
Cierra con una batería de verificaciones del host.

**Desde v1.2.0 no hace falta ejecutarlo a mano:** cualquier `lab.sh`
detecta dependencias faltantes y lo lanza automáticamente.

| Requisito | Verificación |
|---|---|
| Docker Engine 24+ | `docker version` |
| Compose v2 (plugin) | `docker compose version` |
| /dev/loop0-15 registrados | `ls /dev/loop[0-9]*` |
| rhce-lab-loop.service | `systemctl is-active rhce-lab-loop` |
| cgroup v2 | `stat -fc %T /sys/fs/cgroup` → `cgroup2fs` |

> Se trabaja como root y SELinux puede quedar **Enforcing**: los
> contenedores del lab son privileged, no hace falta tocarlo.

> **¿WSL2?** El lab nació en WSL2, pero **ya no es el escenario
> soportado**: el kernel de WSL2 no trae nf_tables (firewalld forzado a
> modo offline) y la gestión de loop devices difiere de la de una MV.
> Usa una MV Rocky 10: se levanta en minutos con cualquier hipervisor.

## Instalación desde cero (MV limpia o snapshot revertido)

```bash
# 1) git y credenciales
sudo dnf -y install git
git config --global credential.helper store   # PAT la primera vez que pushees

# 2) Clonar
git clone https://github.com/llljacklll/RHCE_Lab.git
cd RHCE_Lab

# 3) Levantar. Si el host no tiene Docker/compose o /dev/loopN, lab.sh
#    lanza scripts/vm_bootstrap.sh él solo; .vault_pass se crea si falta
./lab.sh up        # compila imágenes: requiere internet (~5-10 min la 1ª vez)

# 4) Verificación integral de infraestructura: TODO en verde
bash scripts/smoke_test.sh
```

> `vm_bootstrap.sh` sigue disponible a mano (`sudo bash scripts/vm_bootstrap.sh`,
> idempotente y re-lanzable) por si prefieres dejar el host a punto antes.
> Para volver a un **snapshot antiguo** de la MV, mira la sección siguiente.

## Restaurar la MV / recuperar un snapshot

Flujo probado de punta a punta con una MV restaurada **sin Docker y sin
/dev/loopN**: el lab auto-bootstrapea el host, recompila desde cero y
queda prístino.

**El atajo** (dependencias si faltan + saneo git + `up` + `doctor`, en un solo comando):

```bash
bash bootstrap.sh
```

> ATENCIÓN: el paso git de `bootstrap.sh` hace `fetch + reset --hard
> origin/main` + `clean -fd`: DESCARTA sin piedad cambios locales sin
> commitear y borra lo untracked. Si el snapshot lleva trabajo que
> quieras conservar, guárdalo ANTES (commit o `git stash push`): el
> remoto manda y el bootstrap no pide permiso.

**El flujo manual** equivalente, para saber qué pasa dentro:

```bash
cd /root/RHCE_Lab

# Solo si el snapshot tenía cambios sin commitear (sin esto, el pull aborta):
git stash push -m "locales del snapshot" -- lab.sh

git pull --ff-only
./lab.sh reset
```

- `reset` destruye contenedores, red, volúmenes e **imágenes antiguas** del
  snapshot: nunca mezclas binarios viejos con código nuevo.
- Los discos quedan **prístinos** (wipe con reintentos) y el filtro LVM se
  aplica por nodo → los checkers LVM **fallan honestos** hasta que crees la VG.
- Si falta algo en el host (Docker, loops...), lab.sh lanza `vm_bootstrap.sh`.

## Uso de la CLI

| Comando | Descripción |
|---|---|
| `./lab.sh up` | Construir imágenes y levantar (lento, requiere internet) |
| `./lab.sh start` / `stop` | Levantar sin recompilar / detener conservando datos |
| `./lab.sh down` | Destruir contenedores, red e imágenes (limpieza total) |
| `./lab.sh reset` | Destruir y reconstruir todo (auto-prepara el host si faltan deps) |
| `./lab.sh doctor` | Chequeo rápido: docker, contenedores, discos por nodo y filtro LVM |
| `./lab.sh autostart` | Instalar el autoarranque del lab con la MV (unidad `rhce-lab.service`) |
| `./lab.sh shell` | Entrar por SSH al nodo control |
| `./lab.sh web` | Lanzar la consola web (`127.0.0.1:8888`; remoto por túnel SSH: [docs/WEBUI.md](docs/WEBUI.md)) |
| `./lab.sh run <playbook.yml>` | Ejecutar un playbook contra los 3 nodos |
| `./lab.sh run --vault <playbook.yml>` | Ídem, pidiendo contraseña de Vault |
| `./lab.sh exam` | Ayuda del modo examen |
| `./lab.sh exam easy/exam_001.yml` | Cargar examen estático (arranca cronómetro) |
| `./lab.sh exam --random 4` | Generar examen aleatorio de 4 tareas |
| `./lab.sh exam --start` | Empezar el examen generado (arranca cronómetro) |
| `./lab.sh grade` | Corregir el examen activo (detiene cronómetro) |
| `./lab.sh test` | Batería de pruebas automática |
| `./lab.sh up --dns 1.1.1.1,8.8.8.8` | Forzar DNS de Docker (redes corporativas) |

## Flujo de un examen

1. **Cargar**: `./lab.sh exam hard/exam_003.yml` (o `--random N`).
2. **Resolver**: escribe TU playbook en `ansible/playbooks/` (p. ej.
   `mi_solucion.yml`) y ejecútalo con `./lab.sh run mi_solucion.yml`.

   > Los ficheros `exam_00X.yml` existentes son **soluciones de
   > referencia** (spoilers). Para practicar de verdad, parte de cero.

3. **Corregir**: `./lab.sh grade` → resultado por tareas + informe en
   `state/results/`. Si el cronómetro expiró, la corrección se bloquea.

> ¿Calentamiento guiado antes de tu primer examen?
> [Aprende y practica](#aprende-y-practica).

## El examen desde la web

Todo el flujo anterior se puede hacer desde el navegador:

    ./lab.sh web        # sirve http://127.0.0.1:8888 (solo loopback)

- **Generar** el examen (dificultad `mixed|easy|medium|hard` y N tareas) y
  **cronómetro** en pantalla, con aviso a los 15 y 5 minutos.
- **Enunciado siempre visible**: tarjeta de tareas con `[editar]` (abre
  `vim` apuntando a `ansible/playbooks/<tarea>.yml` EN el terminal web
  del nodo control) y `[mostrar solucion]` (modo aprendizaje, abajo del
  todo). Los botones permanecen ocultos hasta que arranca el cronómetro.
- **Terminal real** del nodo de control (xterm.js) dockado al lado de la
  salida del simulador: aquí se HACE el examen.
- **Grade / Doctor** con la salida ANSI a color; el chip de cabecera
  recuerda la última nota.
- Acceso remoto por **túnel SSH** reutilizando el único puerto abierto de
  la MV: cero firewalld.

Detalles de seguridad, atajos de túnel, operativa e interior del
mecanismo: [docs/WEBUI.md](docs/WEBUI.md). Arquitectura general del
proyecto: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Motor de
exámenes: [docs/EXAMS.md](docs/EXAMS.md).

## El Vault del laboratorio

`ansible/files/secrets.yml` (encriptado, viaja en git) contiene cifrada
la variable `db_password`, usada por el examen hard. La contraseña vive
en `ansible/files/.vault_pass` (**no** viaja en git: cada instalación la
crea con `./scripts/create_vault.sh`; desde v1.2.0 `lab.sh` la crea
automáticamente si falta).

- **Contraseña del vault**: `RhceLab2026` (didáctica; en el EX294 real
  te la entregan en el enunciado, igual que aquí)
- **Valor de `db_password`**: `SecretPassword123`

Ejecución de exámenes con vault: `./lab.sh run --vault exam_003.yml`

## Smoke test completo (primera sesión)

```bash
bash scripts/smoke_test.sh              # infra: contenedores, ping, discos, vault
./lab.sh test                           # batería del motor → TODO PASS

./lab.sh exam easy/exam_001.yml         # examen fácil
./lab.sh run exam_001.yml
./lab.sh grade                          # esperado: 3/3 APROBADO

./lab.sh exam medium/exam_002.yml       # examen medio (roles + jinja2)
./lab.sh run exam_002.yml
./lab.sh grade                          # esperado: 2/2 APROBADO

./lab.sh exam hard/exam_003.yml         # examen hard (vault + LVM)
./lab.sh run --vault exam_003.yml       # contraseña: RhceLab2026
./lab.sh grade                          # esperado: 5/5 APROBADO

./lab.sh exam --random 4                # examen aleatorio
./lab.sh exam --start
./lab.sh grade
```

## Notas técnicas

- **Autoarranque (DEP-GUARD)**: al ejecutar cualquier `lab.sh`, si faltan
  Docker, compose, pyyaml o `/dev/loop0`, se lanza `vm_bootstrap.sh`
  automáticamente (idempotente). También se crea `.vault_pass` si falta.
- **Firewalld en modo offline**: los playbooks usan `offline: true` en
  `ansible.posix.firewalld`, que edita los XML directamente sin demonio.
  Es determinista y portable (no depende del daemon ni de nf_tables).
- **LVM sobre loop devices**: los discos son loopback de 1GB. Los loop
  devices son **recursos globales del kernel**, así que cada nodo usa
  una **pareja fija** (node1: `loop0/1`, node2: `loop2/3`, node3:
  `loop4/5`; control ninguno) y `setup-disks.sh` nunca hace
  `losetup -D`. Los exámenes y sus soluciones usan solo el primer
  disco de cada pareja (`loop0/2/4`); el segundo (`loop1/3/5`) queda
  como disco de práctica libre del alumno. Como EL10 no crea `/dev/loopN` al arrancar,
  `vm_bootstrap.sh` los registra vía `LOOP_CTL_ADD` y
  `rhce-lab-loop.service` los mantiene tras reinicios. Sin udev,
  `lvcreate` requiere `--wipesignatures n --zero n` (los playbooks de
  referencia ya lo aplican). No se soportan particiones
  (`/dev/loop0p1`): el LVM se hace sobre el disco raw.
- **Filtro LVM por nodo (checkers honestos)**: la imagen hornea un
  `lvmlocal.conf` con `filter`/`global_filter` para que cada nodo solo
  vea **sus** discos, y `fake-disks.service` ejecuta `setup-disks.sh` en
  el arranque de cada contenedor (systemd real). Un nodo no puede ver
  los PV de otro: los checkers LVM solo dan OK si la VG existe **en ese
  nodo** (en el lab prístino dan FAIL, como debe ser).
- **DNS**: la red es fija (172.20.0.0/24) para evitar caídas por caché
  de DNS de Docker. En redes corporativas: `./lab.sh up --dns <ips>`.
- **Consola web**: un único fichero Python stdlib (`webui/webui.py`)
  que actúa como mando a distancia del CLI: allowlist de acciones y
  `subprocess` sin shell; el servidor **nunca escribe estado**, solo
  lee `state/`. El terminal del nodo control viaja por un WebSocket
  artesanal sobre PTY con gate de Origin (anti drive-by), y xterm.js
  se sirve local desde `webui/static/` (sin internet). El detalle
  completo en [docs/WEBUI.md](docs/WEBUI.md).

## Historial de versiones

El detalle de cada LOTE está en [CHANGELOG.md](CHANGELOG.md) (formato
Keep a Changelog, versionado SemVer). Versión instalada del lab:

```bash
git describe --tags    # p. ej. v1.15.1
```

## Roadmap

- [x] Tareas de Block/Rescue en el task pool
- [x] Checker fino de SELinux (fcontext real)
- [x] Consola web del simulacro (generación, cronómetro, terminal y corrección)
- [x] Más exámenes estáticos (exam_004, exam_005 y exam_006 — LOTE 37)
- [x] Prácticas guiadas de paquetes/servicios y de roles (LOTE 38)
- [x] Serie "Resolviendo el EX294" + plantilla de episodios (LOTE 38)
- [ ] Más episodios de la serie (del exam_002 al exam_006)
- [ ] Prácticas guiadas de cron, LVM y SELinux
- [ ] Task Pack #2: nuevas tareas para el pool aleatorio

## Licencia

CC BY-NC-SA 4.0 — ver [LICENSE](LICENSE).

**Autor:** llljacklll · construido con asistencia de IA.
