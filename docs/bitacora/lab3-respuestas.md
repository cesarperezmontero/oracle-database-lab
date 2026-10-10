# Lab 3 — Preguntas de comprobación

**Nombre:** César Pérez Montero
**Profesor:** Richard Aviles Lopez
**Reviewer:** m18u31

---

## Docker

## 1. ¿Qué diferencia hay entre una imagen y un contenedor? Usa como ejemplo lo que hiciste en los ejercicios G2 y G4.

Una imagen es una plantilla de solo lectura. Un contenedor es una instancia en ejecución o detenida, creada a partir de esa plantilla con su propia capa de escritura.

En el apartado G2, `docker run hello-world` descargó la imagen `hello-world:latest` y creó a partir de ella un contenedor con nombre aleatorio (`keen_moore`, ID `fad73269a653`). En el apartado G4 de la misma imagen `alpine:3.20` hice el contenedor `prueba` y después `prueba2`: una sola imagen, varios contenedores independientes. Al borrar los contenedores en G9, la imagen siguió en `docker images`.

## 2. En el Ejercicio G5 el archivo nota.txt desapareció y en el G6 no. Explica por qué.

En el apartado G5 escribí `/tmp/nota.txt` dentro de la capa de escritura del contenedor `prueba`. Esa capa pertenece al contenedor, así que con `docker rm prueba` se borró con él. `prueba2` nació limpio desde la imagen y respondió `cat: can't open '/tmp/nota.txt': No such file or directory`.

En el apartado G6 escribí en `/datos`, que era el volumen con nombre `datos-prueba` montado con `-v datos-prueba:/datos`. El volumen vive fuera del ciclo de vida del contenedor: aunque el primer contenedor se borró al salir (`--rm`), el segundo montó el mismo volumen y leyó `dato importante`.

## 3. ¿Qué diferencia hay entre docker ps y docker ps -a, y qué significa STATUS = Exited (0)?

`docker ps` solo lista los contenedores en marcha, y `docker ps -a` lista todos, incluidos los detenidos. Por eso, tras G2, `docker ps` salió vacío y `docker ps -a` mostró el contenedor de `hello-world`.

`Exited (0)` significa que el contenedor ya no está corriendo y que su proceso principal terminó con código 0, es decir, sin error. Un `Exited (1)` o superior indicaría que terminó con un fallo.

## 4. En -p 8181:8181, ¿qué número corresponde a tu equipo y cuál al contenedor? ¿Qué pasaría con -p 80:8080 en el ejercicio de nginx?

El formato es `anfitrión:contenedor`: el primer número es el puerto de mi equipo y el segundo el del contenedor. En `-p 8181:8181` coinciden, pero en G7 (`-p 8080:80`) el 8080 era el de mi equipo y el 80 el de nginx dentro del contenedor.

Con `-p 80:8080` estaría publicando el puerto 80 de mi equipo hacia el 8080 del contenedor, pero nginx escucha en el 80, no en el 8080. La conexión llegaría a un puerto donde no hay nadie y la página no cargaría.

## 5. ¿Por qué un contenedor de Oracle se queda en marcha y el de hello-world termina solo?

Un contenedor vive exactamente lo que vive su proceso principal. El de `hello-world` imprime un mensaje y termina, así que el contenedor pasa a `Exited (0)`. El de Oracle arranca el motor de base de datos, que es un servidor pensado para no terminar nunca: mientras el motor esté activo, el contenedor sigue `Up`. Lo mismo vi en G4, el contenedor `prueba` siguió vivo hasta que escribí `exit` en `sh`.

## 6. ¿Qué es el digest de una imagen y por qué lo registramos si ya sabemos que usamos :latest?

El digest es la huella SHA-256 del contenido exacto de la imagen. Dos imágenes con el mismo digest son idénticas bit a bit. La mía es:

```
sha256:f988b0c04c4c386cd306a2a914c0d7a9702d83acc31b064a28ad8eb6278a8fba
```

`:latest` es solo una etiqueta móvil, dentro de un mes apuntará a otra versión. El digest no cambia, así que en la evidencia 04 queda registrado qué versión exacta de Oracle instalé (26ai Free 23.26.3) y cualquiera podría reproducir el mismo entorno.

## 7. ¿Qué comando borraría realmente los datos de Oracle? ¿Por qué docker rm oralab-26ai no lo hace?

Los datos están en el volumen `oralab-26ai-data`, montado en `/opt/oracle/oradata`. Lo que los borra de verdad es:

```bash
docker volume rm oralab-26ai-data
```

(o un `docker system prune -a --volumes` con el contenedor detenido). `docker rm oralab-26ai` solo borra el contenedor. Los volúmenes con nombre son independientes y sobreviven, igual que en G6. Si vuelvo a crear el contenedor con el mismo `-v`, Oracle encuentra sus datafiles y arranca con los datos intactos.

## Git, organización y evidencia

## 8. ¿Por qué este laboratorio se hace dentro del repositorio oracle-database-lab, con Issue, branch y Pull Request, en vez de en una carpeta aparte?

Porque la instalación se trata como un cambio versionado y revisable, igual que el código. El Issue #5 define qué hay que conseguir (criterios de aceptación), la branch `chore/5-install-oracle-environment` aísla el trabajo sin tocar `main`, cada Parte queda en un commit con `Refs #5` y el Pull Request permite que un compañero lo revise antes de fusionarlo.

El resultado es trazable y reproducible, los scripts y la evidencia quedan junto al resto del proyecto, y cualquiera puede ver qué se hizo en qué orden y con qué resultado.

## 9. ¿Qué diferencia hay entre source 00-config.sh y bash 00-config.sh? ¿Por qué usamos source?

`bash 00-config.sh` ejecuta el script en una shell hija, define las variables allí y al terminar, desaparecen. `source 00-config.sh` lo ejecuta en la shell actual, así que `$CONT_NAME`, `$EVID` o la función `ts` quedan disponibles para los comandos siguientes.

Lo comprobé sin querer en la Parte G, `script` abre una shell nueva y dentro de ella, `$(ts)` ya no existía (`Command 'ts' not found`). El log se creó como `_03-tutorial-docker.script.log` sin marca de tiempo y tuve que borrarlo y repetir.

## 10. Explica cada parte del nombre 20260915T091230Z_02-docker.script.log.

- `20260915T091230Z`: marca de tiempo ISO 8601 compacta en UTC (15/09/2026, 09:12:30). La `Z` indica UTC. Ordena las evidencias cronológicamente sin depender de la zona horaria.
- `_02`: número del paso que la produjo. Enlaza la evidencia con su script (`02-verificar-docker.sh`) y su Parte (F).
- `docker`: descripción en kebab-case, sin tildes ni espacios.
- `.script.log`: tipo de evidencia, una salida de terminal (frente a `.spool.log` para sesiones SQL y `.png` para capturas).

## 11. ¿Para qué sirve .gitattributes y qué error evita?

Fija cómo normaliza Git los finales de línea. Con `*.sh text eol=lf` (y lo mismo para `.sql` y `.md`), los scripts siempre se guardan y se extraen con LF, aunque alguien los edite en Windows.

Evita el error `$'\r': command not found` al ejecutar un `.sh` con finales CRLF, bash interpreta el `\r` como parte del comando. Fue el primer commit del lab (`29c4fc8`) precisamente para que todos los scripts posteriores nacieran ya protegidos.

## 12. ¿Por qué en este Pull Request elegimos Create a merge commit en lugar de Squash and merge?

Porque aquí cada commit tiene valor propio, corresponde a una parte del laboratorio y documenta cuándo y cómo se verificó cada pieza (Docker, imagen, contenedor, migraciones, Java/SQLcl, ORDS...). Con Squash and merge los 15 commits se fundirían en uno y se perdería ese historial paso a paso. El merge commit los conserva en `main` y además deja constancia de que entraron juntos por el PR.

## Seguridad

## 13. Describe las cuatro capas de la estrategia de contraseñas (Parte D) y qué pasaría si te saltas la primera.

1. **`.gitignore`**: antes de crear el fichero con secretos, se añade `config/.env` (y `backups/`) para que Git nunca lo vea.
2. **Plantilla versionada**: `config/.env.example` documenta qué variables existen (`ORACLE_PWD`, `APP_USER_PWD`, `ORDS_PUBLIC_PWD`) con valores falsos.
3. **Fichero real local**: `config/.env` con las contraseñas reales, comprobado con `git check-ignore -v config/.env` (respondió `.gitignore:1:config/.env`).
4. **Carga sin teclearlas**: `set -a; source config/.env; set +a`, y los scripts usan `"$ORACLE_PWD"`.

Si me salto la primera, `config/.env` aparece en `git status` como fichero nuevo y basta un `git add .` para que la contraseña entre en un commit. Desde ese momento queda en el historial aunque luego se borre.

## 14. ¿Por qué no escribimos la contraseña directamente en el comando docker run, aunque el script no se suba a Git?

Porque todo lo que se teclea en la terminal se guarda en texto plano en `~/.bash_history`, y ahí se quedaría para siempre. Usando `"$ORACLE_PWD"`, en el historial solo queda el nombre de la variable. Además, la contraseña acabaría también en las evidencias si el comando se grabase con `script` o `tee`. Antes de cada commit comprobé que ningún log contenía las contraseñas reales.

## 15. Si descubres tu contraseña en un commit ya publicado, ¿basta con borrarla en un commit nuevo? ¿Qué debes hacer?

No. El commit antiguo sigue en el historial y cualquiera puede recuperarlo navegando hacia atrás o con `git log -p`. Además, GitHub escanea los repositorios en busca de secretos y puede que ya se haya copiado.

Hay que darla por comprometida y **rotarla**, cambiar la contraseña (recrear el contenedor con una nueva en `config/.env`) y avisar al docente para limpiar la branch. Por eso antes del push hice la comprobación O.2 (`git grep -F` y `git log -p | grep -c -F` para las tres contraseñas), que debe dar 0.

## Oracle y herramientas

## 16. ¿Por qué no usamos SPOOL ni @archivo.sql con sqlplus dentro del contenedor, y qué hicimos en su lugar?

Porque `sqlplus` se ejecuta dentro del contenedor, un `SPOOL` escribiría el fichero en el sistema de archivos del contenedor, no en mi repositorio y `@archivo.sql` buscaría el script dentro del contenedor, donde no existe (error SP2-0310).

En su lugar, el fichero `.sql` de mi repositorio entra por la entrada estándar con `<` y la salida vuelve a mi equipo y se guarda con `tee`:

```bash
docker exec -i "$CONT_NAME" sqlplus -s sys/"$ORACLE_PWD"@localhost:1521/"$SERVICE_PDB" as sysdba \
  < scripts/deployment/env/07-primera-conexion.sql \
  | tee "$EVID/spool/$(ts)_07-primera-conexion.spool.log"
```

En cambio, SQLcl (Parte L.4) corre en Ubuntu, así que allí sí usé `SPOOL` directamente.

## 17. ¿Qué hace WHENEVER SQLERROR EXIT SQL.SQLCODE al inicio de V000 y V001, y qué pasaría sin esa línea?

Hace que, ante el primer error SQL, sqlplus termine inmediatamente devolviendo el código de error. Así `08-aplicar-migraciones.sh` (con `set -euo pipefail`) detecta el fallo, muestra `ERROR en ...` y no ejecuta V001 sobre un V000 a medias.

Sin esa línea, sqlplus seguiría ejecutando las sentencias siguientes tras un error y terminaría con código 0. El script creería que todo fue bien y la base quedaría en un estado parcial y difícil de diagnosticar. En mi caso ambas migraciones terminaron sin ningún `ORA-`.

## 18. ¿Qué es una migración y por qué V000 y V001 no se deben editar una vez aplicadas?

Una migración es un script versionado y numerado que lleva la base de datos de un estado al siguiente (V000 crea tablespaces y usuarios, y V001 crea tablas e índices). Se aplican en orden y cada una se ejecuta una sola vez.

Una vez aplicada, editarla rompe la trazabilidad, el fichero ya no describe lo que realmente se ejecutó, y las bases donde ya se aplicó no recibirían el cambio, así que cada entorno quedaría distinto. Cualquier cambio posterior va en una migración nueva (V002...).

## 19. ¿Por qué en SQL Developer se usa el servicio FREEPDB1 y no FREE ni un SID?

Oracle 26ai usa arquitectura multitenant. `FREE` es el contenedor raíz (CDB$ROOT), donde no se trabaja con datos de aplicación. `FREEPDB1` es la base de datos conectable (PDB) donde están los 5 esquemas `ADMIN_*` y el usuario `ALUMNO`. Conectando por **nombre de servicio** `FREEPDB1` voy directamente a la PDB.

Un SID identifica la instancia, no la PDB, y me llevaría a la raíz. De hecho, SQL Developer traía por defecto SID `xe`, que ni siquiera existe en esta imagen. Marqué "Nombre del Servicio" y escribí `FREEPDB1` (captura 11).

## 20. ¿Qué aporta SQLcl frente a SQL*Plus, y por qué un DBA debe dominar ambas?

SQLcl es la herramienta moderna, autocompletado, historial, formato automático (`SET SQLFORMAT ansiconsole`), conexiones guardadas (`CONNECT -save oralab26-system` y `CONNMGR list`) e integración con Liquibase. Además, al instalarse en mi equipo, `SPOOL` escribe directamente en el repositorio.

SQL*Plus existe en cualquier servidor Oracle desde 1982 y es lo que hay cuando solo tienes una terminal en el servidor, como dentro del contenedor (Partes J y K). Un DBA necesita SQLcl para el día a día y SQL*Plus para cuando no hay otra cosa.

## Entorno de trabajo

## 21. ¿Por qué el curso pasa de Git Bash a Ubuntu en WSL 2? Da al menos dos problemas concretos de Git Bash que desaparecen en Ubuntu.

Porque los servidores donde corre Oracle son Linux, y el entorno de trabajo debe parecerse a ellos. Problemas de Git Bash que desaparecen:

- **`docker run -it` falla con "not a TTY"**: en Git Bash había que recurrir a PowerShell. En Ubuntu entré y salí de los contenedores Alpine (G4-G6) sin problema, incluso grabando con `script`.
- **Finales de línea CRLF**: los scripts editados en Windows fallan con `$'\r': command not found`.
- **Conversión de rutas de MSYS**: Git Bash reescribe argumentos que parecen rutas (`/opt/...`), lo que rompe comandos de `docker exec`.
- **Sin gestor de paquetes**: en Ubuntu instalé todas las herramientas (`jq`, `tmux`, `shellcheck`, `openjdk-21-jdk`...) con `apt`.

## 22. ¿Por qué clonamos el repositorio en ~/oracle-database-lab y no trabajamos sobre la carpeta de Windows (/mnt/c/...)? ¿Y por qué recomendamos bash frente a zsh para los scripts del curso?

`/mnt/c` es el disco de Windows visto desde Linux a través de una capa de traducción, es mucho más lento para Git y para muchos ficheros pequeños, y no conserva bien los permisos de Linux. Lo vi en este lab, los ficheros que copié desde `/mnt/e` llegaron todos con permiso de ejecución (`100755`), incluidos `.sql` y `.env.example`, y tuve que corregirlos en un commit aparte (`db473c6`). Dentro de `~` el repositorio vive en el sistema de archivos ext4 nativo de Linux.

Recomendamos bash porque es la shell por defecto en Ubuntu y en casi todos los servidores Linux, los scripts del curso (`#!/usr/bin/env bash`, `set -euo pipefail`, `[[ ]]`) se comportan igual en todas partes. zsh tiene diferencias de sintaxis (expansión de variables y arrays, globbing) que pueden hacer que un script funcione en el portátil y falle en el servidor.
