# RUNBOOK - Reset total y prueba de fuego

## Cuándo usar esto
Tras cambios del motor o de los checkers que se quieran validar desde cero absoluto,
o cuando el estado del host o de los nodos sea desconocido.

## Procedimiento oficial
# 1. (Opcional) Restaurar snapshot del host laboratoriob - cero absoluto
# 2. Clone fresco: JAMAS pull sobre el arbol que dejo el snapshot
rm -rf /root/RHCE_Lab
git clone https://github.com/llljacklll/RHCE_Lab.git
cd RHCE_Lab
# 3. El lab NO se auto-levanta: up es prerrequisito de test y de grades
./lab.sh up
# 4. Bateria del entorno: debe dar 10/10 y ENTORNO DE LABORATORIO PERFECTO
./lab.sh test
# 5. Calificar examenes (nivel + extension)
./lab.sh grade easy/exam_001.yml
./lab.sh grade medium/exam_002.yml
./lab.sh grade hard/exam_003.yml

## Por que clone fresco y no pull
El snapshot del host trae un arbol viejo con modificaciones locales (ej. " M lab.sh")
que bloquean el fast-forward, y los untracked del arbol anterior NO viajan en git
(baja confirmada: ansible/playbooks/exam003_lvm.yml). El clone garantiza que se
prueba EXACTAMENTE lo que hay en origin/main.

## Regla de oro
Nada vive fuera de git: lo que importa se commitea o se .gitignora.

## Marcador de lectura contra nodos virgenes
- Bateria: 10/10 + banner v1.4.0.
- Examenes: se ESPERAN 0/N, cada FAIL con su razon legible.
- Los tres examenes fijos pueden salir aprobados tras la bateria (Fase 5 fuerza sus soluciones: huella legitima).
- Todo PASS sin huella conocida es sospechoso. Alarmas reales: crash, FAIL mudo, PASS fantasma.
