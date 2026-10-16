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
| 💾 Discos LVM | Cada nodo arranca con **su propia pareja** de discos de 1GB: node1 → `/dev/loop0-1`, node2 → `/dev/loop2-3`, node3 → `/dev/loop4-5` |

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

~bash
# 1) git y credenciales
sudo dnf -y install git
git config --global credential.helper store   # PAT la primera vez que pushees

# 2) Clonar
git clone https://github.com/llljacklll/RHCE_Lab.git
cd RHCE_Lab

# 3) Host a punto: docker + compose + /dev/loopN persistentes
sudo bash scripts/vm_bootstrap.sh

# 4) Vault: secrets.yml ya viene encriptado en el repo; este paso
#    crea .vault_pass en ansible/files/ (no viaja en git)
./scripts/create_vault.sh

# 5) Levantar (compila imágenes: requiere internet)
./lab.sh up

# 6) Verificación integral de infraestructura: TODO en verde
bash scripts/smoke_test.sh
~

## ⚡ Inicio rápido (host ya preparado)

~bash
./lab.sh up                 # levantar
./scripts/create_vault.sh   # vault + .vault_pass (una sola vez)
./lab.sh test               # batería de pruebas automática
~

## 🎮 Uso de la CLI

| Comando | Descripción |
|---|---|
| `./lab.sh up` | Construir imágenes y levantar (lento, requiere internet) |
| `./lab.sh start` / `stop` | Levantar sin recompilar / detener conservando datos |
| `./lab.sh down` | Destruir contenedores, red e imágenes (limpieza total) |
| `./lab.sh reset` | Destruir y reconstruir todo |
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
crea con `./scripts/create_vault.sh`).

- **Contraseña del vault**: `RhceLab2026` (didáctica; en el EX294 real
  te la entregan en el enunciado, igual que aquí)
- **Valor de `db_password`**: `SecretPassword123`

Ejecución de exámenes con vault: `./lab.sh run --vault exam_003.yml`

## 🧪 Smoke test completo (primera sesión)

~bash
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
~

## 🛠️ Notas técnicas

- **Firewalld en modo offline**: los playbooks usan `offline: true` en
  `ansible.posix.firewalld`, que edita los XML directamente sin demonio.
  Es determinista y portable (no depende del daemon ni de nf_tables).
- **LVM sobre loop devices**: los discos son loopback de 1GB. Los loop
  devices son **recursos globales del kernel**, así que cada nodo usa
  una **pareja fija** (node1: `loop0/1`, node2: `loop2/3`, node3:
  `loop4/5`; control ninguno) y `setup-disks.sh` nunca hace
  `losetup -D`. Como EL10 no crea `/dev/loopN` al arrancar,
  `vm_bootstrap.sh` los registra vía `LOOP_CTL_ADD` y
  `rhce-lab-loop.service` los mantiene tras reinicios. Sin udev,
  `lvcreate` requiere `--wipesignatures n --zero n` (los playbooks de
  referencia ya lo aplican). No se soportan particiones
  (`/dev/loop0p1`): el LVM se hace sobre el disco raw.
- **DNS**: la red es fija (172.20.0.0/24) para evitar caídas por caché
  de DNS de Docker. En redes corporativas: `./lab.sh up --dns <ips>`.

## 🗺️ Roadmap

- [ ] Tareas de Block/Rescue en el task pool
- [ ] Checker fino de SELinux (fcontext real)
- [ ] Más exámenes estáticos

## 📜 Licencia

CC BY-NC-SA 4.0 — ver [LICENSE](LICENSE).

**Autor:** llljacklll · construido con asistencia de IA.
