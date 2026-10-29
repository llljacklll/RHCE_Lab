# Plantilla de episodio (Serie "Resolviendo el EX294")

Copiar este esqueleto a `docs/serie/episodio_NN.md` y rellenarlo.

Reglas de la casa:
- Nada de spoilers antes de la sección 3.
- Toda afirmación sobre el corrector debe salir del propio repo
  (`scenarios/**.yml` y comentarios de `ansible/playbooks/exam_*.yml`),
  nunca de memoria.
- El playbook de la sección 3 debe coincidir con la solución de
  referencia del repo, o indicar explícitamente la diferencia.

---

# EPISODIO N — exam_XXX · "<Título>"

**Dificultad:** ... · **Tiempo límite:** ... min · **Tasks:** ... · **Checks:** ...

> 2-3 líneas de gancho: qué se aprende aquí y por qué este escenario
> es representativo del EX294.

## 0 · El enunciado
Tabla task a task con el texto literal del escenario.

## 1 · Análisis: qué pide de verdad el enunciado
Tabla: task -> módulo correcto -> qué validará el checker.
Lecturas finas del enunciado ("todos los nodos", "persistente",
"habilitar Y arrancar"...).

## 2 · El esqueleto (los 30 primeros segundos del examen)
Play base: name, hosts, become, tasks.

## 3 · Solución paso a paso
Playbook completo, tarea por tarea, explicando cada línea no obvia.

## 4 · Comprobación en el laboratorio
`./lab.sh run <solución>`, `./lab.sh grade` y verificación manual.

## 5 · Errores típicos que cuestan puntos
5-6 errores, cada uno con su porqué (no solo el qué).

## 6 · Variaciones para practicar
3-4 mutaciones del enunciado, sin solución: para repetir de memoria.

## 7 · Checklist de autoevaluación
Casillas que resumen los criterios de éxito del escenario.
