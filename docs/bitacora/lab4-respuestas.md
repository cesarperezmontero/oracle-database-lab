# Lab 4 — Respuestas

**Nombre:** César Pérez Montero
**Profesor:** Richard Aviles Lopez

---

## Parte A — Punto de partida, copia del Lab 3 y diagnóstico

### Punto de control: archivos FUERA del volumen

Ninguno. La copia (evidencia 00) marca los 26 archivos como "dentro" y `archivos_fuera_del_volumen=0`. Los cinco datafiles de negocio (`academia01.dbf` ... `fintech01.dbf`) se crearon en `$ORACLE_HOME/dbs` porque V000 les da una ruta relativa y no hay OMF (`db_create_file_dest` vacío): Oracle resuelve la ruta relativa contra `$ORACLE_HOME/dbs`.

En mi imagen (la oficial `container-registry.oracle.com/database/free:latest`) `$ORACLE_HOME/dbs` es un enlace simbólico a `/opt/oracle/oradata/dbconfig/FREE/dbs`, dentro del volumen. Por eso la evidencia 01 dice "DENTRO del volumen, pero en carpeta no estándar". Los datos no se perderían al recrear el contenedor, pero están en la carpeta de configuración, mezclados con el SPFILE, el password file y los redo archivados, en vez de en `FREE/FREEPDB1/`.

La copia tardó 3 min 49 s, ocupa 958 MB comprimida (volumen de 7079 MB) y las cuatro sumas SHA-256 dan OK.

### Reto: informe de diagnóstico

1. **Alto** · V000 tiene en claro las contraseñas de los cinco `ADMIN_*` y ya están en el historial de Git: hay que invalidarlas primero, porque cualquiera con acceso al repo puede usarlas hoy (Parte D, V003).
2. **Alto** · `08-aplicar-migraciones.sh` pasa `sys/<contraseña>` en la línea de comandos: se ve con `ps` y queda en el historial de la shell (Parte D, 08 v2).
3. **Medio** · Datafiles de negocio en `$ORACLE_HOME/dbs` por la ruta relativa de V000: en esta imagen sobreviven porque `dbs` enlaza al volumen, pero en una imagen sin ese enlace se perderían al recrear el contenedor (Parte C).
4. **Medio** · La base está en ARCHIVELOG (`ENABLE_ARCHIVELOG=true` de la imagen oficial) sin FRA: 13 redo archivados (2017 MB) en `$ORACLE_HOME/dbs/arch` que nadie purga. Si llenan el disco, la base se para (se ordena en el Lab 5, Parte L).
5. **Bajo** · `05-crear-contenedor.sh` publica el 8181 sin servicio detrás (ORDS escucha en 8080 en Linux): superficie expuesta sin uso (Parte C, 05 v2).

Orden: primero lo que ya está expuesto (1 y 2), después lo que puede perder o parar la base (3 y 4) y al final lo cosmético (5).

### P1

**A y D.** Tras `SHUTDOWN IMMEDIATE` todos los datafiles comparten el SCN del checkpoint final, así que la copia es consistente y se abre con `STARTUP` sin aplicar redo. No exige ARCHIVELOG (B), no pierde nada confirmado (C) y no necesita RMAN (E).

## Parte B — La cuenta de observabilidad C##OPS_RO

La evidencia 02 muestra `C##OPS_RO` común (`COM = YES`) y `OPEN` en CDB$ROOT y FREEPDB1. PDB$SEED no sale porque las vistas CDB_ no muestran la semilla. Comprobé `ro.sh` a mano:
- desde FREE ve 2 filas en `v$pdbs` (PDB$SEED y FREEPDB1, gracias a `CONTAINER_DATA = ALL`);
- desde FREEPDB1 solo ve 1;
- un `CREATE TABLE` en FREEPDB1 falla con `ORA-01031: insufficient privileges`.

### Reto: mínimo privilegio

Dar el rol DBA a `C##OPS_RO` tiene dos riesgos concretos:
1. **Robo de credencial.** La contraseña de una cuenta de monitorización vive en `config/.env` y en las herramientas que la usan. Si se filtra, con DBA quien la tenga puede leer los datos de negocio de todos los esquemas (`SELECT ANY TABLE`: pacientes de clínica, movimientos de fintech) y cambiarlos o borrarlos (`DROP ANY TABLE`, `ALTER SYSTEM`).
2. **Error humano sin red.** Un `DROP` o un `ALTER SYSTEM` lanzado por error desde la ventana de "solo mirar" se ejecuta, en vez de fallar con ORA-01031. Además, la auditoría ya no distingue a quien observa de quien administra.

Para leer el alert log no hace falta ningún rol nuevo. Basta un único privilegio de objeto: `GRANT SELECT ON sys.v_$diag_alert_ext TO c##ops_ro CONTAINER = ALL;`. Es lo que hace `11-ampliar-ops-ro.sql` en la Parte J, porque SELECT_CATALOG_ROLE no incluye esa vista.

## Parte C — Reubicar los datafiles y prueba de persistencia

`03-reubicar-datafiles.sh` movió los cinco `TBS_*` de `$ORACLE_HOME/dbs` (que en mi imagen es `dbconfig/FREE/dbs`, dentro del volumen) a `/opt/oracle/oradata/FREE/FREEPDB1/`, con `AUTOEXTEND ON NEXT 50M MAXSIZE 1G`. Usé el método offline: `OFFLINE NORMAL`, `cp -p`, `RENAME DATAFILE`, `ONLINE` y, solo después, `rm` del original. Free no tiene `MOVE DATAFILE` online. La segunda ejecución respondió "Nada que reubicar" (idempotencia) y en `dbconfig/FREE/dbs` no quedó ningún `*01.dbf`.

Prueba de persistencia: `SHUTDOWN IMMEDIATE`, `docker rm` y recreación con `05` v2.
- Tardó 1 min 31 s, de los que 40 s fueron hasta healthy.
- Los mismos cinco tablespaces ONLINE y las mismas tablas 3/3/2/3/3. `aca_estudiantes` tiene 0 filas: los datos de demostración llegan con V002 en la Parte D.
- `docker port` ya solo muestra 1521.
- El contenedor nuevo no recibe contraseñas: en `docker inspect` la variable `ORACLE_PWD` está vacía (es la de la imagen).

### P2

**B.** OFFLINE, copiar con el sistema operativo, RENAME DATAFILE y ONLINE. A (`MOVE DATAFILE` online) es una opción de Enterprise Edition. En C, `RENAME` no copia nada: solo cambia la ruta en el control file. D, `SHUTDOWN ABORT`, deja la base inconsistente y además es innecesario.

### Reto: que no vuelva a pasar

Activé OMF en FREEPDB1 con `scripts/lab4/03-omf.sql`, en su propio commit:

```sql
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SYSTEM SET db_create_file_dest = '/opt/oracle/oradata' SCOPE = BOTH;
```

`SCOPE = BOTH` aplica el cambio ya y lo deja en el SPFILE (para esta PDB, `ISPDB_MODIFIABLE = TRUE`), así que sobrevive a reinicios. Lo fijé en la PDB porque es donde se crean los tablespaces de negocio.

Después, `CREATE TABLESPACE tbs_x;` sin cláusula DATAFILE ya no da error ni usa `$ORACLE_HOME/dbs`. Oracle crea y nombra el archivo dentro del volumen: `/opt/oracle/oradata/FREE/55E54F210F100828E0630B00580ADFD0/datafile/o1_mf_tbs_x_ogy19s83_.dbf` (el GUID de FREEPDB1). Le da 100 MB, AUTOEXTEND y `DROP TABLESPACE` borra el archivo solo.

OMF arregla el **dónde**, pero no el **cuánto**: el archivo salió con `max_mb = 33554432` (32 TB), porque en 26ai el tablespace por defecto es BIGFILE y no tiene techo. Las migraciones siguen necesitando `MAXSIZE`.

## Parte D — Migraciones V003 (contraseñas) y V002 (datos de demostración)

La evidencia `04-password-v000` es la prueba de que el defecto era real y está corregido:
- **Antes de V003**, la contraseña de `admin_academia` que quedó en V000 (y en el historial de Git) todavía abría sesión: `SELECT user` devolvió `ADMIN_ACADEMIA`.
- **Después**, la misma contraseña da `ORA-01017`.

Los cinco `ADMIN_*` quedan con `AUTHENTICATION_TYPE = NONE` y `ACCOUNT_STATUS = OPEN`: son cuentas de solo esquema, que poseen sus objetos pero no tienen forma de iniciar sesión. Para la prueba, SQLcl recibió la contraseña por la entrada estándar, no como argumento.

`08` v2 aplica las migraciones con `/ as sysdba` (autenticación del sistema operativo dentro del contenedor), así que ya no hay `sys/<contraseña>` que se vea con `ps`.

V002 cargó 20 000 estudiantes, 40 asignaturas y 60 000 matrículas en 13 s; la fila 101 es `00000101X`, ACTIVO. Al aplicarla otra vez respondió "V002 ya aplicada (20000 estudiantes): no se inserta nada". Las dos ejecuciones están en `spool/`.

### P-D1

**C.** `NO AUTHENTICATION` deja la cuenta sin ningún método de autenticación: ni la contraseña antigua ni una nueva sirven hasta que alguien le asigne una con `IDENTIFIED BY`. `ACCOUNT LOCK` (A) conserva la contraseña y se deshace con `UNLOCK`. `PASSWORD EXPIRE` (B) deja entrar con la contraseña antigua para cambiarla. Revocar `CREATE SESSION` (D) no sirve si la cuenta lo recibe por un rol o lo vuelve a obtener.

## Parte E — Instancia y base de datos, arranque por etapas y alert log

### Instancia frente a base (evidencias 05)

| Dato | Pertenece a | Valor | Por qué |
|---|---|---|---|
| `HOST_NAME` | instancia | `1798f1f0fffc` | Es el id del contenedor: en la Parte A era `ef2b142804c6` y cambió al recrearlo en la Parte C |
| `STARTUP_TIME` | instancia | 2026-11-07 11:00:45 | El arranque del contenedor nuevo |
| PID de `db_pmon_FREE` | instancia | 5759 | 57 procesos de background, 2,06 GiB de memoria en el contenedor |
| `DBID` | base | 1509902213 | No cambia aunque se borre el contenedor: identifica a la base |
| `CREATED` | base | 2026-07-05 | Cuando se construyó la base de la imagen, no cuando se arrancó |
| Archivos | base | 16 datafiles (4329 MB), 3 tempfiles, 3 redo y 2 control files | Viven en el volumen y existen aunque la instancia esté parada |

`C##OPS_RO` entra por el servicio `free` a CDB$ROOT (SID 182). El servicio `freepdb1` es la puerta de FREEPDB1. Con una sesión SQLcl abierta aparece su proceso servidor dedicado, `oracleFREE (LOCAL=NO)`, junto al listener `tnslsnr`. El listener ve los mismos servicios en estado READY, porque LREG los registró. En mi entorno `LOG_MODE` es ARCHIVELOG (ver Parte A).

### Punto de control: cada error con mis palabras

- **ORA-01507 en NOMOUNT:** la instancia ya existe (SGA de 1 603 398 928 bytes y procesos), pero no ha abierto el control file. `v$database` sale de él y falla. `v$parameter` sí responde porque sale del SPFILE, que ya está cargado en memoria (`spfile`, `control_files`, `db_name`).
- **ORA-01219 en MOUNT:** el control file ya está abierto, así que funcionan `v$database` (FREE, MOUNTED, ARCHIVELOG), `v$controlfile` (2) y `v$datafile` (16 conocidos). `dba_tables` es diccionario: vive en SYSTEM, un datafile todavía cerrado. Solo funcionan las vistas fijas.
- Tras `ALTER DATABASE OPEN`, FREEPDB1 abrió sola en READ WRITE porque `dba_pdb_saved_states` guarda `FREEPDB1 / OPEN`.

### P3

**A y C.** `STARTUP_TIME` es de la instancia y cambia en cada arranque (A). `CREATED` es la fecha de creación de la base (C): 2026-07-05 frente a 11:00 de hoy. B es falsa: el DBID no cambió al recrear el contenedor. D es falsa: una instancia monta una sola base. E es falsa: `v$database` responde ya en MOUNT.

### P4

**A y C.** En NOMOUNT solo hay SPFILE en memoria. Se puede consultar `v$parameter` y crear un control file (`CREATE CONTROLFILE`). `dba_users` exige OPEN. ARCHIVELOG y renombrar SYSTEM exigen MOUNT.

### P5

**B. MOUNT.** El cambio de modo se escribe en el control file, que debe estar abierto, y los datafiles deben estar cerrados.

### Reto: el parte del reinicio

Datos del último reinicio, solo del alert log (horas UTC; local = +1 h):
- **Parada pedida:** 11:28:51. `Shutting down ORACLE instance (immediate)`, iniciada por `sqlplus@1798f1f0fffc`.
- **Parada completa:** 11:29:43, es decir 52 s. Casi todo es la espera de 50 s entre `Stopping background process SMCO` y `Stopping background process CJQ0`: la instancia esperó a que terminaran procesos de background, no sesiones de usuario. El cierre de las PDB, `CLOSE NORMAL` y `DISMOUNT` tardaron unos 2 s.
- **Arranque:** `Starting ORACLE instance (normal)` a las 11:29:44. `Completed: ALTER DATABASE MOUNT` a las 11:29:46. `Completed: ALTER DATABASE OPEN` a las 11:29:49,5. La base estuvo abierta 5,5 s después de empezar a arrancar; en total, unos 59 s sin servicio.
- **Recuperación de instancia:** no. Solo aparece "Crash Recovery excluding pdb 2/3 which was cleanly closed", que confirma que todo se cerró limpio. No hay "Beginning/Completed crash recovery". `Thread 1 opened at log sequence 14`, la misma secuencia con la que se cerró.
- **Errores:** dos `ORA-00800 [Set Priority Failed]`, uno de VKTM y otro de LGWR. Son **conocidos**: el contenedor no tiene `CAP_SYS_NICE` y Oracle no puede subir la prioridad de esos procesos; la base funciona. Ninguno **a investigar** en este reinicio.

En el alert log también aparece un `ORA-07427: spstp: cannot change directory to dbs`, con `ORA-27300/27301 No such file or directory`, que al principio anoté como **a investigar**. En la Parte J lo aclaré: es del 2026-07-05 22:02:54, del job J002 durante la construcción de la imagen, cuando `$ORACLE_HOME/dbs` todavía no enlazaba al volumen. No es de mi entorno ni de este reinicio: queda como **conocido**.

## Parte F — Parámetros: SPFILE, SCOPE y PDB

### Lectura (evidencia 07-parametros-lectura)

La instancia arrancó con SPFILE (`/opt/oracle/product/26ai/dbhomeFree/dbs/spfileFREE.ora`, que es un enlace al volumen). Hay 564 parámetros documentados; 18 no están en su valor por defecto y 134 son estáticos. El SPFILE tiene 18 parámetros especificados, contando `control_files` dos veces (una línea por cada control file). Eso explica por qué el PFILE generado tiene solo 32 líneas: el SPFILE guarda lo que alguien fijó y el resto sale por defecto o derivado.

Ejemplos de derivados:
- `sessions = 322` (`ISDEFAULT = TRUE`) sale de `processes = 200`.
- `cpu_count = 2` lo calcula Oracle (`ISDEFAULT = TRUE`). En el entorno de pruebas aparecía fijado.

`db_block_size = 8192` y `compatible = 23.6.0` no se pueden cambiar. `db_create_file_dest` sale vacío en la raíz porque el OMF de la Parte C lo fijé solo en FREEPDB1: allí vale `/opt/oracle/oradata`.

### Cambios (evidencia 07-parametros-cambios)

- **MEMORY:** `open_cursors` pasó a 400 en memoria, con 300 en el SPFILE. Se perdería al reiniciar.
- **BOTH:** 500 en memoria y en el SPFILE, con `UPDATE_COMMENT = 'Lab4: prueba SCOPE=BOTH'`. Se deshizo a 300 sin comentario.
- **Estático:** `db_files` en memoria da `ORA-02095`. Con `SCOPE = SPFILE` queda 200 en memoria y 300 pendiente para el próximo arranque. `RESET` borró la línea y quedó "(no especificado)".
- **`processes`:** `v$parameter` dice `IMMEDIATE`, pero en memoria da `ORA-02097` + `ORA-02095`. En la práctica es estático: la metadata orienta, pero lo que decide es la prueba.
- **`memory_size`:** `ORA-62352`. Solo es dinámico si la instancia arrancó con él, y arrancó con 0.
- **PDB:** en FREEPDB1, `open_cursors = 350` solo afecta a esa PDB; la raíz seguía en 300. `processes` desde la PDB da `ORA-65040`. `RESET` devolvió la herencia del CDB.
- **Sesión:** `nls_date_format` cambió el formato solo para esa conexión (`2026-11-07 11:32:56`).

Al terminar comprobé que la instancia quedó como estaba: `open_cursors = 300` sin comentario, `db_files` sin especificar y `processes = 200`.

### PFILE versionado

`initFREE_lab4.ora` (32 líneas, desde el SPFILE) frente a `initFREE_lab4_memoria.ora` (122 líneas, desde la memoria). Doce parámetros tienen valor en memoria sin estar escritos en el SPFILE. Por ejemplo, `log_buffer`, `job_queue_processes` y `optimizer_mode`: son por defecto o derivados.

Hallazgo propio: ninguno de los dos PFILE contiene el `db_create_file_dest` de FREEPDB1. Los parámetros de una PDB no viven en el SPFILE del CDB, sino en el diccionario de la propia PDB. Un PFILE versionado no detecta la deriva de configuración de las PDB. En este repo ese cambio queda versionado en `scripts/lab4/03-omf.sql`.

### P6

**B.** Si la instancia arrancó con SPFILE, el SCOPE por defecto es BOTH: el cambio se aplica en memoria y en el SPFILE.

### P7

**C.** `processes` es un parámetro de instancia (`ISPDB_MODIFIABLE = FALSE`) y desde una PDB da `ORA-65040`. Lo vi en el bloque 5. No llega a evaluarse si es estático (D).

### P8

**A y C.** `STARTUP PFILE='/ruta/init_bueno.ora'` arranca con una copia buena, sin leer el SPFILE dañado. `CREATE SPFILE FROM PFILE='...'` repara el SPFILE para los siguientes arranques. B no sirve sin instancia arrancada. D es para abrir tras una recuperación incompleta. E no arregla nada.

### Reto: petición de cambio (change request)

**CR-LAB4-01 · Subir `open_cursors` a 1000 en FREEPDB1**
- **Motivo declarado:** la aplicación recibe `ORA-01000: maximum open cursors exceeded`.
- **Valor actual:** `open_cursors = 300`. Está escrito en el SPFILE (`*.open_cursors=300`, `ISDEFAULT = FALSE`) y FREEPDB1 lo hereda del CDB. El límite es **por sesión**, no global.
- **Análisis previo, antes de aprobar:** ORA-01000 casi siempre delata cursores que la aplicación abre y no cierra. Lo mediría con `SELECT s.sid, s.username, COUNT(*) FROM v$open_cursor o JOIN v$session s ON s.sid = o.sid GROUP BY s.sid, s.username ORDER BY 3 DESC;`, junto con `v$sesstat` ("opened cursors current"), mientras se reproduce el error. Si una sesión crece sin parar, es una fuga: el cambio solo retrasaría el fallo y se devuelve al equipo de desarrollo con la evidencia.
- **Valor propuesto (si la medida demuestra uso legítimo):** el pico medido más un margen, por ejemplo 500. No 1000 a ciegas, porque cada cursor abierto consume memoria de la sesión (PGA y shared pool).
- **Alcance:** solo FREEPDB1, que es donde está la aplicación. Ejecutaría `ALTER SESSION SET CONTAINER = FREEPDB1; ALTER SYSTEM SET open_cursors = 500 COMMENT = 'CR-LAB4-01' SCOPE = BOTH;`, con BOTH para que sobreviva al reinicio. El parámetro es dinámico (`IMMEDIATE`) y modificable por PDB, así que no hace falta parada. Antes probaría el valor con `SCOPE = MEMORY` en un entorno de pruebas.
- **Prueba:** repetir la carga que daba ORA-01000 y confirmar que no aparece, y que el máximo de "opened cursors current" queda por debajo del nuevo límite.
- **Rollback:** `ALTER SYSTEM RESET open_cursors SCOPE = BOTH;` en FREEPDB1, que vuelve a heredar los 300 del CDB, sin parada.
- **Evidencia:** spool con el valor antes y después (`v$parameter` y `v$spparameter` en la PDB), la consulta de cursores por sesión, el `UPDATE_COMMENT` con el número de CR y el commit en el repo con el script del cambio.

## Parte G — Memoria: SGA, Buffer Cache, análisis de sentencias y PGA

### G.1 Medir la memoria (evidencia 08-memoria)

`memory_size = 0`, `memory_target = 0` y `sga_target = sga_max_size = 1536M`: esta instancia usa **ASMM**. Oracle reparte la SGA entre los componentes y la PGA va aparte, con `pga_aggregate_target = 512M` y `pga_aggregate_limit = 2G`. `db_cache_size = 0` y `shared_pool_size = 0` no significan "sin caché", sino "sin mínimo fijado".

El reparto de ASMM en mi instancia es distinto al del entorno de pruebas: **shared pool 896 MB y buffer cache 512 MB** (allí era 416 y 864). `AJUSTES = 0` en `v$sga_dynamic_components` indica que ASMM no ha movido nada desde este arranque. El reparto viene de antes: ASMM guarda en el SPFILE los tamaños que va aprendiendo, y los reutiliza en el siguiente arranque. El PFILE de la Parte F tiene `FREE.__shared_pool_size=939524096` (896 MB) y `FREE.__db_cache_size=536870912` (512 MB). En arranques anteriores esta base necesitó más shared pool que caché de datos. `v$sga` suma 4,8 + 928 + 592 + 4,3 MB, las mismas cifras de "Total System Global Area" de la Parte E. El asesor da 17 457 lecturas físicas estimadas para cualquier tamaño entre 768 MB y 3072 MB: en una base sin carga real, más memoria no cambia nada y el asesor no sirve para decidir.

Los procesos con más PGA son MMON y los cuatro **ARC0-ARC3** (12,8 MB cada uno). Los archivadores existen porque mi base está en ARCHIVELOG (Parte A); en el entorno de pruebas no aparecen.

### G.2 Punto de control: la caché

| Ronda | Lecturas lógicas | Lecturas físicas | Tasa de acierto |
|---|---|---|---|
| 1, caché fría | 357 | 262 | 1 − 262/357 = 26,6 % |
| 2, caché caliente | 247 | 0 | 1 − 0/247 = **100 %** |

- **Las lógicas casi coinciden** porque toda lectura física termina en una lógica: el bloque se trae del disco a la caché y desde ahí se lee. En la ronda 2 son 247 lecturas lógicas para 244 bloques más la cabecera del segmento y un par de bloques de mapa de espacio.
- En mi ronda 1 hay 110 lecturas lógicas y 17 físicas **de más**. Son lecturas recursivas: tras el FLUSH, Oracle también tuvo que releer de disco bloques del diccionario y del mapa de espacio para analizar y planificar la primera consulta. En la ronda 2 ese trabajo ya estaba hecho.
- **245 bloques en caché para una tabla de 244** (`dba_tables.blocks`): el bloque 245 es la cabecera del segmento, que `BLOCKS` no cuenta pero un recorrido completo tiene que leer.

### G.3 Análisis duro frente a variables de enlace

| Medida | Literales | Variable de enlace |
|---|---|---|
| Análisis totales / duros | 1004 / 1000 | 1 / 1 |
| CPU de análisis | 860 ms | 0 ms |
| Tiempo total | 970 ms | 10 ms (97 veces menos) |
| Cursores en `V$SQL` | 1000 | 1 (1000 ejecuciones) |
| Memoria en la shared pool | 38 845 KB | 39 KB (unas 1000 veces menos) |

El 89 % del tiempo con literales fue analizar, no ejecutar. Los 4 análisis de más son recursivos (diccionario). Con la variable de enlace sale 1 análisis total, no 1000 blandos, porque PL/SQL mantiene abierto el cursor de `EXECUTE IMMEDIATE` entre iteraciones (session cursor cache).

A diferencia del entorno de pruebas (397 de 1000), siguen los **1000** cursores con literales. Mi shared pool es más del doble de grande (896 MB) y todavía no ha tenido que expulsar ninguno. Aun así ocupan 38 MB para hacer lo mismo que 39 KB.

### G.4 Punto de control: la PGA

- **PGA automática:** 2675 KB óptimos, 2377 KB usados, OPTIMAL, 0 KB en TEMP y 40 ms.
- **Manual con 64 KB:** usó 65 KB, escribió 2048 KB en TEMP y releyó **6 veces** (6 PASSES). Tardó 320 ms, **8 veces más**, con solo 60 000 filas.
- **Diferencia con el enunciado:** en mi instancia `maximum PGA allocated` (464,3 MB) **no** superó `aggregate PGA target parameter` (512 MB), y `over allocation count = 0`. No puedo demostrar con mis datos que el objetivo se supere sin error. Lo que sí se ve es que la PGA es un objetivo repartible: `aggregate PGA auto target` es 200 MB, menos de los 512 MB, porque la PGA fija de los procesos de background (MMON, ARCn) se descuenta antes.
- El experimento bajó la `cache hit percentage` de la PGA de la instancia de 100 % a 80,4 %: los 2 MB que fueron a TEMP cuentan como lectura y escritura extra.
- **Histograma:** 3395 óptimas, 0 de una pasada y **2 de varias pasadas**, ambas en el tramo de 1-2 MB. La instancia arrancó a las 11:29:44 (Parte E). Una se identifica en `v$sql_workarea` como `/* lab4_pga_64k */` (`sql_id 0tguvz0pvd96p`, 1 multi-pass). La otra cae en el mismo tramo de tamaño, pero su cursor ya no está en `v$sql_workarea`. Desde el reinicio no ha habido más carga que la de mis scripts, así que también es del laboratorio. En producción, cualquier multi-pass sería una alarma.

### P9

**B.** Con `MEMORY_TARGET = 0` y `SGA_TARGET = 2G` gestiona ASMM, y `DB_CACHE_SIZE = 512M` pasa a ser un **mínimo**: el buffer cache puede crecer, pero no bajar de 512 MB. A es falsa, porque no es un tamaño fijo. C es AMM, que exige `MEMORY_TARGET`. D es falsa, porque no se ignora.

### P10

**A y D.** El área de ordenación y la memoria de sesión (UGA) de un servidor dedicado viven en la PGA. Shared pool, log buffer y buffer cache son SGA.

### P-G1

**B.** Usar variables de enlace en la aplicación. A solo aplaza el problema (mis 38 MB para una sola consulta). C provoca más análisis duros. D es un parche que esconde el defecto y puede empeorar los planes.

### P-G2

**B.** El área de trabajo no cupo en la PGA y la ordenación se hizo en varias pasadas sobre TEMP. Es exactamente mi `lab4_pga_64k`: 6 PASSES y 2048 KB en TEMP.

### Reto: encontrar a los culpables

`scripts/lab4/08-reto-literales.sql`, ejecutado con `ro.sh` (como `C##OPS_RO`, de solo lectura, desde la raíz) justo después de `08-parse-y-pga.sql`. Agrupa `V$SQL` por `con_id` y `force_matching_signature`, la firma que coincide cuando dos textos solo se diferencian en los literales, y muestra las firmas con más de 50 `sql_id` distintos.

Encontró una sola firma: `1863221789280198928` en FREEPDB1, con 1000 sentencias, 1000 ejecuciones y 38 845 KB de shared pool. Es `SELECT /* lab4_literal */ COUNT(*) FROM admin_academia.aca_estudiantes WHERE est...`. Excluyo la firma 0, que corresponde a PL/SQL y sentencias sin literales. Uso `COUNT(DISTINCT sql_id)` para no contar cursores hijo de la misma sentencia.

## Parte H — Procesos de background y procesos servidor

### H.1 Desde Oracle (evidencia 09-procesos)

`v$process` cuenta **87 procesos background de Oracle en 54 procesos Linux**, y 7 servidores en 7 procesos Linux. Hay más procesos Oracle que procesos Linux porque algunos procesos Oracle son hilos dentro del mismo proceso Linux (por ejemplo, SCMN): por eso no cuadra uno a uno.

Los obligatorios están todos con su SPID: PMON 2616, LREG 2679, SMON 2670, DBW0 2662, LGWR 2664, CKPT 2667, MMON 2687, MMNL 2690 y RECO 2674.

El bloque 3 da **4 procesos ARCn** (ARC0 es el 2767). El enunciado espera 0 porque su base está en NOARCHIVELOG. La mía está en ARCHIVELOG (Parte A): los archivadores copian cada redo lleno a `$ORACLE_HOME/dbs/arch`.

Mi sesión es la SID 56 (`C##OPS_RO`, SQLcl desde `C00L3R-Caesar`, mi equipo) y la atiende el proceso servidor dedicado SPID 3620. Las otras sesiones "USER" sin usuario son J000-J002: esclavos del coordinador de jobs (CJQ0) que ejecutan tareas automáticas.

### H.2 Desde Linux (evidencia 09-procesos-so)

`09-procesos-so.sh 2664` devuelve `2664 104 db_lgwr_FREE`. **El SPID de LGWR en `v$process` coincide con el PID de `/proc` dentro del contenedor.** `docker top` muestra otro número para el mismo proceso: LGWR = 8824 y PMON = 8776, frente a 2664 y 2616 en Oracle y en `/proc`. Es el PID del anfitrión: el contenedor tiene su propio espacio de nombres de PID. El 5759 de PMON que salió en la Parte E era de la instancia anterior, la que se reinició en E.3.

En la pasada de `/proc` salen 60 procesos `db_*_FREE`, 1 listener y 0 `oracleFREE`, porque en ese instante no había ninguna sesión por red. El RSS de cada proceso, de 84 a 269 MB, no se suma: casi todo es la SGA compartida, contada de nuevo en cada proceso.

### P11

**C. LGWR.** El COMMIT espera a que LGWR escriba el redo en el redo log online (write-ahead logging). DBWn escribe los bloques de datos más tarde.

### P12

**B y D. PMON y SMON.** ARC0 solo existe en ARCHIVELOG: mi base lo tiene y la del enunciado no, así que no es obligatorio. CJQ0 solo existe si hay jobs. RECO, en la opción C, no está formulada como obligatoria.

### Reto: la sesión que más consume

Lancé, como SYSDBA en FREEPDB1, `SELECT COUNT(*) FROM admin_academia.aca_matriculas a, admin_academia.aca_matriculas b WHERE a.matricula_id < 10000;` (599 940 000 combinaciones, 18,22 s). Mientras corría ejecuté `scripts/lab4/09-reto-sesion.sql` como `C##OPS_RO`. El script une `v$session`, `v$process`, `v$containers` y `v$sql`, filtra las sesiones `USER` en estado `ACTIVE` y las ordena por PGA asignada.

| SID, serial# | Usuario / PDB | SPID (Linux) | PGA usada / asignada | Segundos en curso |
|---|---|---|---|---|
| 56, 45655 | SYS / FREEPDB1 | 3909 | 3,3 MB / 3,7 MB | 4 |

En el primer intento, con `matricula_id < 3000`, la consulta duró 5,95 s y no apareció. SQLcl tarda unos segundos en arrancar (Java), y cuando conectó la consulta ya había terminado. En un diagnóstico real hay que muestrear mientras el problema está ocurriendo.

La sesión de mi consulta **no** es la que más PGA tiene: J000 tiene asignados 20,8 MB. El producto cartesiano con COUNT(*) gasta CPU, no memoria de ordenación. Para "la sesión que más consume" hay que decidir antes qué recurso: la PGA no detecta una sesión que solo consume CPU. Lo complementaría con `v$sesstat` ("CPU used by this session") o `v$session.last_call_et`.

## Parte I — Navegar por los contenedores: qué ve cada usuario y por qué

### Quién ve qué (evidencia 10-que-ve-cada-usuario)

| Quién | Desde dónde | Qué vio | Por qué |
|---|---|---|---|
| SYS | CDB$ROOT | 16 datafiles: 4 + 3 + 9 (CON_ID 1, 2 y 3) | SYSDBA en la raíz: `V$` no se filtra |
| SYS | FREEPDB1 | 9 datafiles (CON_ID 3) y 10 tablespaces, igual en DBA_ que en CDB_ | Dentro de una PDB todo se filtra por el contenedor actual |
| `lab4_analista` (local, solo CREATE SESSION) | FREEPDB1 | 0 tablas propias y 0 accesibles. `ORA-00942` en `DBA_TABLES`, `V$SESSION` y `ACA_ESTUDIANTES`. `ORA-01031` al saltar a la raíz | Sin privilegios no ve ni el diccionario ni los datos de otros |
| `lab4_analista` con `READ ANY TABLE ON SCHEMA admin_academia` | FREEPDB1 | Las 3 tablas de Academia y 20 000 estudiantes. `ORA-00942` en `CLI_PACIENTES`. `ORA-41900` en el UPDATE | El privilegio de esquema abre un esquema completo y solo en lectura |
| `c##lab4_auditor` (común, sin CONTAINER_DATA) | CDB$ROOT | 5 tablespaces (solo CON_ID 1) y sesiones de CON_ID 0 (87) y 1 (4) | Lee el catálogo, pero desde la raíz solo ve la raíz |
| `c##lab4_auditor` | FREEPDB1 (SET CONTAINER) | 10 tablespaces | Desde dentro de la PDB, DBA_ muestra la PDB |
| `C##OPS_RO` | CDB$ROOT | CDB_TABLESPACES = 15 (5 + 10) | `CONTAINER_DATA = ALL` (`DEFAULT_ATTR = Y`, `ALL_CONTAINERS = Y`) |

`ADMIN_CLINICA.CLI_PACIENTES` **existe**: lo comprobé como SYSDBA. El `ORA-00942` del bloque 4a no significa "no existe": Oracle no revela objetos que no puedes ver. En cambio, cuando el objeto es visible pero falta la acción, `ORA-41900` dice exactamente qué falta (UPDATE).

Al final quedan 0 usuarios `%LAB4%`: la limpieza funcionó.

### Punto de control

- **CON_ID 0 en `V$LOG` (3 filas, una por grupo):** el redo es de toda la CDB, no de un contenedor. Hay una sola instancia y un solo hilo de redo, y todas las PDB escriben sus cambios en los mismos redo logs. Por eso no puede pertenecer a ninguna PDB.
- **`c##lab4_auditor` no ve sesiones de FREEPDB1:** lo cambiaría `ALTER USER c##lab4_auditor SET CONTAINER_DATA = ALL CONTAINER = CURRENT;`, ejecutado en la raíz. Es lo que tiene `C##OPS_RO` desde la Parte B.
- **Con `SELECT ANY TABLE`** habría leído `ADMIN_CLINICA.CLI_PACIENTES` y cualquier otra tabla de la PDB, incluidas las de todos los esquemas de negocio. El privilegio de esquema limita la lectura a `ADMIN_ACADEMIA` y deja cerrados los demás.

### Diccionario (evidencia 10-diccionario) y ciclo de vida de una PDB

- **Familias de vistas:** 656 USER_, 590 ALL_, 1309 DBA_ y 1307 CDB_, frente a 921 `V$` y 880 `GV$`. `v$fixed_table` tiene 1591 tablas X$ y 1803 vistas.
- **Mismo usuario, distinta familia:** DBA_TABLESPACES ve 5 (la raíz) y CDB_TABLESPACES ve 15 (5 de la raíz y 10 de FREEPDB1). PDB$SEED queda fuera porque las vistas CDB_ excluyen la semilla.
- **`GV$LOG`** se define sobre `x$kccle` y `x$kccrt`: "kcc" es la capa del control file. Por eso `V$LOG` responde ya en MOUNT.
- **Creación de usuarios:** mi imagen tiene `common_user_prefix = C##`. En la raíz, `CREATE USER lab4_local` da **ORA-65096**; en el entorno de pruebas el prefijo estaba vacío y el usuario se creaba como común. `C##` desde una PDB da **ORA-65094**. Un usuario local en la PDB se crea sin problema (`COMMON = NO`).
- **Ciclo de vida de `PDB_LAB4`:** se creó desde la semilla con `FILE_NAME_CONVERT` y quedó en MOUNTED. Se abrió con `OPEN` y quedó en READ WRITE, con sus 3 archivos en `/opt/oracle/oradata/FREE/PDB_LAB4/`. LREG registró el servicio `pdb_lab4`. Intentar `DROP` con la PDB abierta dio **ORA-65025**; tras `CLOSE IMMEDIATE`, `DROP ... INCLUDING DATAFILES` la borró y el script quitó la carpeta vacía. Quedan solo PDB$SEED y FREEPDB1.

### P13

**B.** Dentro de FREEPDB1, `V$DATAFILE` se filtra por el contenedor actual: solo sale CON_ID 3 (9 datafiles), como en mi bloque 2.

### P14

**B.** `ALTER USER c##audit SET CONTAINER_DATA = ALL CONTAINER = CURRENT;`. Es la diferencia entre `c##lab4_auditor` (5 tablespaces) y `C##OPS_RO` (15). `SET CONTAINER` (C) solo le deja entrar en la PDB, no verla desde la raíz.

### P15

**A y D.** El privilegio de esquema cubre las tablas presentes y futuras de HR (A) y ninguna de otro esquema (D), igual que `ADMIN_CLINICA` siguió cerrado en el bloque 4a. No es `ANY` sobre toda la PDB (B), no permite escribir (C, como mostró ORA-41900) y vale para usuarios locales (E): `lab4_analista` era local.

### Reto: diseño del acceso de una auditora externa (no ejecutado)

```sql
-- Contenedor: FREEPDB1, donde vive ADMIN_CLINICA. Usuario LOCAL: no necesita ver otros contenedores
ALTER SESSION SET CONTAINER = FREEPDB1;
CREATE USER aud_clinica IDENTIFIED BY "<contraseña entregada por canal seguro>"
  PASSWORD EXPIRE                -- la cambia en el primer inicio de sesión
  DEFAULT TABLESPACE users QUOTA 0 ON users;
GRANT CREATE SESSION TO aud_clinica;
GRANT READ ANY TABLE ON SCHEMA admin_clinica TO aud_clinica;

-- Último día de la auditoría:
REVOKE READ ANY TABLE ON SCHEMA admin_clinica FROM aud_clinica;
ALTER USER aud_clinica ACCOUNT LOCK;
-- y, cerrado el informe: DROP USER aud_clinica;
```

Por qué cada decisión, con lo observado en I.2:
- **Usuario local en FREEPDB1, no común.** Un usuario común existe en todos los contenedores, y ella solo necesita una PDB. `lab4_analista`, siendo local, no pudo saltar a la raíz (`ORA-01031`): es justo el aislamiento que busco.
- **`READ ANY TABLE ON SCHEMA admin_clinica`** y no `SELECT ANY TABLE`. En el bloque 4 este privilegio abrió un único esquema y dejó cerrado el resto. Además cubre las tablas que se creen durante la semana.
- **`READ` en lugar de `SELECT`.** `READ` no permite `SELECT ... FOR UPDATE`, así que no puede bloquear filas de la aplicación. Escribir queda negado: es el `ORA-41900` del bloque 4b.
- **Ningún rol de catálogo ni `CONTAINER_DATA`:** auditar los datos de clínica no exige ver el diccionario ni otras PDB.
- **El último día, `REVOKE` y `ACCOUNT LOCK`.** Así se corta el acceso y se conserva el usuario para la auditoría de sus sesiones hasta el `DROP` final. Para el examen: `ACCOUNT LOCK` deja la cuenta con contraseña, y no es lo mismo que `NO AUTHENTICATION` (Parte D).

## Parte J — Autopsia de los archivos de la base de datos

### Mínimo privilegio

`GRANT SELECT ON sys.v_$diag_alert_ext TO c##ops_ro CONTAINER = ALL;`. `dba_tab_privs` muestra un único privilegio de objeto, común (`COM = YES`). El GRANT va sobre la vista `V_$`, porque `V$DIAG_ALERT_EXT` es solo un sinónimo público. Gracias a él, el bloque 5 de `11-archivos.sql` lee el alert log por SQL como `C##OPS_RO`.

### Inventario (evidencias 11-archivos, 11-archivos-so y 11-dbs-y-archivados)

| Tipo | Archivos | MB | ¿Es la base? |
|---|---|---|---|
| datafile | 16 (4 raíz + 3 seed + 9 FREEPDB1) | 4329 | Sí |
| tempfile | 3 | 60 | Sí, pero no se copia |
| control file | 2 (los dos en `/opt/oracle/oradata/FREE/`) | 36 | Sí |
| redo online | 3 grupos × 1 miembro | 600 | Sí |
| redo archivado | 13 | 2017 | No (relacionado) |

Mi base tiene **3 grupos de redo de 200 MB**; la del enunciado tiene 2 de 20 MB. Linux da 209 715 712 bytes por redo = 200 × 1 048 576 + 512: el bloque de cabecera del redo es de 512 bytes. Los datafiles de negocio miden 104 865 792 bytes = 100 × 1 048 576 + 8192: el bloque 0, la cabecera del archivo, no cuenta como espacio útil.

**Hallazgos propios de mi imagen:**
- **El bloque 2 de `11-archivos-so.sh` sale vacío.** En mi imagen no son el SPFILE y el password file los que enlazan al volumen: es **toda la carpeta** `$ORACLE_HOME/dbs`, que apunta a `/opt/oracle/oradata/dbconfig/FREE/dbs`. `ls -l "$ORACLE_HOME/dbs"`, sin barra final, muestra solo el enlace. Con `ls -l $ORACLE_HOME/dbs/` aparece el contenido: SPFILE (3584 bytes), password file (2048 bytes) y algo que el enunciado no menciona.
- **Los 13 redo archivados están en esa carpeta** (`arch1_1_…` a `arch1_13_1237845575.dbf`, 2,1 GB). "Archive destination `$ORACLE_HOME/dbs/arch`" no es una carpeta: es el **prefijo** del nombre de cada archivo, el destino por defecto cuando no hay `log_archive_dest` ni FRA. El primero es del 2026-07-05, cuando se construyó la imagen. Del 2 al 13 son de mis sesiones del 9 de octubre al 7 de noviembre.
- **En la misma carpeta hay dos copias automáticas del control file** (`c-1509902213-20261009-00` y `c-1509902213-20261107-00`, con el DBID en el nombre) y `snapcf_FREE.f`. La copia de hoy (11:11 UTC) se generó al cambiar la estructura física en la Parte C. Esta base ya hace autobackup del control file por defecto, sin RMAN configurado.
- **El ADR no está en el volumen**: `/opt/oracle/diag` vive en la capa del contenedor. Lo he comprobado en mi propio entorno. El alert log actual empieza el **2026-07-05**, con las líneas que trae la imagen, y tiene **0 líneas de octubre**: todo el historial del contenedor anterior, del 9 de octubre al 7 de noviembre, se perdió al recrearlo en la Parte C. La prueba de persistencia no perdió datos, pero sí el diagnóstico. Va a la autopsia de la Parte N con riesgo medio.

### Punto de control

- **Password file como archivo "relacionado":** no guarda datos de la base ni su estructura. Guarda las credenciales de los usuarios con privilegios administrativos (SYS: SYSDBA y SYSOPER) para autenticarlos **por red**. Sin él, la base monta y abre igual, y `/ as sysdba` dentro del contenedor sigue funcionando por autenticación del sistema operativo. Lo que se pierde es el SYSDBA remoto.
- **Enlaces simbólicos:** en mi imagen el enlace es la carpeta `$ORACLE_HOME/dbs` entera, a `/opt/oracle/oradata/dbconfig/FREE/dbs`.
  - Ventaja: todo lo que Oracle escribe en `dbs` (SPFILE, password file, autobackups del control file y redo archivado) vive en el volumen y sobrevive a `docker rm`.
  - Inconveniente: la carpeta de configuración mezcla 3 KB de parámetros con 2 GB de redo archivado que nadie purga. Además, los datafiles creados con ruta relativa también acabaron ahí (Parte C).
- **TEMP no se respalda:** solo guarda datos de trabajo efímeros (ordenaciones, hash, tablas temporales) que no sobreviven a la sesión y no hacen falta para recuperar nada. Si falta un tempfile, se vuelve a crear vacío (`ALTER TABLESPACE temp ADD TEMPFILE`). Al abrir la base, Oracle lo recrea automáticamente.

### Reto: plan de copia a partir del inventario

Copia en frío completa de la base:

| Elemento | MB |
|---|---|
| Datafiles (16) | 4329 |
| Control files (2) | 36 |
| Redo online (3) | 600 |
| SPFILE + password file | ≈ 0,01 (3584 + 2048 bytes) |
| **Total** | **≈ 4965 MB (4,85 GB)** sin comprimir |

`backup-estado.sh` copió más: el volumen entero, 7079 MB. Incluye los 2 GB de redo archivado, los tempfiles y los autobackups. Comprimido, se queda en 958 MB, porque la mayor parte de los datafiles son bloques vacíos.

Con RMAN sobrarían:
1. **El redo online (600 MB):** RMAN nunca lo copia. En ARCHIVELOG, lo que se respalda es el redo archivado.
2. **El segundo control file (18 MB):** RMAN guarda una copia de seguridad del control file, no cada miembro multiplexado.
3. **Los tempfiles:** RMAN no los copia, igual que la copia en frío no debería.
4. **Los bloques nunca usados de los datafiles:** RMAN se salta los bloques sin formatear. De los 4329 MB solo copiaría lo ocupado.

RMAN incluye el SPFILE con el autobackup del control file. El **password file no lo copia**: hay que guardarlo aparte, junto a la configuración.

### P16

**B y D.** Los control files y los online redo logs forman la base, junto con los datafiles. El password file, el SPFILE y el alert log son archivos relacionados.

### P17

**C.** En NOARCHIVELOG, sin copias del redo en otro disco, solo se puede restaurar la última copia completa y se pierde todo lo posterior. `RECOVER` (A) necesitaría el redo archivado. `CREATE CONTROLFILE` (B) no devuelve los datafiles ni el redo perdidos. Sin FRA (D), no hay nada automático.

## Parte K — Anatomía de una página: del tablespace al byte

### Del tablespace a la fila (evidencia 12-bloque)

- **Tablespaces:** todos los permanentes de FREEPDB1 son BIGFILE, con gestión local de extensiones (AUTOALLOCATE), incluido USERS. Solo TEMP es SMALLFILE con UNIFORM. Los `TBS_*` usan ASSM (`SSM = AUTO`); SYSTEM y UNDOTBS1, MANUAL.
- **Segmento:** `ACA_ESTUDIANTES` tiene 17 extensiones y 256 bloques (2048 KB). Son 16 extensiones de 8 bloques (64 KB) y una de 128 bloques (1 MB): AUTOALLOCATE agranda la extensión a medida que crece el segmento.
- **Fila 101:** ROWID `AAAR2lAAAAAAAMOAAF`, `data_object_id` 73125, archivo 16 (`relative_fno` 1024, `academia01.dbf`), **bloque 782** (extensión 0, bloques 776-783) y **ranura 5**.
- **Diferencia con el entorno de pruebas:** el archivo es el 16 y no el 25, y el objeto es el 73125 y no el 73295. El bloque y la ranura coinciden porque V002 es determinista.

### Decodificar el ROWID

Base 64 de Oracle: A-Z = 0-25, a-z = 26-51, 0-9 = 52-61.

| Trozo | Caracteres | Cálculo | Valor | Lo confirma |
|---|---|---|---|---|
| OOOOOO | `AAAR2l` | R=17, 2=54, l=37 → 17·64² + 54·64 + 37 | 73 125 | `DATA_OBJECT_ID` y `DBA_OBJECTS` |
| FFF | `AAA` | 0 | 0 | En BIGFILE no hay archivo relativo |
| BBBBBB | `AAAAMO` | M=12, O=14 → 12·64 + 14 | 782 | `ROWID_BLOCK_NUMBER(…,'BIGFILE')` y `Block header dump: 0x30e` |
| RRR | `AAF` | F=5 | 5 | `ROWID_ROW_NUMBER` y `tab 0, row 5` |

### La fila por dentro

`DUMP()` y el volcado coinciden byte a byte:
- `ESTUDIANTE_ID`: `c2 02 02`. Es NUMBER en base 100: exponente `c2` y dígitos 02-1 = 1 y 02-1 = 1, es decir 1·100 + 1 = 101.
- `DNI`: `30 30 30 30 30 31 30 31 58` = `00000101X` en ASCII.
- `ESTADO`: `41 43 54 49 56 4f` = `ACTIVO`.
- La fila suma 68 bytes de datos (VSIZE). `tl: 78` = 3 de cabecera (`fb`, `lb`, `cc`) + 7 de longitud de columna + 68 de datos. Con la entrada de 2 bytes del directorio ocupa 80 bytes por fila. `AVG_ROW_LEN = 76` es una media de DBMS_STATS que no cuenta el directorio.
- **Ocupación:** 230 bloques llenos, 1 entre 25 y 50 % libre, 13 casi vacíos y 0 sin formatear. 230 + 1 + 13 = **244**, los bloques bajo la HWM, los mismos que `dba_tables.blocks` (Parte G).

### Punto de control

- **`avsp = fseo − fsbo`:** 0x427 − 0xc6 = **0x361**. En decimal, 1063 − 198 = **865** bytes. Coincide con `avsp = tosp = 0x361`: no hay huecos entre filas.
- **Fecha de registro:** los 7 primeros bytes de la columna 6 son `78 7e 0b 07 0c 1a 29`. Se leen así: siglo 0x78 − 100 = 20, año 0x7e − 100 = 26, mes 0x0b = 11, día 0x07 = 7, hora 0x0c − 1 = 11, minuto 0x1a − 1 = 25 y segundo 0x29 − 1 = 40. Resultado: **2026-11-07 11:25:40**. Es exactamente cuando apliqué V002 (spool `20261107T112539Z`). Los 4 bytes restantes son las fracciones de segundo del TIMESTAMP.
- **Si un UPDATE modifica la fila 101:** la ranura 0x01 está ocupada por la transacción de V002 (`Xid 0x0002.000.00000425`, flag `--U-`, confirmada), así que la nueva transacción tomaría la ranura libre **0x02**. Al hacerlo, Oracle comprueba en el undo que la transacción de la ranura 0x01 terminó y la limpia: pone su SCN de confirmación, `Lck` pasa de 90 a 0 y la fila 101 queda con `lb: 0x2`. Es la limpieza diferida de bloques (delayed block cleanout), y genera redo aunque solo se cambie una fila.

### Reto: abrir otro bloque (estudiante 19500)

Hice una copia, `scripts/lab4/12-bloque-reto.sql`, igual que 12-bloque.sql pero con el estudiante 19500 y con `tracefile_identifier` `lab4_bloque_reto`. El volcado completo está en `config/…_12-volcado-bloque-reto.trc.txt`.

| | Bloque 782 (estudiante 101) | Bloque 1162 (estudiante 19500) |
|---|---|---|
| ROWID | `AAAR2lAAAAAAAMOAAF` | `AAAR2lAAAAAAASKABN`: S=18, K=10 → 18·64 + 10 = 1162; B=1, N=13 → 64 + 13 = 77 |
| `nrow` | 90 | **85** |
| `tl` de la fila | 78 | **84** (ID de 5 cifras: NUMBER `c3 02 60` en 3 bytes; DNI, nombre y email más largos; `EGRESADO` 8 bytes frente a `ACTIVO` 6) |
| `avsp` | 0x361 = 865 | 0x33a = **826** |
| `hsiz` | 0xc6 = 198 | 0xbc = 188 (5 entradas menos de 2 bytes en el directorio) |
| ITL 0x01 | `Xid 0x0002.000.00000425`, `--U-`, Lck 90 | **La misma transacción**, `--U-`, **Lck 85** |

Caben menos filas porque son más largas. Con 826 bytes libres, una fila más (84 + 2 = 86 bytes) dejaría 740, por debajo del 10 % de PCTFREE (809 bytes): Oracle pasó al bloque siguiente. **Sí, también se ve la limpieza diferida**: es la misma transacción de V002 (mismo Xid y mismo SCN `0x00495c9d`), confirmada, con las 85 filas aún marcadas. Un COMMIT de 20 000 filas no tocó ninguno de los 244 bloques.

### P18

**B.** Sin segundo argumento, `ROWID_BLOCK_NUMBER` supone SMALLFILE y reparte los bits entre archivo relativo y bloque. En BIGFILE todos esos bits son del bloque. Por eso el script usa `'BIGFILE'` y yo obtengo 782, igual que en el volcado.

### P19

**A y B.** Con PCTFREE 10, un bloque deja de recibir INSERT cuando su espacio libre bajaría del 10 %: es lo que paró en 90 filas mi bloque 782. Ese 10 % se reserva para que las filas existentes crezcan con UPDATE. No es solo para la ITL (C), también afecta a las tablas (D) y no impide la migración si el UPDATE crece más del 10 % (E), como veré en la Parte M.

## Parte L — Capacidad y coste: factor de bloqueo, páginas y tiempo de una consulta

### Predicción frente a realidad: ACA_ESTUDIANTES (evidencia 13-capacidad)

| Cálculo | bfr | Bloques | Qué tiene en cuenta |
|---|---|---|---|
| Unidad 3 (H = 96, R = 76) | 95 | 211 | Cabecera genérica, PCTFREE y AVG_ROW_LEN |
| Versión Oracle (H = 122, R + 2) | 93 | 216 | Además, la ITL y la entrada de directorio de cada fila |
| Medido (filas reales por bloque) | 86,6 (de 68 a 95) | 231 con filas | Las filas miden 78-84 bytes en el bloque (Parte K: 78 la del 101, 84 la del 19500) |
| Estadísticas (bajo la HWM) | — | 244 | Además, 13 bloques casi vacíos al final del segmento |
| Asignado al segmento | — | 256 | Además, el resto de la última extensión de 1 MB |

La fórmula acierta el orden de magnitud: centenares de bloques, no miles. Se queda corta porque `AVG_ROW_LEN` no cuenta los 2 bytes del directorio y las filas con ID de 5 cifras son más largas que la media.

### El coste de una lectura (bloque 5 de 13-capacidad)

| Medida | Mi valor | Entorno de pruebas |
|---|---|---|
| Lectura lógica (5a) | 3,18 µs (4 por búsqueda: raíz, rama, hoja y tabla) | 1,9 µs |
| Lectura física aleatoria (5b) | 11,6 µs | 8,9 µs |
| Lectura secuencial (5c) | 44 ms para 4595 bloques = 9,6 µs por bloque, en 53 peticiones (~87 bloques por petición), Bw = 814 MB/s | 31 ms, 1152 MB/s |
| `c_sec / c_aleat` | 0,827 | 0,762 |
| Umbral del índice | (1/86) × 0,827 = **0,96 %** de las filas | 0,89 % |

Mi equipo es algo más lento en CPU: la lectura lógica cuesta más. El resultado del método es el mismo: una lectura física "aleatoria" cuesta casi lo mismo que una secuencial, porque `FLUSH BUFFER_CACHE` vacía la caché de Oracle pero no la caché de páginas de Linux. Las "lecturas físicas" del experimento salieron de la RAM.

**Hallazgo propio en el bloque 6:** las medias de toda la instancia desde el arranque son **674 µs** (`db file sequential read`) y **428 µs** (`db file scattered read`), frente a 11 y 33 µs en el entorno de pruebas. Es unas 60 veces la latencia de mi experimento. La instancia arrancó a las 11:29 (Parte E) con la caché de Linux fría para muchos bloques, y esas primeras lecturas fueron de verdad al disco: el `ext4.vhdx` de WSL en E:, a través de Docker Desktop. **Mis 674 µs son la latencia real de este almacenamiento**; los 11,6 µs del experimento son la de la caché del sistema operativo. Con 674 µs, el cociente sería 9,6 / 674 ≈ 0,014 y el umbral ≈ 0,016 % de las filas, mucho más cerca del caso HDD del enunciado (0,012 %). Para decidir un índice en esta máquina usaría la cifra de `v$system_event`, no la del experimento.

### L.4 con mis cifras

Consulta del 2 % de LECTURAS (k = 8000) con un índice cuyas filas están desordenadas respecto a la tabla:
- **Recorrido completo:** 4676 bloques secuenciales ≈ 44 ms en el contenedor.
- **Por índice:** 8000 × 11,6 µs ≈ 93 ms con la caché de Linux caliente, y 8000 × 674 µs ≈ **5,4 s** con mi disco real.

El recorrido completo gana en todos los casos: el 2 % está muy por encima de cualquier umbral (0,96 % o 0,016 %).

### Reto: dimensionar ACA_MATRICULAS (evidencias 13-reto-matriculas)

**Predicción, antes de mirar las estadísticas.** Uso solo la estructura (`MATRICULA_ID`, `ESTUDIANTE_ID` y `ASIGNATURA_ID` NUMBER, `PERIODO` VARCHAR2(10) y `FECHA_MATRICULA` TIMESTAMP) y lo que sé de V002 (IDs hasta 60 000 y 20 000, 40 asignaturas, `'2026-1'`):
- Datos: unos 3 + 3 + 2 + 6 + 11 = 25 bytes, más 5 de longitud de columna, R ≈ 30.
- bfr = floor(8096 · 0,9 / 30) = **242** y b = ceil(60 000 / 242) = **248 bloques**.
- Si usara el tamaño declarado (22 + 22 + 22 + 10 + 11 = 87 bytes), saldrían 84 filas por bloque y 715 bloques: el error típico de sobrestimar R.

**Realidad:**
- `AVG_ROW_LEN = 30`: la predicción acertó R. Con ese valor, la fórmula da también 242 y 248.
- `BLOCKS` (bajo la HWM) = **370**; asignados, 384.
- Medido como SYSDBA: **301 bloques con filas** y **199,3 filas por bloque** (de 159 a 213). Los datos ocupan 26,3 bytes de media (VSIZE).

**Por qué la diferencia es mayor que en ACA_ESTUDIANTES:**
1. **Filas cortas, sobrecarga fija.** Cada fila lleva siempre 3 bytes de cabecera, 1 de longitud por columna (5) y 2 de directorio. Son unos 10 bytes sobre 26 de datos, el 38 %; en ACA_ESTUDIANTES eran unos 12 sobre 68, el 18 %. En el bloque cada fila ocupa unos 36 bytes: floor(8070 · 0,9 / 36,3) ≈ 200 filas por bloque, justo lo medido. La fórmula con R = 30 no ve esa sobrecarga y se equivoca más cuanto más corta es la fila.
2. **62 bloques sin formatear bajo la HWM.** `DBMS_SPACE`: 300 llenos, 1 entre 25 y 50 %, 7 casi vacíos y 62 sin formatear = 370. En ASSM hay una HWM baja y una alta: Oracle reserva y formatea los bloques por tramos. Los 62 están por encima de la HWM baja y todavía sin usar, pero cuentan en `BLOCKS`. En ACA_ESTUDIANTES ese número era 0.

**Recorrido completo en un HDD a 150 MB/s:** 370 bloques × 8 KB = 2,9 MB → 2,9 / 150 ≈ **20 ms** de transferencia, más un posicionamiento inicial de unos 5 ms. Unos 25 ms: leer la tabla entera es trivial. Con mi almacenamiento real (Bw de 814 MB/s, aunque con 674 µs de latencia por petición), serían unas 7 peticiones de unos 50 bloques, alrededor de 5-10 ms.

### P20

**B. 50 000.** bfr = floor((8192 − 96) · 0,9 / 180) = floor(40,48) = 40 filas por bloque, y b = ceil(2 000 000 / 40) = 50 000 bloques. 44 445 (A) sale de ignorar la cabecera y PCTFREE: floor(8192 / 180) = 45 filas por bloque y 2 000 000 / 45. Las otras opciones tampoco aplican bien el redondeo (floor para el bfr y ceil para b).

### P21

**B.** `db file scattered read` son lecturas multibloque a la buffer cache: es el recorrido completo, el 5c de mi experimento, con ~87 bloques por petición. Las de un solo bloque son `sequential read` (A), y las directas a la PGA, `direct path read` (C).

## Parte M — Filas migradas y encadenadas: provocarlas, detectarlas y curarlas

### Cuatro pruebas del mismo problema (evidencia 14-filas-migradas)

1. **`CHAIN_CNT`:** `MIGRA` empezó con 5000 filas de 9 bytes en 13 bloques, con PCTFREE 0. Una de cada cinco filas (`MOD(id, 5) = 0`) creció de 1 a 300 bytes. Después, `ANALYZE` da **`CHAIN_CNT = 1000`, el 20 %**, y la tabla pasa a 58 bloques. Son justo las 1000 filas que crecieron: con PCTFREE 0 no había hueco en su bloque y se mudaron. `CHAIN_CNT` no distingue migradas de encadenadas: hay que razonarlo, y aquí ninguna fila llega a 8 KB.
2. **`LIST CHAINED ROWS`:** `CHAINED_ROWS` recibe las 1000. La primera, por ROWID de cabeza, es el ID **2935**: `AAASSvAAAAAABYLAAC`, archivo 25 (el de `TBS_LAB4`), bloque 5643, ranura 2.
3. **Coste:** en 1000 búsquedas por clave, `table fetch continued row` = **200** y 3200 lecturas lógicas, 3,2 por búsqueda. Lo normal son 3 (índice de dos niveles y bloque de tabla). De los IDs 1 a 1000, 200 son múltiplos de 5 y cuestan 4: (800 · 3 + 200 · 4) / 1000 = 3,2. Es un **7 % más de trabajo en cada acceso, para siempre**.
4. **En el bloque:** `tab 0, row 2: tl: 9 fb: --H----- lb: 0x2 cc: 0` y `nrid: 0x00001624.25a`. En el bloque original solo queda la **cabeza** (H, sin F ni L), 0 columnas y la dirección nueva. En BIGFILE, la parte anterior al punto es el bloque: 0x1624 = **5668**. Tras el punto va la ranura. Lo más importante: **el ROWID y el índice siguen apuntando a la cabeza**, por eso hace falta un salto más.

**Encadenamiento:** `ANCHA` tiene 2 filas en 5 bloques, `AVG_ROW_LEN = 6016` y `CHAIN_CNT = 1`. Solo la fila de unos 12 000 bytes (3 × 4000) está encadenada, porque no cabe en ningún bloque de 8 KB. La fila "corta" no. Reorganizar no lo arregla.

**Cura de la migración:** `ALTER TABLE ... MOVE PCTFREE 20` dejó `PK_MIGRA` **UNUSABLE**: las filas tienen ROWID nuevo y el índice apuntaba a los viejos. `ALTER INDEX ... REBUILD` lo devolvió a **VALID**. Después, `CHAIN_CNT = 0` y **63 bloques**, más que los 58 de antes, porque ahora cada bloque deja un 20 % libre para crecer.

**Limpieza:** `LAB4_PRUEBAS` y `TBS_LAB4` borrados (`tbs_lab4_restantes = 0`). Es lo que exige la verificación final.

### Migración frente a encadenamiento, con mis datos

| | Migración (`MIGRA`) | Encadenamiento (`ANCHA`) |
|---|---|---|
| Causa | UPDATE de 1 a 300 bytes en bloques con PCTFREE 0 | Fila de unos 12 000 bytes en bloques de 8 KB |
| En el bloque original | La cabeza con `nrid` (`fb: --H-----`) | La primera pieza, enlazada con las siguientes |
| Detección | `CHAIN_CNT` 1000, `LIST CHAINED ROWS` y `table fetch continued row` 200 | `CHAIN_CNT` 1 |
| Cura | `MOVE` (en producción `MOVE ONLINE`) con PCTFREE adecuado y `REBUILD` | Ninguna con MOVE: bloque mayor (16/32 KB) o rediseño (LOB o tabla aparte) |

### P22

**A y C.** `ANALYZE ... LIST CHAINED ROWS` identifica las filas afectadas (mis 1000). `MOVE ONLINE` con un PCTFREE mayor reescribe las filas en su sitio, dando hueco para crecer, y mantiene los índices válidos. `DBMS_STATS` (B) no rellena `CHAIN_CNT`. FLUSH (D) y `DB_FILE_MULTIBLOCK_READ_COUNT` (E) no tocan la causa.

### P23

**B.** Una fila de 12 000 bytes no cabe en un bloque de 8 KB: está **encadenada**, como mi fila 1 de `ANCHA`, y MOVE no lo arregla. Oracle la guarda sin error (C) y no la comprime (D).

## Parte N — Autopsia de la instancia y verificación final

El informe propio está en `docs/bitacora/lab4-autopsia.md`: 9 hallazgos con sección, evidencia, riesgo, acción y prioridad, y un resumen para dirección.

`16-verificacion-final.sh` da **TODO OK**: 0 fallos, todas las evidencias de la 00 a la 15, `config/.env` y `backups/` fuera de Git.

### P24

**B.** Un usuario común de solo lectura con `SELECT_CATALOG_ROLE`, `CONTAINER_DATA = ALL` y el GRANT puntual de `V_$DIAG_ALERT_EXT`: es `C##OPS_RO`, y con él ejecuté la autopsia. SYS desde cron (A) o el rol DBA (C) dan mucho más de lo necesario. SYSTEM con su contraseña en una variable de entorno (D) es además una credencial potente expuesta.

---

## 8. Preguntas de comprobación

### Respaldo y diagnóstico (A)

**1.** Es consistente porque `backup-estado.sh` hace `SHUTDOWN IMMEDIATE` y `docker stop` antes del `tar`: todos los datafiles comparten el SCN del checkpoint final y se abriría sin aplicar redo. La evidencia 00 muestra "Database closed / dismounted / instance shut down" antes del paso 5. Tomada con la base abierta, cada archivo quedaría copiado en un instante distinto y la copia sería inconsistente. Solo serviría en ARCHIVELOG, con RMAN y el redo de después.

**2.** `manifiesto.txt` dice qué es la copia: `etiqueta=lab3-final`, `fecha_utc=20261107T104005Z`, imagen, `git_commit=e8bf302`, tipo y `archivos_fuera_del_volumen=0`. `SHA256SUMS` es la huella de cada archivo. `restaurar-estado.sh` hace primero `sha256sum --check`: si un byte está mal, se detiene sin tocar nada. Después pide escribir el nombre del volumen antes de borrarlo. En la Parte A comprobé las 4 sumas: OK.

**3.** **RPO**, lo que puedo perder: todo lo hecho después del 2026-11-07 10:40:05 UTC, la hora de la copia. Si restaurara hoy, se perderían las Partes C a N: reubicación, OMF, V002 y V003, C##OPS_RO… **RTO**, lo que tardo en volver a dar servicio: no lo he medido restaurando, porque la Parte A solo verifica la copia. Mi referencia es la propia copia (3 min 49 s con la base parada, de ellos 10 s de vuelta a READ WRITE) y la recreación del contenedor de la Parte C (1 min 31 s, con 40 s hasta healthy). Estimo un RTO de unos 3-4 minutos; lo mediré de verdad en el Lab 5.

### Correcciones del Lab 3 (C, D)

**4.** En `$ORACLE_HOME/dbs`, porque V000 usó rutas relativas (`DATAFILE 'academia01.dbf'`) y sin OMF Oracle las resuelve contra esa carpeta. En mi imagen, `dbs` enlaza a `/opt/oracle/oradata/dbconfig/FREE/dbs` (evidencia 01: "DENTRO del volumen, pero en carpeta no estándar"). Lo habría evitado `DB_CREATE_FILE_DEST` (OMF), que activé en FREEPDB1 con `03-omf.sql`, o simplemente una ruta absoluta.

**5.** Porque `RENAME DATAFILE` solo cambia la ruta que guarda el control file; no mueve ni copia el archivo. Por eso `03-reubicar-datafiles.sh` hace `cp -p` antes del `RENAME` y Oracle valida la cabecera en `ONLINE`. Sin la copia, el ONLINE fallaría.

**6.** V000 ya está aplicada y en el historial: editarla no cambia la base, y otro entorno que ya la ejecutó quedaría distinto. Los cambios se hacen con una migración nueva. Borrar las contraseñas del archivo no sirve, porque siguen en `git log`. Invalidarlas sí protege: la evidencia 04 muestra que la contraseña de V000 **abría sesión antes de V003** y da **ORA-01017 después**.

**7.** Demuestra que todo el estado está en el volumen: borré el contenedor, lo recreé con `05` v2 y salieron los mismos 5 tablespaces y las mismas tablas 3/3/2/3/3 (evidencia 03). Se ejecuta después de reubicar porque, en una imagen sin el enlace de `dbs`, los datafiles en `$ORACLE_HOME/dbs` estarían en la capa del contenedor y `docker rm` los borraría.

### Instancia, arranque y parámetros (E, F)

**8.** De la **instancia**: `HOST_NAME = 1798f1f0fffc` (cambió al recrear el contenedor; antes `ef2b142804c6`), `STARTUP_TIME`, 57 procesos `db_*_FREE` y una SGA de 1 603 398 928 bytes. De la **base**: `DBID = 1509902213` (no cambió), `CREATED = 2026-07-05` y los 16 datafiles, 3 redo y 2 control files (evidencia 05).

**9.** NOMOUNT lee el SPFILE (por eso `v$parameter` responde) y arranca SGA y procesos. MOUNT lee los control files: `v$database`, `v$controlfile` y `v$datafile` (16). OPEN abre datafiles y redo. `ORA-01507` en NOMOUNT: `v$database` necesita el control file. `ORA-01219` en MOUNT: `dba_tables` es diccionario, guardado en el datafile de SYSTEM, todavía cerrado (evidencia 06).

**10.** `v$parameter` es el valor en memoria y `v$spparameter`, lo escrito en el SPFILE. Con `db_files` (evidencia 07): `SCOPE = SPFILE` dejó 200 en memoria y 300 en el SPFILE, pendiente del siguiente arranque. Tras `RESET`, el SPFILE quedó "(no especificado)" y la memoria siguió en 200.

**11.** Porque `PROCESSES` dimensiona estructuras de la SGA que se reservan al arrancar. Aunque `ISSYS_MODIFIABLE` diga IMMEDIATE, el cambio en memoria da `ORA-02097` + `ORA-02095` (bloque 4 de la evidencia 07). En la práctica es estático: se cambia con `SCOPE = SPFILE` y reinicio.

### Memoria y procesos (G, H)

**12.** **ASMM**: `memory_target = 0` y `memory_size = 0` (sin AMM), `sga_target = 1536M` (Oracle reparte la SGA) y `pga_aggregate_target = 512M` (la PGA va aparte). `db_cache_size = 0` y `shared_pool_size = 0` indican que no hay mínimos fijados (evidencia 08-memoria).

**13.** Ronda 1, en frío: 357 lógicas y 262 físicas, un 26,6 % de acierto. Ronda 2, en caliente: 247 lógicas y 0 físicas, **100 %**. Las lógicas se parecen porque toda física termina en una lógica. En la ronda 1 sobran 110 lógicas y 17 físicas recursivas, del diccionario y del mapa de espacio, tras el FLUSH. En la caché quedan 245 bloques: 244 de datos más la cabecera del segmento.

**14.** Con literales: 1000 análisis duros, 860 ms de CPU de análisis, 970 ms en total, 1000 cursores y 38 845 KB de shared pool. Con `:id`: 1 análisis, 0 ms, 10 ms, 1 cursor y 39 KB. Son 97 veces menos tiempo y unas 1000 veces menos memoria (evidencia 08-parse-y-pga).

**15.** `v$process.spid` de LGWR = **2664** = PID 2664 en `/proc` dentro del contenedor (`09-procesos-so.sh 2664`). `docker top` muestra **8824**, porque enseña el PID del anfitrión: el contenedor tiene su propio espacio de nombres de PID.

### Contenedores (I)

**16.** Desde la raíz, SYS ve `V$DATAFILE` sin filtrar: 4 (CDB$ROOT) + 3 (PDB$SEED) + 9 (FREEPDB1) = 16. Dentro de FREEPDB1, todas las vistas se filtran por el contenedor actual y solo salen sus 9 (evidencia 10, bloques 1 y 2).

**17.** Porque Oracle no revela la existencia de objetos que no puedes ver: responde lo mismo que si no existieran. `DBA_TABLES` existe, igual que `ADMIN_CLINICA.CLI_PACIENTES`, que comprobé como SYSDBA, y aun así salió `ORA-00942`. Cuando el objeto sí es visible y falta la acción, 23ai lo dice: `ORA-41900: missing UPDATE privilege`.

**18.** Los dos son comunes y tienen `SELECT_CATALOG_ROLE`, pero solo `C##OPS_RO` tiene `CONTAINER_DATA = ALL`. Desde la raíz, `c##lab4_auditor` vio 5 tablespaces (solo CON_ID 1) y `C##OPS_RO` ve 15. Los igualaría `ALTER USER c##lab4_auditor SET CONTAINER_DATA = ALL CONTAINER = CURRENT;`.

**19.** **Ventaja:** un solo GRANT cubre todas las tablas del esquema, también las futuras, sin mantener una lista y sin abrir otros esquemas (bloque 4). **Riesgo:** como cubre las futuras, cualquier tabla nueva, aunque sea sensible, queda legible al instante, sin que nadie lo decida.

**20.** `C##`. En el bloque 3a, `CREATE USER lab4_local` en la raíz dio `ORA-65096` y no se creó nada. En el entorno de pruebas el prefijo estaba vacío y el usuario se creaba como común.

### Archivos (J)

**21.** **Son la base:** 16 datafiles, 3 tempfiles, 2 control files y 3 redo online. **Relacionados:** SPFILE, password file, 13 redo archivados, autobackups del control file (`c-1509902213-*`) y ADR (alert log y trazas). El password file es **relacionado**: no guarda datos ni estructura, solo las credenciales para el SYSDBA por red. La base abre sin él.

**22.** 104 865 792 = 100 × 1 048 576 + 8192: Linux cuenta también el bloque 0, la cabecera del archivo, que `v$datafile` no cuenta como espacio útil (evidencia 11-archivos-so).

**23.** (1) Los 2 control files están en la misma carpeta del mismo volumen, `/opt/oracle/oradata/FREE/`. (2) Cada uno de los 3 grupos de redo tiene un único miembro. Un fallo de ese disco se lleva todo.

**24.** Porque el alert log y las trazas son la historia del sistema. Al recrear el contenedor en la Parte C se perdió todo lo del 9 de octubre al 7 de noviembre: mi alert log empieza en julio, con la imagen, y tiene 0 líneas de octubre (evidencia 11-dbs-y-archivados). No se pierde ningún dato, pero se pierde el diagnóstico de cualquier incidente previo.

### Bloque y fila (K)

**25.** `AAAR2lAAAAAAAMOAAF`:
- `AAAR2l` = 17·64² + 54·64 + 37 = **73 125**, igual que `ROWID_OBJECT` y `DBA_OBJECTS`.
- `AAA` = 0, porque en BIGFILE no hay archivo relativo. El archivo real es el 16, según `ROWID_TO_ABSOLUTE_FNO`.
- `AAAAMO` = 12·64 + 14 = **782**, igual que `ROWID_BLOCK_NUMBER(…, 'BIGFILE')`.
- `AAF` = **5**, igual que `ROWID_ROW_NUMBER`.

**26.** `nrow` es el número de filas del bloque (90). `fsbo` (free space begin offset) es dónde empieza el hueco libre: tras la cabecera y el directorio, 0xc6 = 198. `fseo` (free space end offset) es dónde acaba: donde empiezan las filas, 0x427 = 1063. `avsp` es el espacio disponible. 0x427 − 0xc6 = **0x361 = 865** = `avsp`.

**27.** `0x01 Xid 0x0002.000.00000425 … --U- 90`: la ranura 1 de la ITL guarda la transacción que insertó las 90 filas (V002). Está confirmada (U, upper bound commit), pero las 90 filas siguen marcadas (`Lck 90`; la fila 101 tiene `lb: 0x1`). Es la **limpieza diferida**: el COMMIT no recorre los bloques modificados, para ser instantáneo. La siguiente sesión que toque el bloque comprueba en el undo que la transacción terminó y lo limpia. El bloque 1162 del reto muestra lo mismo, con Lck 85.

**28.** 3 bytes de cabecera de fila (`fb`, `lb`, `cc`) + 7 de longitud de columna (una por columna) + 68 de datos (3 + 9 + 9 + 11 + 19 + 6 + 11) = **78** = `tl`.

### Capacidad y coste (L)

**29.** bfr = floor((8192 − 96) · 0,9 / 76) = **95** y b = ceil(20 000 / 95) = **211**. La tabla real tiene 244 bloques bajo la HWM por tres motivos:
- las filas ocupan 78-84 bytes en el bloque, más 2 de directorio: el bfr medido es 86,6;
- hay ITL y cabecera mayores que 96 bytes;
- 13 bloques casi vacíos al final (`DBMS_SPACE`: 230 llenos + 1 + 13 = 244).

**30.** Lógica: **3,18 µs** (5a). Física aleatoria: **11,6 µs** (5b). Bloque secuencial: 44,1 ms / 4595 = **9,6 µs** (5c, ~87 bloques por petición, 814 MB/s).

**31.** c_sec = 8192 / (150 · 1 048 576) s ≈ **52 µs** por bloque. lat = 5 ms = 5000 µs. Cociente = 52 / 5000 ≈ **0,0104**. Umbral = 0,0104 / 86 ≈ 0,000121 = **0,012 %** de las filas.

**32.** Porque `FLUSH BUFFER_CACHE` vacía la caché de Oracle, pero no la caché de páginas de Linux: los bloques salen de la RAM del sistema operativo. No invalida el método: el método es medir, y en almacenamiento real se aplica igual. De hecho, mi `v$system_event` desde el arranque da 674 µs por `db file sequential read`, la latencia real de mi disco virtual, y con ella el umbral baja a ≈ 0,016 %.

### Filas migradas y encadenadas (M)

**33.** **Migración:** un UPDATE agranda una fila que ya no cabe en su bloque y se muda. Deja la cabeza con `nrid` (`fb: --H-----`). Se detecta con `CHAIN_CNT` (1000), `LIST CHAINED ROWS` y `table fetch continued row` (200). Se cura con `MOVE` (en producción `MOVE ONLINE`) y un PCTFREE adecuado. **Encadenamiento:** la fila mide más que un bloque (12 000 bytes > 8 KB) y se reparte en piezas. Se detecta igual (`CHAIN_CNT` 1 en `ANCHA`), pero MOVE no lo cura: hace falta un bloque mayor o un rediseño.

**34.** De los IDs 1 a 1000, 800 cuestan 3 lecturas (raíz e hoja del índice, más el bloque de tabla) y los 200 múltiplos de 5, migrados, cuestan 4, por el salto al `nrid`. (800 · 3 + 200 · 4) / 1000 = **3,2**, y `table fetch continued row` = 200.

**35.** Porque MOVE reescribe las filas en bloques nuevos y les da un ROWID nuevo, mientras el índice sigue guardando los viejos: Oracle lo marca UNUSABLE (`PK_MIGRA UNUSABLE` en la evidencia 14). En producción usaría `ALTER TABLE ... MOVE ONLINE`, que mantiene los índices válidos y no bloquea el DML, y recogería estadísticas después. O bien MOVE + `ALTER INDEX ... REBUILD` en una ventana de mantenimiento.

### Autopsia y trabajo profesional (N, O)

**36.** De `lab4-autopsia.md`:
1. **ARCHIVELOG sin FRA, con 2 GB de archivados sin purgar** en `$ORACLE_HOME/dbs`. Riesgo: llenar el disco y que la base se pare. Acción: FRA con tamaño, RMAN y retención. Prioridad alta.
2. **Control files y redo sin multiplexar en el mismo volumen.** Riesgo: punto único de fallo. Acción: multiplexar. Prioridad alta.
3. **ADR fuera del volumen.** Riesgo: se pierde el historial del alert log al recrear el contenedor (ya pasó). Acción: `diagnostic_dest` persistente o logs centralizados. Prioridad media.

**37.** Porque SYSTEM tiene el rol DBA: puede escribir, borrar y cambiar parámetros, y un error o una credencial filtrada lo convierte todo en incidente. `C##OPS_RO` solo lee el diccionario y las vistas `V$`:
- un `CREATE TABLE` da `ORA-01031` (Parte B);
- no tiene ningún privilegio `ANY` (verificación final, `ops_ro_dml = 0`);
- **ni siquiera puede leer datos de negocio**: para el `VSIZE` de `ACA_MATRICULAS` (Parte L) tuve que usar SYSDBA, porque `SELECT_CATALOG_ROLE` no da acceso a las tablas.

**38.** (1) **Contraseñas literales en V000**, ya en el historial de Git: V003 las invalida con `NO AUTHENTICATION` (evidencia 04: de entrar como ADMIN_ACADEMIA a `ORA-01017`). (2) **`sys/<contraseña>` en la línea de comandos** de `08`: `08` v2 usa `/ as sysdba`. Además, `05` v2 ya no pasa `ORACLE_PWD` al reutilizar el volumen, así que no aparece en `docker inspect`, y todas las contraseñas nuevas (`OPS_RO_PWD`) viajan por la entrada estándar.

---

## 9. Preguntas tipo examen adicionales

**P25 · B.** PDB$SEED: plantilla de solo lectura (READ ONLY en mi `v$pdbs`). De ella creé `PDB_LAB4` en la Parte I.

**P26 · C.** `ORA-65094: invalid local user or role name`: el `C##` está reservado a usuarios comunes, que solo se crean en la raíz. Lo vi en el bloque 3b de `10-ciclo-vida-pdb`.

**P27 · B.** Primero `CLOSE IMMEDIATE` y después `DROP ... INCLUDING DATAFILES`. A falla con `ORA-65025` si está abierta, como me pasó en el bloque 5.

**P28 · A y C.** `V$DATAFILE` y `V$LOG` salen del control file, abierto ya en MOUNT (16 datafiles conocidos en E.3). `DBA_` y `CDB_` necesitan el diccionario abierto: `ORA-01219`.

**P29 · A.** KCC es la capa del control file (`x$kccle`, `x$kccrt` en la definición de `GV$LOG`, Parte I).

**P30 · B.** Las vistas CDB_ existen en la raíz y en cada PDB. Desde una PDB solo devuelven sus filas: en FREEPDB1, `CDB_TABLESPACES` dio 10, solo CON_ID 3.

**P31 · B.** Los tempfiles no se respaldan: se recrean. RMAN no los copia (A), el undo vive en UNDOTBS (C) y hay TEMP en la raíz y en la PDB (D).

**P32 · B.** La instancia ya tiene los parámetros en memoria y sigue funcionando. `CREATE SPFILE FROM MEMORY` lo recrea, la misma idea que mi `CREATE PFILE … FROM MEMORY` de la Parte F.

**P33 · B.** `V$PWFILE_USERS`: en mi base, `SYS` con SYSDBA y SYSOPER (Parte J).

**P34 · A y B.** La ITL (`Itl 0x01/0x02`) y el directorio de filas (`pri[0..89]`) están en la cabecera del bloque 782.

**P35 · B.** Primero extensiones de 64 KB (8 bloques) y, al crecer, de 1 MB: las 16 + 1 de `ACA_ESTUDIANTES`.

**P36 · B.** ASSM: espacio libre gestionado con mapas de bits, el que lee `DBMS_SPACE.SPACE_USAGE` (FULL/FS1-FS4).

**P37 · B.** BIGFILE gestionado localmente: todos mis tablespaces nuevos son `BIG = YES` y `LOCAL`.

**P38 · A.** 0 físicas: todos los bloques estaban en la buffer cache. Además, 4 lecturas lógicas son justo raíz, rama, hoja y tabla, como mi 5a.

**P39 · A y B.** Subir PCTFREE (`MIGRA` pasó de 58 a 63 bloques con PCTFREE 20) y filas más grandes (90 filas en el bloque 782 frente a 85 en el 1162). Un bloque mayor (D) lo aumentaría.

**P40 · B.** Vacía la caché de toda la instancia y todas las sesiones pasan a leer de disco hasta recalentarla: picos de latencia. Lo vi en mi ronda en frío (262 físicas frente a 0).

**P41 · B.** La migrada cabía y se mudó al crecer (`MIGRA`); la encadenada no cabe en ningún bloque (`ANCHA`, 12 000 bytes).

**P42 · A.** `ALTER INDEX ... REBUILD`, o haber usado `MOVE ONLINE`: mi `PK_MIGRA` pasó de UNUSABLE a VALID con REBUILD.

**P43 · A.** `V$DIAG_ALERT_EXT`. Con el GRANT sobre `V_$DIAG_ALERT_EXT`, `C##OPS_RO` la usa en `11-archivos` y en la sección 10 de la autopsia.

**P44 · A y B.** Ampliar el espacio (datafile en SMALLFILE, MAXSIZE en BIGFILE) y averiguar qué segmentos crecen. Borrar redo (C) o pasar a NOARCHIVELOG (D) es destruir protección. Reiniciar (E) no libera nada.

**P45 · A y B.** La SGA y los procesos de background (una sola instancia: 87 procesos para todas) y los redo online (`V$LOG` con CON_ID 0). Cada PDB tiene su SYSTEM, sus usuarios locales y, en mi base, su propio UNDOTBS1 (local undo).

**P46 · B.** `ORA-01031: insufficient privileges`, exactamente lo que recibió `lab4_analista` en el bloque 3c.
