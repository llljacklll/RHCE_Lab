# Episodio 02 — Roles, variables y Jinja2 (exam_002)

- Serie: preparación del EX294 con RHCE_Lab
- Escenario: scenarios/medium/exam_002.yml — dificultad media — 30 minutos
- Requisitos: episodio_01 superado, lab levantado y batería ./lab.sh test en verde
- Material del repo: scenarios/medium/exam_002.yml (enunciado),
  ansible/playbooks/exam_002.yml (solución de referencia),
  ansible/roles/role_webserver/ (el rol que te dan hecho)

## 0. El enunciado

    Título:  Roles, Variables y Jinja2
    Dificultad: media — Tiempo: 30 minutos

    task_1: Usando el role 'role_webserver', instalar httpd en los nodos con
            el puerto 8080, y definir la variable 'owner' como 'Victor'
    task_2: Crear un archivo index.html en /var/www/html/ que contenga la
            palabra 'Victor'

Subtexto del enunciado: el rol ya existe y NO se toca. El ejercicio entero es
consumirlo bien desde el play. Es exactamente el músculo de la pregunta 6 del
examen real (ver docs/INTEL_EX294.md): te dan un rol hecho y casi solo hay que
llamarlo, con los README.md del rol como primera lectura.

## 1. Análisis previo

Primera acción física: leer el rol ANTES de escribir una línea. En el examen
real los roles dados traen README.md; aquí, el fichero clave es
defaults/main.yml:

    # ansible/roles/role_webserver/defaults/main.yml
    http_port: 80
    owner: "Admin"

Esos DOS nombres (http_port, owner) son el contrato del ejercicio. Todo
override que no use exactamente esos nombres crea una variable huérfana:
Ansible no da error, el rol sigue con sus defaults y el examen se cae en
silencio. El fallo silencioso es el peor tipo de fallo.

- Las plantillas del rol consumen las variables: index.html.j2 usa
  {{ owner }}, {{ http_port }} y {{ ansible_hostname }}; ports.conf.j2 escribe
  Listen {{ http_port }}. Por eso el override del play llega hasta la web y
  hasta la configuración del puerto.
- Precedencia que manda aquí: vars del play > role defaults. No hay que tocar
  el rol ni tirar de extra-vars ni de group_vars.
- La task_2 no pide un playbook nuevo: el index.html lo despliega el propio
  rol con su plantilla. Si la task_1 está bien, la task_2 sale sola.
- Qué corrige grade (afirmaciones salidas del propio repo):
  - task_1: check_package — httpd instalado en los nodos (rpm -q).
  - task_2: check_file — /var/www/html/index.html contiene "Victor" (grep exacto).
  - El puerto 8080 NO entra en la corrección automática: es didáctico y se
    verifica a mano (sección 4).
- Tiempo objetivo: 5-8 minutos. Es un ejercicio de concepto, no de mecánica.

## 2. Esqueleto de partida

    ---
    - name: "EXAM 002 :: Aplicar role_webserver con overrides (8080 / Victor)"
      hosts: nodes
      become: true
      vars:
        # overrides aquí
      roles:
        - role_webserver

Tres decisiones que el enunciado ya ha tomado por nosotros:

- hosts: nodes — dice "en los nodos", que es el grupo nodes del inventario del lab.
- El rol se declara en la sección roles (no como task con include_role): para
  consumir un rol entero con overrides es la forma más limpia.
- Las vars del play son el sitio donde viven los overrides (precedencia de la
  sección 1).

## 3. Solución paso a paso

Paso 1 — Overrides con los nombres EXACTOS del contrato del rol:

    vars:
      http_port: 8080
      owner: "Victor"

Paso 2 — Play completo (ansible/playbooks/exam_002.yml):

    ---
    - name: "EXAM 002 :: Aplicar role_webserver con overrides (8080 / Victor)"
      hosts: nodes
      become: true
      vars:
        http_port: 8080
        owner: "Victor"
      roles:
        - role_webserver

Paso 3 — Aplicar. En el día a día del lab, ./lab.sh test aplica y gradea este
escenario dentro de la batería. Para lanzarlo a mano, el play vive en
ansible/playbooks/exam_002.yml y se aplica con el flujo habitual desde el control.

Lo que debe pasar, en orden:

1. dnf instala httpd.
2. ports.conf.j2 se despliega a /etc/httpd/conf.d/ports.conf con Listen 8080
   (el override ya llega al rol) y, como el fichero cambia, dispara el
   handler "reiniciar httpd".
3. index.html.j2 escribe la página con owner=Victor, http_port=8080 y el
   hostname del nodo.
4. El servicio httpd queda started y enabled.

Detalle fino: el handler solo salta si ports.conf cambia. Re-aplicar el mismo
play sin cambios no reinicia nada: idempotencia normal, no es un fallo.

## 4. Comprobación (grade + a mano)

La nota automática (los checks del repo):

- task_1: check_package — httpd instalado en los nodos.
- task_2: check_file — /var/www/html/index.html contiene "Victor".

Y a mano, el hábito del examen real (donde el ssh desde el entorno está
prohibido, ver docs/INTEL_EX294.md):

- Ver el puerto sin tocar nada:

    ansible nodes -m command -a "cat /etc/httpd/conf.d/ports.conf"

  Debe mostrar Listen 8080.

- Ver la página servida:

    ansible nodes -m command -a "curl -s http://localhost:8080/"

  Debe devolver la página con Victor (si el nodo no tiene curl, vale con
  cat /var/www/html/index.html).

- El simulacro de lo que harías en el examen, --check --diff:

    ansible-playbook ansible/playbooks/exam_002.yml --check --diff

## 5. Errores típicos

1. Poner los overrides en defaults/main.yml del rol: funciona, pero se toca un
   rol ajeno. En el examen los roles dados no se tocan; el override va en el
   play (o donde diga el enunciado).
2. Nombre de variable que no cuadra (web_port, port, Owner): no hay override,
   no hay error y el rol sigue con 80/Admin. Fallo silencioso.
3. Escribir "victor", "VICTOR" o "Victor " (con espacio): el grep de grade es
   exacto. La task_2 se cae por un carácter.
4. Olvidar become: true: el dnf y el template a /etc fallan por permisos.
5. Mirar solo la nota de grade y no verificar el 8080: en ESTE escenario el
   puerto es didáctico y grade no lo corrige, pero en el examen real el
   corrector sí verifica el detalle. Lección: comprobar cada dato pedido uno
   a uno, no solo lo que crees que puntúa.
6. Re-implementar el rol como tasks en el play: duplica trabajo, se sale del
   enunciado y quema tiempo. Si te dan un rol, se consume.

## 6. Variaciones para practicar

- Volver atrás: mismo play con http_port: 80 y owner: "Admin" — verificar que
  al no cambiar nada real, el handler no salta.
- Extra-vars gana a todo:

    ansible-playbook ansible/playbooks/exam_002.yml -e "http_port=9090 owner=Test"

  Sirve para ver la precedencia en vivo: extra-vars > vars del play > role defaults.

- Fuente en el inventario: definir http_port en group_vars/nodes y quitar las
  vars del play. Las vars de grupo ganan a los defaults del rol, pero pierden
  contra las vars del play: buen experimento para fijar la tabla de precedencia.
- Dos roles en la lista: declarar un segundo rol trivial después de
  role_webserver y observar el orden de ejecución (orden de declaración).
- Músculo del examen real (pregunta 5): construir el rol en vez de consumirlo
  — ansible-galaxy init apache + httpd + firewalld + index.html.j2. Eso cae en
  el banco de ejercicios del LOTE 40.

## 7. Checklist de salida

- [ ] El play declara el rol en roles: y no lo re-implementa.
- [ ] Los overrides usan los nombres exactos de defaults/main.yml del rol.
- [ ] become: true presente.
- [ ] grade: task_1 y task_2 en verde.
- [ ] Verificado a mano: ports.conf con Listen 8080 y página con Victor.
- [ ] Re-aplicar el play no cambia nada y el handler no salta (idempotencia).
- [ ] Tiempo dentro del objetivo (5-8 minutos).
