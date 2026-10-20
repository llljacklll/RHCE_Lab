# 🚀 RHCE Lab — Simulador del examen EX294 (Red Hat Certified Engineer)

Simulador completo del examen de certificación **RHCE (EX294)** basado en
**Ansible Automation**, ejecutado 100% sobre contenedores Docker para ofrecer
un entorno aislado, reproducible y sin riesgo para tu máquina.

- **1 nodo control** (Ansible Core 2.16) + **3 nodos managed** (AlmaLinux 10 con systemd real)
- Motor de exámenes con **cronómetro y anti-trampas**
- Corrección automática por **plugins** (paquetes, usuarios, servicios, ficheros, LVM, cron...)
- Generador de **exámenes aleatorios** desde un banco de tareas

---

## ✨ Características

| Pilar | Descripción |
|---|---|
| 🐳 Infraestructura real | 4 contenedores con systemd, IPs fijas (172.20.0.10-13) y red dedicada |
| 🧠 Corrección modular | Plugins en `core/checkers/` validan cada tarea en los 3 nodos |
| 🎲 Exámenes aleatorios | `./lab.sh exam --random N` genera exámenes únicos desde `scenarios/task_pool.yml` |
| ⏱️ Anti-trampas | Cronómetro persistente en `state/exam_status.yml`: si expira, `grade` se bloquea |
| 📝 Logs persistentes | Cada corrección deja un informe en `state/results/` |
| 💾 Discos LVM | Cada nodo arranca con **su propia pareja** de discos de 512MB (1GB por nodo): node1 → `/dev/loop0-1`, node2 → `/dev/loop2-3`, node3 → `/dev/loop4-5` |
| 🚀 Autoarranque total | `lab.sh` auto-prepara el host si faltan dependencias; cada contenedor monta sus discos y aplica su filtro LVM solo, al arrancar (systemd) |

## 📋 Prerrequisitos del host (MV Rocky / Alma / RHEL / CentOS 9-10)

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

## 🔧 Instalación desde cero (MV limpia o snapshot revertido)

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

## ♻️ Restaurar la MV / recuperar un snapshot

Flujo probado de punta a punta con una MV restaurada **sin Docker y sin
/dev/loopN**: el lab auto-bootstrapea el host, recompila desde cero y
queda prístino.

**El atajo** (docker si falta + `pull` + `up` + `doctor` en un solo comando):

```bash
bash bootstrap.sh
```

> Si el snapshot tenía cambios sin commitear, el `pull` interno de
> `bootstrap.sh` se lo salta: usa el flujo manual con `stash`.

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

## ⚡ Inicio rápido (host ya preparado)

```bash
./lab.sh up     # levantar (.vault_pass se crea solo si falta)
./lab.sh test   # batería de pruebas automática
```

## 🎮 Uso de la CLI

| Comando | Descripción |
|---|---|
| `./lab.sh up` | Construir imágenes y levantar (lento, requiere internet) |
| `./lab.sh start` / `stop` | Levantar sin recompilar / detener conservando datos |
| `./lab.sh down` | Destruir contenedores, red e imágenes (limpieza total) |
| `./lab.sh reset` | Destruir y reconstruir todo (auto-prepara el host si faltan deps) |
| `./lab.sh doctor` | Chequeo rápido: docker, contenedores, discos por nodo y filtro LVM |
| `./lab.sh autostart` | Instalar el autoarranque del lab con la MV (unidad `rhce-lab.service`) |
| `./lab.sh shell` | Entrar por SSH al nodo control |
| `./lab.sh run <playbook.yml>` | Ejecutar un playbook contra los 3 nodos |
| `./lab.sh run --vault <playbook.yml>` | Ídem, pidiendo contraseña de Vault |
| `./lab.sh exam` | Ayuda del modo examen |
| `./lab.sh exam easy/exam_001.yml` | Cargar examen estático (arranca cronómetro) |
| `./lab.sh exam --random 4` | Generar examen aleatorio de 4 tareas |
| `./lab.sh exam --start` | Empezar el examen generado (arranca cronómetro) |
| `./lab.sh grade` | Corregir el examen activo (detiene cronómetro) |
| `./lab.sh test` | Batería de pruebas automática |
| `./lab.sh up --dns 1.1.1.1,8.8.8.8` | Forzar DNS de Docker (redes corporativas) |

## 📝 Flujo de un examen

1. **Cargar**: `./lab.sh exam hard/exam_003.yml` (o `--random N`).
2. **Resolver**: escribe TU playbook en `ansible/playbooks/` (p. ej.
   `mi_solucion.yml`) y ejecútalo con `./lab.sh run mi_solucion.yml`.

   > ⚠️ Los ficheros `exam_00X.yml` existentes son **soluciones de
   > referencia** (spoilers). Para practicar de verdad, parte de cero.

3. **Corregir**: `./lab.sh grade` → resultado por tareas + informe en
   `state/results/`. Si el cronómetro expiró, la corrección se bloquea.

## 🔐 El Vault del laboratorio

`ansible/files/secrets.yml` (encriptado, viaja en git) contiene cifrada
la variable `db_password`, usada por el examen hard. La contraseña vive
en `ansible/files/.vault_pass` (**no** viaja en git: cada instalación la
crea con `./scripts/create_vault.sh`; desde v1.2.0 `lab.sh` la crea
automáticamente si falta).

- **Contraseña del vault**: `RhceLab2026` (didáctica; en el EX294 real
  te la entregan en el enunciado, igual que aquí)
- **Valor de `db_password`**: `SecretPassword123`

Ejecución de exámenes con vault: `./lab.sh run --vault exam_003.yml`

## 🧪 Smoke test completo (primera sesión)

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

## 🛠️ Notas técnicas

- **Autoarranque (DEP-GUARD)**: al ejecutar cualquier `lab.sh`, si faltan
  Docker, compose, pyyaml o `/dev/loop0`, se lanza `vm_bootstrap.sh`
  automáticamente (idempotente). También se crea `.vault_pass` si falta.
- **Firewalld en modo offline**: los playbooks usan `offline: true` en
  `ansible.posix.firewalld`, que edita los XML directamente sin demonio.
  Es determinista y portable (no depende del daemon ni de nf_tables).
- **LVM sobre loop devices**: los discos son loopback de 512MB. Los loop
  devices son **recursos globales del kernel**, así que cada nodo usa
  una **pareja fija** (node1: `loop0/1`, node2: `loop2/3`, node3:
  `loop4/5`; control ninguno) y `setup-disks.sh` nunca hace
  `losetup -D`. Como EL10 no crea `/dev/loopN` al arrancar,
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

## 🆕 Novedades de v1.2.0 (autoarranque total)

- **DEP-GUARD**: `lab.sh` detecta dependencias del host faltantes y
  auto-ejecuta `vm_bootstrap.sh` (probado en una MV restaurada sin Docker).
- **Discos idempotentes por nodo** + `fake-disks.service` (systemd) y
  `lvmlocal.conf` por nodo con filtro LVM → checkers honestos.
- **Wipe prístino con reintentos** de los discos en cada arranque/reset.
- **`.vault_pass` automático** en el primer uso.
- **`./lab.sh doctor`**: chequeo rápido del lab (docker, contenedores,
  discos por nodo y filtro LVM).
- **`./lab.sh autostart`**: instala `rhce-lab.service` (systemd) — el lab
  se levanta solo al arrancar la MV. Se quita con
  `systemctl disable rhce-lab`.
- **CI en cada push**: `bash -n`, validación de YAML, heredocs de python
  y consistencia de checkers.
- **Task Pack #1**: pool aleatorio renovado (14 tareas en 3 dificultades,
  con LVM multi-nodo sin choques de dispositivo).
- **Flujo de recuperación documentado** (restaurar MV → `pull` → `reset`).

## 🗺️ Roadmap

- [ ] Tareas de Block/Rescue en el task pool
- [ ] Checker fino de SELinux (fcontext real)
- [ ] Más exámenes estáticos

## 📜 Licencia

CC BY-NC-SA 4.0 — ver [LICENSE](LICENSE).

**Autor:** llljacklll · construido con asistencia de IA.
