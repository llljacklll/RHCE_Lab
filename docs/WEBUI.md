# WEBUI — La consola web del simulacro

La webui (`webui/webui.py`) es un **mando a distancia del CLI** con
terminal del nodo de control incluido: desde el navegador puedes generar
el examen, arrancar el cronómetro, leer los enunciados, editar tus
playbooks con `vim` EN un terminal real, consultar las soluciones de
referencia en modo aprendizaje y corregir. El CLI local sigue siendo
exactamente el mismo y vale igual que siempre: la web es una capa fina
encima, no un reemplazo.

Tres reglas de oro del diseño (sacadas de la cabecera del propio
`webui.py`, que es la especificación de facto):

1. **Toda acción pasa por `lab.sh` y solo por una allowlist** de
   acciones (`generate`, `start`, `grade`, `doctor`), ejecutadas con
   `subprocess` SIN shell: nada llega nunca a una cadena de comandos.
2. **El servidor JAMAS escribe estado**: lee `state/current_exam.yml`,
   `state/exam_status.yml` y `state/results/` para pintar el panel;
   quien escribe el estado es siempre el CLI.
3. **Escucha SOLO en 127.0.0.1**: el acceso remoto va por túnel SSH
   reutilizando el único puerto que ya está abierto en la MV. Cero
   firewalld, cero puertos nuevos.

Es un único fichero Python con **solo stdlib** (sin dependencias: lo
levanta el `python3` de la propia MV) y con el frontend
(HTML/CSS/JS) embebido dentro. `xterm.js` se sirve local desde
`webui/static/`, así que el panel funciona **sin internet** el día que
importa.

## Arranque y parada

```bash
./lab.sh web          # sirve http://127.0.0.1:8888 (queda en nohup)
```

- El subcomando `web` de `lab.sh` lanza `webui/webui.py` en segundo
  plano y deja su log de arranque en `/tmp/webui.log`.
- Comprobación rápida de que vive:

  ```bash
  ss -tlnp | grep 8888     # python3 escuchando SOLO en 127.0.0.1
  curl -s http://127.0.0.1:8888/api/status | head -c 200
  ```

- Tras un reinicio de la MV el servidor no revive solo: relanza
  `./lab.sh web`.
- Parada / reinicio limpio: `pkill -f webui.py` (si tenías el terminal
  web abierto, la sesión se corta: es lo esperado) y a relanzar si toca.
- Opciones manuales (casi nunca necesarias), ejecutando el fichero
  directamente:

  ```bash
  python3 webui/webui.py --port 8899 --bind 127.0.0.1
  ```

  Si enlazas fuera de loopback, el propio binario te avisa al arrancar:
  el proceso corre como root y exponerlo a la red es exponer un shell.
  No lo hagas; usa el túnel.

## Acceso remoto: el túnel SSH

El laboratorio vive en una MV (aquí `laboratoriob`) tras un host de
salto (aquí `laboratorio`), y en una MV de la familia EL firewalld solo
abre el 22 por defecto. La webui no pide abrir nada nuevo: **reutiliza
el SSH**.

Desde TU equipo (esto es importante: no dentro de la MV):

```bash
ssh -J root@<IP-laboratorio> \
    -L 8888:127.0.0.1:8888 root@<IP-laboratoriob>
# y abre http://localhost:8888 en el navegador
```

- `-J` (ProxyJump) encadena el salto por `laboratorio`.
- `-L 8888:127.0.0.1:8888` reenvía el puerto 8888 **de tu equipo** al
  loopback de `laboratoriob`.
- **Regla de oro del `-L`**: el puerto local se abre DONDE CORRE el
  CLIENTE ssh. Si ejecutas el comando DENTRO de la MV, el túnel queda
  en el lado equivocado y tu navegador verá conexión fallida con el
  lab funcionando perfectamente. Es el fallo clásico y tiene toma
  dedicada en el Short (problema -> arreglo).
- Variantes útiles:
  - `-N` para no abrir shell remoto (túnel puro).
  - Equipo con WSL2: el `localhostForwarding` suele dejar el 8888 usable
    desde el navegador de Windows; si se resiste, lanza el mismo `ssh`
    desde PowerShell.
  - Puerto 8888 ocupado en TU equipo: cambia solo el número de la
    IZQUIERDA y del navegador (`-L 9999:127.0.0.1:8888` ->
    `http://localhost:9999`). El de la derecha es el del lab.
  - `ssh-copy-id` en ambos saltos elimina los prompts de contraseña
    (recomendado antes de grabar el Short).
- Cerrar el `ssh` es apagar la web: el navegador muere con el túnel.
  Es intencional: **el túnel ES el control de acceso** (quien entra,
  entra con credenciales SSH).

## Recorrido del panel

De arriba abajo:

| Zona | Qué hace |
|---|---|
| Chips de cabecera | `examen:` id del examen activo (+ límite en minutos) y `ultimo:` nota `N/N` del último informe en `state/results/` |
| **Generar examen** | Dificultad (`mixed`/`easy`/`medium`/`hard`) + N tareas -> ejecuta `./lab.sh exam --random N dif` |
| **Cronómetro** | Restante `HH:MM:SS`; amarillo por debajo de 15 min, rojo por debajo de 5; `--:--:--` si no hay examen activo |
| **Tareas del examen** | Enunciado SIEMPRE visible; los botones `[editar]` y `[mostrar solucion]` permanecen ocultos hasta que el cronómetro está en marcha |
| **Ejecutar** | `Iniciar cronometro` (`exam --start`), `Terminal`, `Grade`, `Doctor`, `Limpiar` |
| **Salida del simulador** | La salida ANSI del último comando, a color; sobrevive al F5 (se lee por offset desde `webui/run.log`) |
| **Terminal del nodo de control** | Un `bash` real con PTY (xterm.js); aquí se HACE el examen: `vim`, `ansible-playbook`, `ssh` a los nodos |
| **Solucion de la tarea** | Tarjeta propia ABAJO DEL TODO (LOTE 29): `soluciones/<tarea>.yml` en modo lectura pura |

Detalles de comportamiento que conviene conocer:

- **Ocultación anti-despistes (LOTE 29)**: al cargar, el panel arranca
  en modo `examoff` (fail-closed: si el estado no se puede leer, los
  botones NO salen). En cuanto `state/exam_status.yml` dice `running` o
  `expired`, aparecen los botones de tarea y el de Terminal. El
  enunciado se ve siempre: oculto está el modo ejecución, no la lectura.
- **`[editar]` es un toggle**: si el terminal está cerrado lo abre solo
  y luego inyecta `vim ansible/playbooks/<tarea>.yml` en la sesión. El
  botón pasa a decir `cerrar edicion`, que envía `ESC :wq` (guarda y
  sale). Al saltar de una tarea a otra, el `vim` anterior se cierra
  guardando y el nuevo se abre solo, en dos fases separadas 400 ms
  (razón técnica: el typeahead de `vim` sobre el PTY se comería un
  segundo comando inmediato; con la pausa, el cierre y la apertura no
  pisan comandos).
- **`[mostrar solucion]` también es un toggle**: pinta la solución en
  su propia tarjeta abajo del todo, de solo lectura. Es el modo
  aprendizaje: el spoiler lo controlas tú, tarea a tarea.
- **Terminal autoconectado**: al abrir el panel de Terminal la sesión
  arranca sola (el botón `Conectar` murió en el LOTE 29). El botón
  `Reconectar` solo aparece si la sesión cayó (p. ej. reiniciaste el
  servidor); al caer, el estado de edición se resetea limpio.
- **Una acción en vuelo**: si lanzas Generar/Grade/Doctor con algo
  corriendo, la API contesta 409 (`ocupado`) y el badge lo cuenta. Los
  botones se desactivan mientras corre el comando.
- El panel refresca el estado cada 10 s y el cronómetro baja segundo a
  segundo en el navegador (sin hablar con el servidor a cada tick).

## Cómo funciona por dentro

Un vistazo a los bloques del fichero (en orden, tal como están
comentados en `webui.py`):

- **ADAPTER** — el único sitio que conoce el CLI y el estado del lab.
  La tabla `ACTIONS` define las acciones permitidas y sus argv
  exactos; un cambio de CLI se absorbe aquí y solo aquí:

  | Acción | Comando que ejecuta |
  |---|---|
  | `generate` | `./lab.sh exam --random <n> <d>` (dificultad posicional) |
  | `start` | `./lab.sh exam --start` |
  | `grade` | `./lab.sh grade` |
  | `doctor` | `./lab.sh doctor` |

- **Runner** — un solo comando en vuelo (lock global; segunda acción
  en marcha -> 409). La salida cruda va a `webui/run.log` y el navegador
  la lee incrementalmente por offset: un F5 no pierde la consola.
- **Lectura de estado** — regex de confianza sobre los YAML de `state/`
  (nunca parseadores completos: ficheros pequeños, formato conocido):
  `current_exam.yml` (id, `time_limit` en minutos, tareas) y
  `exam_status.yml` (`status`, `start_time`, `end` -> restante). La nota
  del último informe sale de `state/results/*.log` con el patrón
  `Nota  : N/N`.
- **Tareas y soluciones** — `exam_tasks()` trocea `current_exam.yml`
  por tareas (`- id:` + `description:`) tal como las serializa el
  generador, con `html.escape` server-side. `read_solution()` sanea el
  id con `^[A-Za-z0-9_]+$` ANTES de tocar el disco y luego lee
  `soluciones/<tarea>.yml`.
- **ANSI -> HTML** — la salida del CLI llega con colores; un traductor
  de secuencias CSI (genérico) la convierte en `<span>` de colores y
  descarta lo que no es presentación.
- **Frontend embebido** — todo el HTML/CSS/JS del panel vive en el
  string `INDEX_HTML`: un fichero, un heredoc, cero build.
- **Terminal (`/ws`)** — WebSocket RFC6455 mínimo escrito a mano
  (handshake con `Sec-WebSocket-Accept`, frames enmascarados del
  cliente, ping->pong, límite de 10 MB por frame). Cada conexión
  levanta una `TerminalSession`: `pty.fork()` + `bash -l` con el cwd del
  lab y `TERM=xterm-256color`, dos hilos (PTY->WS de salida y
  WS->PTY de entrada/resize con `TIOCSWINSZ`). Al morir cualquier lado
  se mata el **grupo entero** del proceso (`killpg` + `waitpid`): ni
  `vim` ni `ssh` huérfanos, ni zombies.
- **Servidor** — `ThreadingHTTPServer` con una peculiaridad: los
  sockets tomados por `/ws` salen de su jurisdicción (el server no debe
  cerrarlos al terminar el request handler).

Tabla de rutas:

| Ruta | Método | Qué devuelve |
|---|---|---|
| `/` | GET | El panel (HTML embebido) |
| `/api/status` | GET | `{running, action, exit, lab:{status,exam,time_limit,remaining,...}, last:[...5], project}` |
| `/api/run` | POST | `{action, params}` -> 200/400 (acción/params no válidos)/409 (ocupado) |
| `/api/output?offset=N` | GET | `{chunk (HTML ya coloreado), next, running, action, exit}` |
| `/api/exam` | GET | `{tasks:[{id, desc}]}` del examen activo |
| `/api/solucion?task=ID` | GET | `{task, content}` o 404 si el id no es `[A-Za-z0-9_]+` o no existe |
| `/static/<fichero>` | GET | Solo 3 ficheros en whitelist (xterm js/css/fit); resto -> 404 |
| `/ws` | GET (Upgrade) | 101 -> sesión de terminal (con gate de Origin) |

## Modelo de seguridad

La webui corre como root (necesita PTY y ejecuta `lab.sh`), así que el
modelo de amenazas se tomó en serio:

1. **Loopback only**: por defecto escucha en `127.0.0.1`. Nadie de la
   red llega sin pasar por SSH.
2. **El túnel es el control de acceso**: no hay usuarios/contraseñas
   propios; heredas las credenciales y el cifrado del SSH de la MV.
   TLS sería redundante dentro de un túnel SSH.
3. **Allowlist + sin shell**: la API solo ejecuta 4 acciones fijas con
   argv prefabricado (`subprocess.Popen` con lista, sin `shell=True`);
   los parámetros se validan (`n` entero, `d` en la lista). No hay
   inyección posible porque no hay cadena de comandos.
4. **Gate de Origin en `/ws`**: un WebSocket NO tiene política de
   mismo-origen (un WS no tiene SOP); sin este gate, cualquier pestaña
   abierta en tu navegador podría apuntar a `localhost:8888/ws` y
   hablarte con un shell root. `/ws` solo acepta Origin
   `localhost`/`127.0.0.1` (o sin Origin: clientes CLI de pruebas).
5. **Saneo de `task`**: `^[A-Za-z0-9_]+$` antes de leer disco. Un
   `?task=../../etc/passwd` o un `x%00y` dan 404 (probado por las
   sondas de los lotes).
6. **Estáticos con whitelist**: `/static/` sirve exactamente 3 ficheros
   conocidos; cualquier otra ruta bajo `/static/` es 404.
7. **Fail-closed en la UI**: si el estado no se puede leer, el panel se
   queda en modo `examoff` (botones ocultos), nunca "abierto por
   defecto".

Qué NO cubre este modelo: multiusuario concurrente (es una herramienta
personal de laboratorio: el 409 serializa comandos y cada pestaña del
terminal es una sesión root independiente), ni auditoría de sesiones.
Si algún día la webui deja de ser una herramienta de un solo operador,
hay que rediseñar antes de exponerla.

## Ficheros que la webui toca

| Fichero | Quién lo escribe | En git |
|---|---|---|
| `webui/webui.py` | desarrollo (lotes) | sí |
| `webui/static/{xterm.min.js,xterm.min.css,xterm-addon-fit.min.js}` | desarrollo (lote 27) | sí |
| `webui/run.log` | la webui (salida del ÚLTIMO comando; se machaca en cada acción nueva) | no (ignorado, lote 26) |
| `webui/__pycache__/` | Python | no (ignorado) |
| `ansible/playbooks/<tarea>.yml` | TU al pulsar `[editar]` (vim los crea vacíos si no existen) | tú decides: son tus soluciones |
| `state/*` | el CLI; la webui solo LEE | no (ignorado) |

Regla de oro del RUNBOOK: lo que importa se commitea o se gitignora.
Tus playbooks de examen son material de práctica: o los commiteas como
solución propia, o los borras antes de un reset.

## Problemas frecuentes

| Síntoma | Causa | Remedio |
|---|---|---|
| `curl: (7) Failed to connect` en TU equipo | El `-L` se abrió donde no era (regla de oro del túnel) | Lanza el `ssh -J ... -L` desde tu equipo, no dentro de la MV |
| Navegador abre, botones muertos | Ficheros xterm o JS viejos en caché | F5; si persiste, comprueba `webui/static/` (3 ficheros) |
| `wq: command not found` en el terminal | Cerraste `vim` a mano y luego pulsaste `cerrar edicion` (el `:wq` cae al prompt) | Cosmético: el estado se resetea bien igualmente |
| El panel no responde tras un reboot | El servidor no es un servicio del sistema | `./lab.sh web` y a correr |
| `address already in use` al relanzar | webui anterior viva | `pkill -f webui.py` y relanza |
| Tareas no cargan tras Generar | Aún no has hecho `Iniciar cronometro` (comportamiento LOTE 29, no bug) | Arranca el cronómetro; el enunciado sí se ve siempre |
| Grade no sale y el badge dice ocupado | Otro comando en vuelo (409) | Espera a que acabe (el badge muestra `exit N`) |
| Terminal dice `sesion cerrada` al vuelo | Reinicio del servidor o caída del túnel | `Reconectar` (resetea el estado de edición) |

## Historia del desarrollo (LOTE 26-29)

| LOTE | Commit | Qué aportó |
|---|---|---|
| 26 | `f820a2a` (+ retoques 26-d) | La consola base: panel, allowlist de acciones, chips, cronómetro, salida ANSI a color, `./lab.sh web`, .gitignore de la webui |
| 27 | `5ccf1c5` | Terminal del nodo de control: `/ws` con PTY artesanal, xterm.js servido local, gates de seguridad (Origin, saneo, killpg) |
| 28 | `11c32ae` | El examen hacible desde la web: tarjeta de tareas con enunciado, `[editar]` inyecta vim apuntando al fichero de la tarea, `[mostrar solucion]` saneado, terminal dockado sin tapar la salida |
| 29 | `ab81d8a` | UX de examen real: solución en su propia tarjeta abajo del todo, toggles por tarea, botones ocultos hasta iniciar cronómetro, autoconexión del terminal (muere `Conectar`) |

Documentación relacionada: la arquitectura general del laboratorio en
[ARCHITECTURE.md](ARCHITECTURE.md); el motor de exámenes (cronómetro,
anti-trampas, corrección) en [EXAMS.md](EXAMS.md); el procedimiento de
reset y prueba de fuego en [RUNBOOK.md](RUNBOOK.md).

