# Lab 2 — Preguntas de comprobación

**Nombre:** César Pérez Montero
**Profesor:** Richard Aviles Lopez
**Reviewer:** m18u31

---

## 1. ¿Por qué un Issue sin criterios de aceptación es un problema, aunque la descripción general parezca clara?

Porque no se sabe cuándo está terminado. Una descripción como "mejorar la documentación" puede interpretarse de muchas formas, y cada persona tendrá una idea distinta de lo que hay que entregar. Los criterios de aceptación convierten la intención en una checklist verificable: cualquiera puede comprobar objetivamente si el trabajo está hecho.

Además, el Reviewer los usa como lista de comprobación del PR. En el Issue #1 había cuatro criterios (archivo en la raíz, convención de branches, Conventional Commits y enlace desde `README.md`), y gracias al segundo se detectó que las plantillas `<type>/...` no se veían en GitHub: la convención "existía" en el archivo, pero no se podía leer.

## 2. Explica la diferencia entre "Refs #N" y "Closes #N" en un mensaje de commit o en la descripción de un Pull Request.

- **`Refs #N`** solo crea una referencia cruzada: el commit o el PR aparece en la actividad del Issue, pero el Issue sigue abierto. Lo usé en el cuerpo de los commits mientras trabajaba (`0c080ad`, `d277d6e`, `dc91c36`) y en el Issue #1 apareció *"added a commit that references this issue"*.
- **`Closes #N`** (también `Fixes` o `Resolves`) cierra el Issue automáticamente cuando el commit o el PR llega a `main`. Lo puse en la descripción del PR #2 y el Issue #1 se cerró solo al hacer el Squash and merge.

Poner `Closes #N` en un commit que sigue en una branch sin fusionar no cierra nada todavía: el cierre ocurre en el merge.

## 3. ¿Qué ocurre exactamente si intentas hacer git push directamente sobre una branch main protegida? ¿Es un error tuyo o un fallo del sistema?

Git envía los objetos, pero GitHub rechaza actualizar la branch. En la Parte H obtuve:

```
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: - Changes must be made through a pull request.
 ! [remote rejected] main -> main (protected branch hook declined)
```

No es un fallo del sistema: es la protección funcionando como se configuró. Tampoco es exactamente "un error mío", sino un intento de saltarse el proceso. La solución nunca es forzar el push, sino crear una branch y abrir un Pull Request. Después deshice el commit local con `git reset --hard HEAD~1`, que era seguro porque nunca llegó a GitHub.

Para que el rechazo afectara también al propietario del repositorio tuve que activar *Do not allow bypassing the above settings*. Sin esa opción, un administrador puede saltarse la regla.

## 4. Un compañero te dice: "he aprobado el PR sin mirar los archivos, total ya me fío". ¿Qué riesgo tiene esa forma de revisar?

Es un *rubber-stamping*: la aprobación deja de significar "lo he comprobado" y pasa a significar "confío en ti". Se pueden colar errores, secretos, permisos excesivos o cambios accidentales que nadie ha leído, y la protección de `main` pierde su sentido, porque se cumple la regla de forma técnica pero no su objetivo. Además, la responsabilidad del fallo se diluye entre el autor y el reviewer.

En este lab, mirando el archivo renderizado se vio que las plantillas desaparecían. Leyendo solo la descripción del PR ("Verified links render correctly") no se habría detectado.

## 5. Si el reviewer pide un cambio y tú ya habías hecho push de tu branch, ¿tienes que abrir un Pull Request nuevo? Explica qué ocurre técnicamente con el PR existente cuando haces un nuevo commit.

No. Un Pull Request no guarda una lista fija de commits: compara una branch (head) con otra (base). Si hago nuevos commits en la misma branch y los subo con `git push`, el PR los incorpora automáticamente y se actualizan sus pestañas *Commits* y *Files changed*.

Es lo que pasó en la Parte G: después del Request changes subí `d277d6e` y `dc91c36` a `docs/1-contribution-guidelines`, y el PR #2 pasó de 1 a 3 commits. Los comentarios sobre líneas que cambiaron quedaron marcados como *Outdated*, pero la conversación se conservó entera. Si abriera un PR nuevo, se rompería el hilo de la revisión.

## 6. Describe con tus palabras la diferencia entre Merge commit, Squash and merge y Rebase and merge. ¿Cuál usarías para una branch con commits "wip", "fix", "fix2", "ok ya"?

- **Merge commit:** mete en `main` todos los commits de la branch tal cual y añade un commit de fusión con dos padres. Conserva toda la historia, incluidos los commits intermedios.
- **Squash and merge:** junta todos los commits de la branch en uno solo nuevo y lo añade a `main`. La historia de `main` queda lineal y limpia.
- **Rebase and merge:** reaplica los commits de la branch uno a uno encima de `main`, sin commit de fusión. Historia lineal, pero con todos los commits.

Para una branch con "wip", "fix", "fix2", "ok ya" usaría **Squash and merge**: esos commits no aportan nada por separado y ensuciarían `main`. Es lo que hice en el PR #2: tres commits (el cambio y dos correcciones de la revisión) se convirtieron en `8209403 docs: add contribution guidelines (#2)`.

## 7. ¿Por qué borrar una branch después del merge no elimina el trabajo realizado en ella?

Porque una branch es solo un puntero a un commit, no una copia de los archivos. Tras el merge, el contenido ya está integrado en `main` (en mi caso, en el commit `8209403`), así que borrar el puntero no borra nada de lo integrado. Además, los commits originales siguen visibles en el PR #2, y GitHub ofrece el botón *Restore branch* para volver a crear el puntero.

Con Squash and merge, `git branch -d` me avisó de que la branch *"is not fully merged"*: los commits originales no están en `main`, porque fue un commit nuevo con el mismo contenido. Por eso usé `git branch -D`, sabiendo que el PR ya estaba *Merged*.

## 8. ¿Qué información debería contener siempre la descripción de un Pull Request, como mínimo?

Debe responder sin que nadie pregunte a:

- **Qué hace el cambio** (*Summary*) y **qué archivos o piezas toca** (*Changes*).
- **Cómo se ha probado** (*Testing*): pasos concretos o comprobaciones realizadas.
- **Por qué se hace** (*Related Issue*), con la palabra clave para cerrarlo (`Closes #N`).
- Si aplica, evidencia visual (capturas del antes y el después).

Es la plantilla Summary / Changes / Testing / Related Issue que usé en el PR #2.

## 9. Un reviewer escribe solo "esto está mal" como comentario. ¿Qué le falta a ese comentario para ser útil? Reescríbelo tú con un ejemplo inventado.

Le falta todo lo que permite actuar: **qué** está mal exactamente, **por qué** importa, **qué** propone para solucionarlo y **si bloquea** o no el merge. En un canal escrito y asíncrono, además, se lee más duro de lo que se pretende y provoca una respuesta defensiva.

Ejemplo reescrito sobre un script SQL inventado:

> `issue (blocking): this DELETE has no WHERE clause, so it would remove every row in CUSTOMERS when the migration runs. Could we filter by STATUS = 'INACTIVE' and add a rollback script that restores the deleted rows?`

## 10. ¿Qué diferencia hay entre que main esté protegida y que simplemente el equipo "se ponga de acuerdo" en no hacer push directo?

Un acuerdo es una política que depende de la disciplina y la memoria de cada persona: basta un despiste, una prisa o una persona nueva que no lo conozca para que alguien haga push directo a `main`. Con la branch protegida, la política se aplica técnicamente: GitHub rechaza el push (lo comprobé en la Parte H) y no deja hacer merge sin la aprobación requerida (el PR #2 estuvo bloqueado hasta el Approve de `m18u31`). La norma deja de ser una sugerencia y se cumple siempre, sin excepciones, ni siquiera para el administrador si se activa *Do not allow bypassing*.

## 11. Explica con un ejemplo propio la diferencia entre un comentario issue: (blocking) y uno nitpick: (if-minor) en formato Conventional Comments.

- **`issue (blocking)`:** hay un problema real que impide considerar el cambio listo. Hasta que se resuelva no se debe aprobar.
  > `issue (blocking): the new index is created on CUSTOMER_EMAIL but the query in the runbook filters by CUSTOMER_ID, so it will never be used. Please index the column the query actually filters on.`
- **`nitpick (if-minor)`:** detalle menor de estilo o consistencia. El autor decide si lo cambia, y por sí solo nunca debería bloquear.
  > `nitpick (if-minor): the other migration files use uppercase SQL keywords; this one mixes "create table" and "CREATE INDEX".`

La diferencia es la severidad, y está declarada explícitamente: no hay que deducirla del tono.

## 12. Si tu próximo commit es feat!: cambia la firma de la función principal de la API, ¿qué tipo de versión SemVer se dispara y por qué?

Una versión **MAJOR** (por ejemplo, de 2.1.0 a 3.0.0). El `!` después del tipo, o un pie `BREAKING CHANGE:`, indica un cambio que rompe la compatibilidad. Al cambiar la firma de la función principal, el código que ya la usaba dejará de funcionar sin modificaciones. Aunque el tipo sea `feat` (que por sí solo daría MINOR), el `!` tiene prioridad y obliga a subir la versión mayor para avisar a quienes dependen de la API.

## 13. ¿Por qué abrir un Draft PR desde el primer commit estructural puede ahorrar tiempo al equipo, aunque parezca más lento para el autor individual?

Porque permite validar el enfoque antes de invertir horas en los detalles (*Fail Fast*). Si un compañero detecta que el diseño no es el adecuado cuando solo existe el esqueleto, corregirlo cuesta poco. Si lo detecta al final, con toda la lógica y los tests ya escritos, rehacerlo es caro, y el autor tiende a defender un mal diseño solo por las horas invertidas (falacia del coste hundido).

Para el autor supone abrir el PR antes y recibir comentarios a mitad de trabajo, pero el equipo se ahorra revisiones largas, cambios de arquitectura tardíos y rondas de ida y vuelta.
