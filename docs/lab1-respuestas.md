# Lab 1 — Preguntas de comprobación

**Nombre:** César Pérez Montero
**Profesor:** Richard Aviles Lopez

---

## 1. ¿Cuál es la diferencia entre Working Directory, Staging Area y Local Repository? Da un ejemplo de un archivo pasando por las tres.

- **Working Directory:** son los archivos tal y como están en mi disco, es donde los creo y los edito.
- **Staging Area:** es una "lista de preparación" con los cambios que he elegido para el próximo commit. Un cambio entra aquí con `git add`.
- **Local Repository:** es el historial de commits guardado dentro de la carpeta `.git`.

**Ejemplo:** creé `README.md` en el disco (Working Directory). Con `git add README.md` pasó a la Staging Area (en `git status` aparecía como `A`). Con `git commit -m "docs: add initial project documentation"` quedó guardado en el historial como el commit `655be25`.

## 2. Si modificas un archivo pero no haces git add, ¿aparece ese cambio en tu próximo commit? Explica por qué.

No, ese cambio no aparece en el próximo commit. Un commit solo guarda lo que está en la Staging Area. Si modifico un archivo y no hago `git add`, el cambio se queda únicamente en el Working Directory. Esto permite elegir qué cambios van en cada commit.

## 3. ¿Por qué git status no mostraba las carpetas vacías que creaste en la Parte C? ¿Qué truco usamos para
## solucionarlo?

Git guarda el contenido de los archivos, no las carpetas. Una carpeta solo existe para Git si contiene algún archivo, por eso las carpetas vacías de la Parte C no aparecían en `git status`. El truco fue crear dentro de cada una un archivo vacío llamado `.gitkeep`.

## 4. Explica con tus palabras qué es HEAD.

HEAD es una referencia que indica "dónde estoy ahora", normalmente apunta a la rama activa y, a través de ella, a su último commit. Cuando hago un commit, la rama avanza y HEAD avanza con ella. En `git log` se ve, por ejemplo, como `HEAD -> main`.

## 5. ¿Qué diferencia hay entre crear una branch con git switch -c y crear una carpeta nueva con mkdir? ¿Cómo lo comprobamos en la Parte G?

`mkdir` crea una carpeta física en el disco. `git switch -c` no crea ninguna carpeta: crea una línea de historial alternativa, y los mismos archivos del disco cambian según la rama en la que esté.

En la Parte G lo comprobamos ejecutando `dir docs\` en cada rama: en `main` solo aparecía `customer-schema.md`, mientras que en `feature/customer-search` aparecía además `customer-search.md`, sin haber cambiado de carpeta.

## 6. Durante el conflicto de la Parte H, ¿qué representaba el contenido entre <<<<<<< HEAD y =======? ¿Y entre ======= y >>>>>>>?

- Entre `<<<<<<< HEAD` y `=======` estaba la versión de **mi rama actual** (`main`), que tras fusionar `fix/readme-title` tenía el título *"Oracle Database Lab (Training Edition)"*.
- Entre `=======` y `>>>>>>> fix/readme-subtitle` estaba la versión de **la rama que estaba fusionando**, con el título *"Oracle Database Lab — Academic Version"*.

Se ve en la Figura 5. Para resolverlo dejé el título que me interesaba, borré los marcadores e hice `git add` y `git commit` (commit `8e53ea7 merge: resolve README title conflict`).

## 7. ¿Por qué NO se debe hacer git commit --amend sobre un commit que ya se subió con git push?

`--amend` no modifica el commit, sino que crea uno nuevo con otro identificador que lo sustituye. Si el commit original ya está en GitHub, mi historial local y el remoto dejan de coincidir. El siguiente `push` será rechazado, si lo fuerzo romperé el historial de cualquier persona que ya se hubiera descargado el commit original.

## 8. Si borras por accidente la carpeta .git de tu proyecto, ¿qué se pierde exactamente? ¿Se pierde también el código fuente que está en el disco?

Se pierde todo el historial: los commits, las ramas, la Staging Area, la configuración del repositorio (como los remotos) y los cambios guardados con stash. El código fuente que está en el disco no se pierde, porque el Working Directory sigue ahí, pero la carpeta deja de ser un repositorio de Git. Si el proyecto estaba subido a GitHub, podría recuperarlo con `git clone`.

## 9. Explica con tus propias palabras la diferencia entre Git y GitHub, sin usar la palabra "nube".

Git es un programa que se instala en el ordenador y controla las versiones de los archivos, funciona sin conexión a Internet y sin GitHub. GitHub es un servicio web de otra empresa que aloja copias de repositorios Git en sus servidores y añade herramientas para trabajar en equipo.

## 10. ¿Por qué no se debe subir un archivo .env con contraseñas reales a un repositorio, aunque el repositorio sea privado?

Aunque el repositorio sea privado, puede hacerse público por error, se pueden añadir colaboradores, se clona en otros equipos y puede sufrir filtraciones. Además, aunque borre el archivo después, la contraseña sigue en el historial de commits. Lo correcto es añadir `.env` al `.gitignore`, subir un `.env.example` sin valores reales y cambiar cualquier contraseña que se haya subido por error.

## 11. Un compañero te dice: "hice push y ahora GitHub me rechaza el segundo push con 'non-fast-forward'". ¿Qué ha ocurrido probablemente y qué comando ejecutarías primero?

Probablemente el repositorio remoto tiene commits que mi copia local no tiene. Otra persona hizo `push` antes, se editó algo desde la web de GitHub o se usó `--amend` sobre un commit ya subido. Git rechaza el `push` para no sobrescribir esos commits.

Lo primero que ejecutaría es `git pull`, para traer esos commits e integrarlos. Después resolvería los conflictos si los hubiera y volvería a hacer `git push`.

## 12. ¿Qué tipo de Conventional Commit (feat, fix, docs, test…) usarías para: añadir un índice de rendimiento a una tabla, corregir una restricción mal definida, y actualizar el README?

- **Añadir un índice de rendimiento a una tabla**: `perf` (si solo se usan los tipos básicos, `feat`)
- **Corregir una restricción mal definida**: `fix` 
- **Actualizar el README**: `docs`
