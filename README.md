# 🚀 RHCE Lab — Simulador del examen EX294 (Red Hat Certified Engineer)

## Prerrequisitos del host

El lab corre sobre **Docker Engine + plugin compose v2** en un host Linux x86_64.
Dos escenarios soportados:

- **WSL2 (portatil de desarrollo)**: Docker Desktop para Windows con la
  integracion WSL activada. El kernel de WSL2 no trae nf_tables, por eso
  firewalld dentro de los contenedores va siempre en modo offline (restriccion R1).
- **MV Rocky/Alma 10 (escenario de examen)**: Docker Engine nativo (no Desktop).
  Un solo comando deja la MV lista (idempotente, re-lanzable):

        sudo bash scripts/vm_bootstrap.sh

  Detecta la familia EL (Rocky/Alma/RHEL 9-10), escribe el repo oficial de
  Docker CE, instala engine + compose plugin, habilita docker.service y
  verifica /dev/loop-control, cgroup v2 y SELinux.

Checklist del host:

| Requisito | Verificacion |
|---|---|
| Docker Engine 24+ | docker version |
| Compose v2 (plugin) | docker compose version |
| /dev/loop-control (LVM fake) | ls /dev/loop-control |
| cgroup v2 | stat -fc %T /sys/fs/cgroup -> cgroup2fs |
| git con PAT (scope repo) | git ls-remote origin HEAD |

> En la MV se trabaja como root y SELinux puede quedar Enforcing: los
> contenedores del lab son privileged, no hace falta tocarlo.


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
| 💾 Discos LVM | Cada nodo arranca con `/dev/loop0` y `/dev/loop1` de 1GB para práctica LVM |

## 📋 Requisitos

- Linux con **Docker Engine + docker compose v2** (recomendado: VM Rocky/Alma/RHEL 9-10)
- `python3` + `pyyaml` en el host (para el generador aleatorio)
- ~4GB de RAM libres (las imágenes pesan ~1.2GB)

> **¿WSL2?** Funciona con salvedades conocidas (kernel sin nf_tables →
> firewalld forzado a modo offline). Para la experiencia completa se
> recomienda una VM Rocky 10.

## 🔧 Preparar el host (Rocky / Alma / RHEL)

~~~bash
# Docker Engine + compose v2
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker

# Python + YAML para el generador de exámenes
sudo dnf -y install python3-pyyaml

# (Opcional) lanzar docker sin sudo
sudo usermod -aG docker $USER && exit   # reentra en la sesión
~~~

## ⚡ Inicio rápido (desde cero)

~~~bash
# 1) Clonar
git clone https://github.com/llljacklll/RHCE_Lab.git
cd RHCE_Lab

# 2) Levantar el laboratorio (compila imágenes: requiere internet)
./lab.sh up

# 3) Crear el Ansible Vault del laboratorio (una sola vez)
#    (Si el clone ya trae ansible/files/secrets.yml, este paso es opcional)
./scripts/create_vault.sh

# 4) Batería de pruebas automática
./lab.sh test
~~~

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

`ansible/files/secrets.yml` (generado por `./scripts/create_vault.sh`)
contiene cifrada la variable `db_password`, usada por el examen hard.

- **Contraseña del vault**: `RhceLab2026` (didáctica; en el EX294 real
  te la entregan en el enunciado, igual que aquí)
- **Valor de `db_password`**: `SecretPassword123`

Ejecución de exámenes con vault: `./lab.sh run --vault exam_003.yml`

## 🧪 Smoke test completo (primera sesión)

~~~bash
./lab.sh up                              # levantar
./scripts/create_vault.sh                # vault (si no existe)
./lab.sh test                            # batería automática → TODO PASS

./lab.sh exam easy/exam_001.yml          # examen fácil
./lab.sh run exam_001.yml
./lab.sh grade                           # esperado: 3/3 APROBADO

./lab.sh exam medium/exam_002.yml        # examen medio (roles + jinja2)
./lab.sh run exam_002.yml
./lab.sh grade                           # esperado: 2/2 APROBADO

./lab.sh exam hard/exam_003.yml          # examen hard (vault + LVM)
./lab.sh run --vault exam_003.yml        # contraseña: RhceLab2026
./lab.sh grade                           # esperado: 5/5 APROBADO

./lab.sh exam --random 4                 # examen aleatorio
./lab.sh exam --start
./lab.sh grade
~~~

## 🛠️ Notas técnicas

- **Firewalld en modo offline**: los playbooks usan `offline: true` en
  `ansible.posix.firewalld`, que edita los XML directamente sin demonio.
  Es determinista y portable (obligatorio en WSL2, opcional pero
  recomendado en VM).
- **LVM sobre loop devices**: los discos son loopback dentro de cada
  contenedor. Sin udev, `lvcreate` requiere `--wipesignatures n --zero n`
  (los playbooks de referencia ya lo aplican). No se soportan particiones
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
