# EPISODIO 1 — exam_001 · "Apache Básico y Usuarios"

**Dificultad:** EASY · **Tiempo límite:** 15 min · **Tasks:** 3 · **Checks:** 3

> El calentamiento perfecto. Tres tareas que recorren el patrón más
> repetido de todo el EX294: **paquete -> usuario -> servicio**. Si
> este patrón no sale en menos de 5 minutos y de memoria, el resto de
> la certificación se complica. Antes de leer la solución: lanza el
> examen en el laboratorio e inténtalo tú.

---

## 0 · El enunciado

Lo que el alumno ve en pantalla (`scenarios/easy/exam_001.yml`):

| Task | Enunciado |
|------|-----------|
| task_1 | Instalar el servidor web **httpd** en todos los nodos |
| task_2 | Crear el usuario **webadmin** en todos los nodos |
| task_3 | Habilitar y arrancar el servicio **httpd** |

## 1 · Análisis: qué pide de verdad el enunciado

Traducción de cada frase a módulo de Ansible y anticipación de qué
validará el corrector (según los comentarios de la propia solución de
referencia del repo):

| Task | Módulo correcto | Qué valida el checker |
|------|-----------------|----------------------|
| task_1 | `ansible.builtin.dnf` | paquete `httpd` instalado (`rpm -q httpd`) |
| task_2 | `ansible.builtin.user` | usuario `webadmin` existe (`id -u webadmin`) |
| task_3 | `ansible.builtin.service` | servicio `httpd` activo (`systemctl is-active httpd`) |

Dos lecturas finas del enunciado:

1. **"en todos los nodos"** -> el play apunta a `hosts: nodes`, el
   grupo del inventario que agrupa node1, node2 y node3. Escribir
   `hosts: node1` deja node2 y node3 sin tocar; `hosts: all` arrastra
   también lo que no es nodo. El grupo correcto está en el enunciado,
   siempre.
2. **"Habilitar y arrancar" son dos cosas distintas**: `enabled: true`
   (arranque en el boot) y `state: started` (proceso vivo ahora). El
   checker de este escenario consulta `is-active`, pero el EX294 real
   suele exigir las dos: hacer solo el `start` es regalar media nota.

## 2 · El esqueleto (los 30 primeros segundos del examen)

```yaml
---
- name: "EXAM 001"
  hosts: nodes          # 'todos los nodos' = grupo nodes del inventario
  become: true          # crear usuarios y paquetes exige root
  tasks:
    # ... una tarea por cada punto del enunciado, en orden
```

Con este esqueleto escrito, el examen ya tiene estructura. Ahora solo
son tres tareas de una acción cada una.

## 3 · Solución paso a paso

```yaml
---
- name: "EXAM 001 :: Apache Básico y Usuarios"
  hosts: nodes                     # node1, node2, node3
  become: true                     # escalado a root (sudo)

  tasks:

    - name: "task_1 | Instalar el servidor web httpd"
      ansible.builtin.dnf:         # gestor nativo de RHEL/Alma/Rocky
        name: httpd                # nombre exacto del RPM
        state: present             # idempotente: instala solo si falta

    - name: "task_2 | Crear el usuario webadmin con shell bash"
      ansible.builtin.user:
        name: webadmin             # el nombre del enunciado, tal cual
        shell: /bin/bash           # el enunciado no lo pide: es buen hábito
        state: present

    - name: "task_3 | Habilitar (boot) y arrancar (ahora) httpd"
      ansible.builtin.service:
        name: httpd
        state: started             # systemctl start httpd
        enabled: true              # systemctl enable httpd
```

Patrones a observar (son los que se repiten en TODO el examen):

- Un módulo nativo por tarea (`dnf`, `user`, `service`), nunca
  `command`/`shell` para lo que ya tiene módulo.
- `state: present` / `state: started`: el vocabulario del estado
  deseado, no de la acción. Eso ES idempotencia.
- Nombres de tarea con el `task_id` del enunciado como prefijo:
  ayuda a navegar y a mapear contra la corrección.

## 4 · Comprobación en el laboratorio

Con la solución de referencia (incluida en el repo):

```bash
./lab.sh run exam_001.yml     # ejecuta la solución contra los nodos
./lab.sh grade                # corrección del motor
```

Verificación manual, como hará el corrector (desde la consola del
control, `./lab.sh shell`):

```bash
ansible nodes -m command -a "rpm -q httpd" -i /opt/ansible/inventory/hosts.ini
ansible nodes -m command -a "id webadmin" -i /opt/ansible/inventory/hosts.ini
ansible nodes -m command -a "systemctl is-active httpd" -i /opt/ansible/inventory/hosts.ini
```

Y una prueba que casi nadie hace y que diferencia a un aprobado de un
notable: **ejecutar la solución DOS veces**. La segunda ha de salir con
`changed=0` en todo. Si cambia algo, no es idempotente.

## 5 · Errores típicos que cuestan puntos

1. **`hosts` equivocado.** El enunciado dice "todos los nodos": es el
   grupo `nodes`. Con `hosts: node1` la mitad de la flota queda sin
   configurar y el corrector lo canta.
2. **Olvidar `become: true`.** Crear usuarios y paquetes sin root
   acaba en `permission denied` a mitad de examen. El `become` se
   pone en el play, de una vez para todas las tareas.
3. **Instalar con `shell: "dnf install -y httpd"`.** Funciona... una
   vez. Pierde idempotencia y en el EX294 real penaliza. Si hay
   módulo, módulo.
4. **`started` sin `enabled`.** El servicio vive hasta el primer
   reinicio. "Habilitar y arrancar" son las dos claves del módulo
   `service`.
5. **YAML con tabulaciones o indentación rota.** Un espacio de menos
   y el play no parsea mientras el cronómetro corre. Dos espacios
   siempre, nunca tabs.

## 6 · Variaciones para practicar (sin soluciones)

1. El mismo examen con **vsftpd** y usuario **ftpadmin**.
2. El usuario debe tener shell `/sbin/nologin` (usuario de servicio).
3. Task extra: publicar una página de bienvenida en
   `/var/www/html/index.html` con `ansible.builtin.copy` y `content`.
4. Contra reloj real: lanza el examen por el flujo normal (CLI
   `./lab.sh exam` o consola web `./lab.sh web`) en vez de leerlo del
   fichero, y compite contra los 15 minutos.

## 7 · Checklist de autoevaluación

- [ ] `hosts: nodes` (ni `all`, ni un nodo concreto)
- [ ] `become: true` en el play
- [ ] Módulos nativos (`dnf` / `user` / `service`), cero `shell`
- [ ] `state: started` **y** `enabled: true` en el servicio
- [ ] Segunda ejecución con `changed=0` (idempotente)
- [ ] Corrección del motor: 3/3

## 4 · Comprobación en el laboratorio

Con la solución de referencia (incluida en el repo):

