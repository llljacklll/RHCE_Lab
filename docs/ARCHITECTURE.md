# ARCHITECTURE — Cómo está construido el laboratorio

Este documento es el mapa general del proyecto: qué pieza es cada cosa,
dónde vive y con quién habla. Complementa (no sustituye) a los
comentarios de cabecera de los propios ficheros y al [README](../README.md)
de uso. El motor de exámenes en detalle está en [EXAMS.md](EXAMS.md);
la consola web en [WEBUI.md](WEBUI.md); el procedimiento de reset total
en [RUNBOOK.md](RUNBOOK.md).

## Visión de conjunto

El laboratorio son tres capas apiladas:

1. **El host** — una MV de la familia EL 9/10 (`laboratoriob`). Un
   bootstrap idempotente (`scripts/vm_bootstrap.sh`) deja a punto Docker
   Engine + compose, registra los `/dev/loop0-15` del kernel (EL10 no los
   crea solo y son imprescindibles para los discos LVM) y los hace
   persistentes con `rhce-lab-loop.service`.
2. **El clúster** — 4 contenedores Docker sobre una red dedicada
   (`172.20.0.0/24`): un nodo de control con Ansible y tres nodos
   managed con systemd real, SSH y SU propia pareja de discos loop.
3. **El motor** — `lab.sh` (dispatcher) + `core/` (lógica pura en bash)
   + `core/checkers/` (plugins de corrección) + los escenarios y el
   banco de tareas. Sus dos frontales: la propia CLI y la consola web
   (`webui/`), que es un mando a distancia del CLI.

```
        HOST (MV Rocky/Alma EL9-10)
   vm_bootstrap.sh + rhce-lab-loop.service (/dev/loop0-15)
   rhce-lab.service (opcional: autoarranque con la MV)
        |
        |  Docker Engine (red dedicada 172.20.0.0/24)
        |
        +--------------------------------------------------------+
        |  control   Ansible Core 2.16          (sin discos)   |
        |  node1     systemd real + SSH   loop0/1  (2x1GB)      |
        |  node2     systemd real + SSH   loop2/3  (2x1GB)      |
        |  node3     systemd real + SSH   loop4/5  (2x1GB)      |
        +--------------------------------------------------------+
                 ^                 ^                  ^
                 |   ansible-playbook (lab.sh run)   |
                 |                                   |
   TUS playbooks (ansible/playbooks/<tarea>.yml)    |
                                                     |
        lab.sh exam / exam --random / exam --start -> cronometro
        lab.sh grade -> core/checkers/* en los 3 nodos -> state/results/
```

## Topología de contenedores

| Contenedor | Rol | Discos LVM | Particularidades |
|---|---|---|---|
| `control` | Ejecuta Ansible y el examen | ninguno | Aquí viven tus playbooks; la webui abre su terminal |
| `node1` | Nodo managed | `/dev/loop0` + `/dev/loop1` | Discos prístinos: los checkers LVM FALLAN hasta que creas la VG |
| `node2` | Nodo managed | `/dev/loop2` + `/dev/loop3` | idem |
| `node3` | Nodo managed | `/dev/loop4` + `/dev/loop5` | idem |

Decisiones de diseño que conviene recordar:

- **Discos loop = recursos globales del kernel**, así que cada nodo
  recibe una pareja FIJA (nunca `losetup -D`, nunca particiones:
  el LVM se hace sobre el disco raw).
- **Filtro LVM por nodo** (`docker/lvmlocal.conf` horneado en la
  imagen + `fake-disks.service` ejecutando `setup-disks.sh` al arrancar
  cada contenedor): un nodo NO ve los PV de otro, y los checkers LVM
  solo dan OK si la VG existe EN ese nodo. En el lab prístino dan FAIL,
  como debe ser.
- **Firewalld en modo offline**: los playbooks usan `offline: true`
  (editan los XML sin demonio). Determinista y portable, no depende de
  nf_tables (por eso WSL2 dejó de ser escenario soportado).
- **Red con IP fijas** para no depender de la caché de DNS de Docker;
  en redes corporativas, `./lab.sh up --dns <ips>`.

## Mapa del repositorio

| Ruta | Contenido | Quién lo usa |
|---|---|---|
| `lab.sh` | Dispatcher de subcomandos + DEP-GUARD | todo empieza aquí |
| `bootstrap.sh` | Atajo de restauración (pull + up + doctor) | recuperación de snapshots |
| `core/` | El motor en bash (ver abajo) | `lab.sh` |
| `core/checkers/` | 12 plugins de corrección | `core/grade.sh` |
| `docker/` | Dockerfile, compose, discos y filtro LVM, ansible.cfg | `core/docker.sh` / `core/disks.sh` |
| `ansible/` | Inventario, playbooks (los tuyos y los de referencia), role de ejemplo, vault | el nodo control |
| `scenarios/` | 3 exámenes estáticos + `task_pool.yml` (banco aleatorio) | `core/exam.sh` / `exam_random.sh` |
| `soluciones/` | Una solución de referencia por tarea del banco | modo aprendizaje (CLI y web) |
| `state/` | Estado vivo: examen activo, cronómetro, results/ | el motor; la webui SOLO lee |
| `ui/` | `banner.sh` (versión) y `colors.sh` | el CLI |
| `webui/` | La consola web (fichero único + xterm local) | `./lab.sh web` |
| `scripts/` | Bootstrap de MV, vault, smoke test, demos, auditorías | operación del host |
| `docs/` | RUNBOOK + esta documentación | humanos |
| `.github/workflows/` | CI: lint de bash, YAML, heredocs y consistencia de checkers | cada push |

## lab.sh: el dispatcher

`lab.sh` es la única puerta de entrada deliberada del proyecto. Aparte
de repartir subcomandos a `core/`, tiene dos responsabilidades propias:

- **DEP-GUARD**: si faltan Docker, compose, pyyaml o `/dev/loop0`,
  lanza `scripts/vm_bootstrap.sh` automáticamente (idempotente), y crea
  `ansible/files/.vault_pass` si no existe. Desde v1.2.0 el lab se
  auto-prepara: ninguna MV restaurada exige pasos manuales.
- **`web`**: la función `lab_web` (LOTE 26) levanta `webui/webui.py`
  con `nohup` y redirige su log a `/tmp/webui.log`.

## core/: el motor

| Módulo | Responsabilidad |
|---|---|
| `constants.sh` | Fuentes de verdad: rutas (`state/current_exam.yml`, `exam_status.yml`, pid del timer), opciones por defecto |
| `utils.sh` | Funciones auxiliares compartidas del CLI |
| `docker.sh` | Ciclo de vida de la infraestructura: imágenes, contenedores, red (`up`/`start`/`stop`/`down`/`reset`) |
| `disks.sh` | El módulo más gordo: discos loop por nodo, wipe prístino con reintentos, idempotencia de arranque |
| `ansible.sh` | Ejecución de playbooks contra los 3 nodos (`lab.sh run`, soporte `--vault`) |
| `exam.sh` | Motor de examen: carga de estáticos, `--start`, cronómetro y anti-trampas (ver EXAMS.md) |
| `exam_random.sh` | Generador de exámenes únicos desde `scenarios/task_pool.yml` (necesita PyYAML del host) |
| `grade.sh` | Corrección: cablea los checkers por tipo de tarea, escribe el informe con la nota en `state/results/` |
| `test.sh` | Batería del motor (12/12 en verde = entorno perfecto) |

## El sistema de checkers

`core/checkers/` son plugins: cada fichero `check_<tipo>.sh` sabe
validar UN tipo de tarea contra los nodos, y es `grade.sh` quien decide
qué checker ejecutar por cada tarea del examen (el cableado es
dinámico, por el `tipo` declarado en la tarea). El contrato de la
familia (endurecido en los lotes 13-14): cada checker emite
PASS/FAIL **con razón legible** — un FAIL mudo o un PASS fantasma son
bug, no estado.

Los 12 plugins actuales:

| Checker | Valida |
|---|---|
| `check_package.sh` | Paquetes instalados en los nodos objetivo |
| `check_service.sh` | Servicios activos y habilitados |
| `check_user.sh` | Usuarios (existencia, atributos) |
| `check_group.sh` | Grupos y membresías |
| `check_file.sh` | Contenido/estado de ficheros (con el fix fino de los lotes 13) |
| `check_permissions.sh` | Permisos y dueño |
| `check_cron.sh` | Entradas cron (tareas root incluidas) |
| `check_lvm.sh` | VG/PV/LV en el nodo correcto (filtro LVM por nodo) |
| `check_filesystem.sh` | Filesystems creados/formateados |
| `check_mount.sh` | Montajes persistentes |
| `check_selinux_fcontext.sh` | SELinux fino: fcontext de policy real |
| `check_block_rescue.sh` | Tareas block/rescue (playbook con control de error) |

## Escenarios, banco y soluciones

- **`scenarios/{easy,medium,hard}/exam_00X.yml`** — los tres exámenes
  fijos (3, 2 y 5 tareas respectivamente; el hard usa vault + LVM).
- **`scenarios/task_pool.yml`** — el banco de tareas aleatorias,
  agrupadas por dificultad; `exam --random N dif` elige de aquí.
- **`soluciones/<id>.yml`** — una solución de referencia por tarea del
  banco: es el material del "modo aprendizaje" de la webui y el patrón
  para escribir las tuyas. Spoilers, con orgullo.
- **`ansible/playbooks/exam_00X.yml`** — soluciones de referencia de
  los exámenes fijos (para probar el motor de punta a punta:
  `lab.sh test` las fuerza en su Fase 5, huella legítima documentada en
  el RUNBOOK). Los demás ficheros de `ansible/playbooks/` son TUYOS.
- **`state/current_exam.yml`** — el examen ACTIVO serializado: es la
  única verdad que leen CLI y webui (tareas `id` + `description` +
  `checks`, y `time_limit` en minutos).

## Estado y persistencia

Lo que vive en `state/` es efímero y por eso NO viaja en git (regla de
oro del RUNBOOK: lo que importa se commitea o se gitignora):

| Fichero | Qué es |
|---|---|
| `state/current_exam.yml` | El examen activo (tareas + time_limit) |
| `state/exam_status.yml` | El cronómetro: `status: running|expired`, `start_time`, `end` |
| `state/timer.pid` | El subshell que voltea el estado al expirar |
| `state/results/*.log` | Un informe por corrección (`Nota  : N/N` + detalle por tarea) |

También quedan fuera de git `ansible/files/.vault_pass`,
`webui/run.log` y `webui/__pycache__/`. Lo ÚNICO cifrado que sí viaja
en git es `ansible/files/secrets.yml` (el vault con `db_password`).

## La consola web

`webui/webui.py` es un fichero único Python stdlib (~900 líneas) que
sirve el panel en `127.0.0.1:8888`: allowlist de acciones sobre
`lab.sh`, cronómetro, enunciados, soluciones de referencia y un
terminal real del nodo control por WebSocket artesanal sobre PTY.
No duplica lógica: es un cliente más del CLI. Guía completa en
[WEBUI.md](WEBUI.md).

## CI y garantías

En cada push, `.github/workflows/ci.yml` pasa `bash -n` a todo el
bash del repo, valida los YAML, verifica los heredocs de python y la
consistencia de la familia de checkers. La batería local equivalente
es `bash scripts/smoke_test.sh` (infraestructura) + `./lab.sh test`
(motor, 12/12).

## Convenciones de desarrollo

- **Idioma**: documentación y comentarios en español; identificadores,
  rutas y claves YAML en inglés/snake_case.
- **Cambios quirúrgicos**: los lotes del proyecto trabajan con gates
  de base (md5), parches todo-o-nada y verificación ANTES de ejecutar
  nada. Copiar el patrón en cambios propios es gratis.
- **Fail-closed por defecto**: ante estado ilegible, la UI se cierra
  (LOTE 29); ante dependencia ausente, el lab se auto-prepara en vez
  de fallar a medias (DEP-GUARD).
- **El RUNBOOK es la ley para los resets**: clone fresco, nunca pull
  sobre el árbol del snapshot.
