# EXAMS — El motor de exámenes

Cómo funciona un examen del laboratorio de punta a punta: cómo se
genera, cómo corre el cronómetro, qué anti-trampas hay, cómo corrige y
cómo se amplía el banco de tareas. La arquitectura general del repo está
en [ARCHITECTURE.md](ARCHITECTURE.md); el uso day-to-day en el
[README](../README.md); el examen desde el navegador en
[WEBUI.md](WEBUI.md).

## Ciclo de vida

```
./lab.sh exam <estatico> | ./lab.sh exam --random N <dif>
        |
        v
state/current_exam.yml          (el examen ACTIVO: tareas + time_limit)
        |     sin cronometro todavia: se puede regenerar cuantas veces haga falta
        v
./lab.sh exam --start           (presenta el examen Y arranca el cronometro)
        |
        v
state/exam_status.yml           (status: running, start_time, end)
        |     ... 45 minutos de verdad, cuenta atras persistente ...
        v
TU ESCRIBES ansible/playbooks/<tarea>.yml   (vim desde la web, editor local,
        |                                  da igual: el fichero es el contrato)
        v
./lab.sh run <playbook>  (o ansible-playbook desde el terminal web)
        |
        v
./lab.sh grade  -->  core/checkers/* en los 3 nodos
        |
        v
state/results/<examen>_<ts>.log    ("Nota  : N/N" + detalle por tarea)
```

Estados del examen (`state/exam_status.yml`):

| Estado | Significado | Qué se puede hacer |
|---|---|---|
| sin `exam_status.yml` | Examen generado pero sin arrancar | Regenerar, arrancar, doctor |
| `running` | Cronómetro en marcha | Todo: editar, ejecutar, grade (detiene el cronómetro) |
| `expired` | Tiempo agotado | Consultar; `grade` se BLOQUEA (anti-trampa) |

## Exámenes estáticos

Los seis exámenes fijos de `scenarios/`, pensados para calibrar el
laboratorio de punta a punta (sus soluciones de referencia son los
`ansible/playbooks/exam_00X.yml`):

| Examen | Tareas | Esperado con su solución | Se trabaja |
|---|---|---|---|
| `easy/exam_001.yml` | 3 | 3/3 APROBADO | Paquetes/usuarios/servicios básicos |
| `medium/exam_002.yml` | 2 | 2/2 APROBADO | Roles + plantillas Jinja2 |
| `hard/exam_003.yml` | 5 | 5/5 APROBADO | Vault + LVM multi-nodo (necesita `--vault`) |
| `easy/exam_004.yml` | 4 | 5/5 APROBADO | Grupos, setgid y permisos |
| `medium/exam_005.yml` | 4 | 4/4 APROBADO | vsftpd + SELinux fcontext persistente |
| `hard/exam_006.yml` | 5 | 6/6 APROBADO | block/rescue + cron + storage compartido |

```bash
./lab.sh exam easy/exam_001.yml     # cargar (arranca cronometro)
./lab.sh run exam_001.yml           # la solucion de referencia: 3/3
./lab.sh grade
```

> Los `exam_00X.yml` son SPOILERS. Para practicar de verdad, parte de
> cero con tu propio fichero.

## Exámenes aleatorios

```bash
./lab.sh exam --random 4            # 4 tareas, dificultad mixta
./lab.sh exam --random 3 hard       # 3 tareas, solo del grupo hard
./lab.sh exam --start               # presenta y arranca el cronometro
```

- La sintaxis es **posicional**: `--random N [easy|medium|hard|mixed]`.
  La selección dentro del grupo de dificultad la hace el propio
  generador (`core/exam_random.sh` con el PyYAML del host).
- El resultado se serializa en `state/current_exam.yml` con las tareas
  elegidas (`id`, `description`, `checks`) y su `time_limit` en
  minutos (45 por defecto).
- Cada tarea del banco tiene su solución de referencia en
  `soluciones/<id>.yml` — en CLI las puedes leer directamente y en la
  webui están a un `[mostrar solucion]` de distancia.

## El cronómetro y las anti-trampas

El objetivo es simular la presión del EX294 real sin trucos baratos:

- **Persistente**: vive en `state/exam_status.yml` (`status`,
  `start_time`, `end`), no en la memoria de ningún proceso. Reinicies
  lo que reinicies, el reloj es el reloj.
- **Expira solo**: un subshell del propio motor duerme el tiempo
  restante y voltea `running` -> `expired` en el fichero. El pid de ese
  timer queda en `state/timer.pid` (arrancar un examen nuevo mata el
  timer anterior).
- **Anti-trampa dura**: si el estado es `expired`, `grade` se bloquea.
  Se puede consultar el examen, pero no se "entrega tarde".
- **`grade` detiene el cronómetro**: corregir es entregar.
- El tiempo restante lo calculan CLI y webui por igual con
  `end` (o `start_time + time_limit*60` si aún no hay `end`) menos
  `ahora`. La webui lo pinta en `HH:MM:SS` con aviso amarillo a los 15
  minutos y rojo a los 5.

## La corrección

`./lab.sh grade`:

1. Lee el examen activo (`state/current_exam.yml`).
2. Por cada tarea, cablea el checker que corresponde a su `tipo`
   (`core/checkers/check_<tipo>.sh`) y lo ejecuta contra los nodos
   objetivo — que suelen ser los 3, y en las tareas LVM el disco
   correcto por nodo (filtro LVM).
3. Escribe un informe por tarea: PASS o FAIL **con su razón legible**
   (contrato de la familia de checkers: un FAIL mudo es bug).
4. Deja el informe completo en `state/results/<examen>_<timestamp>.log`
   — un fichero por corrección, sin colisiones (cada grade pisa su
   propio timestamp, no el de otro).
5. Pinta la nota final en formato `Nota  : N/N` (el chip `ultimo:` de
   la webui lee exactamente ese patrón del log más reciente).

En el lab prístino los checkers FALLAN honestos (discos vacíos, paquetes
sin instalar): es la señal de que nadie te ha hecho trampas. El
RUNBOOK recoge el marcador de lectura contra nodos vírgenes y la
huella legítima de la Fase 5 de la batería (que fuerza las soluciones
de los tres exámenes fijos).

## Cómo añadir una tarea al banco

Receta con los pasos en orden (el formato exacto de las entradas,
tómalo de tareas existentes en `scenarios/task_pool.yml`: es la spec
de facto):

1. **Diseña la tarea** y sus `checks`: qué comando/dirige valida el
   resultado en los nodos y con qué argumentos. Reusa un checker
   existente siempre que puedas; solo crea uno nuevo si el tipo de
   validación no existe todavía.
2. **Escribe la solución de referencia** `soluciones/<id>.yml`: un
   playbook que resuelve la tarea de la forma canónica. Es a la vez
   prueba y material de aprendizaje.
3. **Si necesitas un checker nuevo**: `core/checkers/check_<tipo>.sh`,
   siguiendo el contrato de la familia (PASS/FAIL + razón; `bash -n`
   limpio). Recuerda que la CI valida la consistencia de la familia en
   cada push.
4. **Da de alta la tarea** en `scenarios/task_pool.yml` dentro de su
   grupo de dificultad: `id` (el nombre tira de
   `soluciones/<id>.yml`), `description` (el enunciado que verá el
   estudiante) y `checks` (tipo + argumentos).
5. **Pruébala de verdad**: genera un examen que la incluya, resuélvela
   con la solución de referencia, y `grade` debe dar el N/N esperado;
   en un nodo sin resolver debe dar FAIL con su razón.
6. **Limpia**: `bash -n` del checker nuevo, YAML válido, sin restos de
   debug. Commit.

Reglas de oro del diseño de tareas: una tarea = un `id` = una solución
de referencia; los ids viven también como nombre de fichero
(`[A-Za-z0-9_]`, la webui lo exige para mostrar la solución); y el
enunciado debe ser resoluble SIN mirar la solución (si no, el
"modo aprendizaje" se convierte en modo trampa).

## El Vault del laboratorio

`ansible/files/secrets.yml` viaja en git CIFRADO con
`ansible-vault`; la contraseña vive en `ansible/files/.vault_pass`,
que NO viaja (lo crea `./scripts/create_vault.sh` o el propio `lab.sh`
en el primer uso).

- Contraseña del vault: `RhceLab2026` (didáctica; en el EX294 real te
  la entregan en el enunciado, igual que aquí).
- Contenido: la variable `db_password` (`SecretPassword123`), usada por
  el examen hard.
- Uso: `./lab.sh run --vault exam_003.yml` (pide la contraseña) o la
  equivalente desde el terminal web.

## CLI <-> web: la misma casa por dos puertas

| Operación | CLI | Webui |
|---|---|---|
| Generar examen | `./lab.sh exam --random 4 medium` | Dificultad + N -> `Generar` |
| Presentar y arrancar cronómetro | `./lab.sh exam --start` | `Iniciar cronometro` |
| Leer enunciados | `cat state/current_exam.yml` | Tarjeta Tareas (siempre visible) |
| Escribir la solución | `vim ansible/playbooks/<tarea>.yml` | `[editar]` (vim en el terminal web) |
| Ejecutar el playbook | `./lab.sh run <tarea>.yml` | El mismo comando, tecleado en el terminal web |
| Consultar la solución de referencia | `cat soluciones/<tarea>.yml` | `[mostrar solucion]` (abajo del todo) |
| Corregir | `./lab.sh grade` | `Grade` (nota en el chip `ultimo:`) |
| Diagnóstico | `./lab.sh doctor` | `Doctor` |
| Cronómetro / estado | `cat state/exam_status.yml` | Cronómetro del panel, refresco cada 10 s |

La webui no tiene lógica propia de examen: todo pasa por `lab.sh` y
por la lectura de `state/`. Lo que vale en CLI vale en la web, y al
revés.
