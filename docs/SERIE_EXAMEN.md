# Serie "Resolviendo el EX294" — escenarios del RHCE_Lab, paso a paso

QUÉ ES: una serie de guías (pensada para acompañar a los vídeos del
canal) en la que se resuelve cada escenario del laboratorio con la
misma mentalidad del examen real: enunciado, cronómetro, corrección
automática y cero pistas a la vista.

Cada episodio sigue la misma estructura (ver plantilla), de modo que
el lector/espectador puede:

  1. Intentar el examen él solo, contra el cronómetro.
  2. Corregirse con el motor (`./lab.sh grade`).
  3. Comparar su enfoque con la solución comentada del episodio.
  4. Repetir con las variaciones finales hasta que salga de memoria.

## Índice de episodios

| Ep. | Escenario | Dificultad | Estado | Documento |
|-----|-----------|------------|--------|-----------|
| 1 | exam_001 - "Apache Básico y Usuarios" | EASY | publicado | [episodio_01.md](serie/episodio_01.md) |
| 2 | exam_002 - roles (consume role_webserver) | MEDIUM | pendiente | - |
| 3 | exam_003 | HARD | pendiente | - |
| 4 | exam_004 - "Grupos, Directorios y Permisos" | EASY | pendiente | - |
| 5 | exam_005 - "SELinux Persistente y Servicios" | MEDIUM | pendiente | - |
| 6 | exam_006 - "Resiliencia, Cron y Storage Compartido" | HARD | pendiente | - |
| 7+ | Exámenes aleatorios del task pool | variada | pendiente | - |

## Cómo usar la serie con el laboratorio

1. Levanta el laboratorio: `./lab.sh up`
2. Lanza el escenario (consola web `./lab.sh web` o el flujo de
   examen de la CLI; ver README, sección "Flujo de un examen").
3. Inténtalo contra el cronómetro. Sin buscar la solución.
4. Corrige: `./lab.sh grade`
5. Lee el episodio y compara patrón a patrón.
6. Repite con las variaciones del final del episodio.

## Documentos de la serie

- [Plantilla de episodio](serie/plantilla_episodio.md) - estructura
  canónica para escribir nuevos episodios.
- [Episodio 1](serie/episodio_01.md) - exam_001, el calentamiento
  perfecto: paquete, usuario y servicio en un solo play.
