# Lab 4 — Informe de autopsia de la instancia FREE

**Autor:** César Pérez Montero
**Fecha:** 2026-11-07
**Fuente principal:** `scripts/lab4/15-autopsia-instancia.sql`, ejecutado como `C##OPS_RO` (solo lectura). Evidencia en `docs/bitacora/lab4/evidencia/spool/*_15-autopsia-instancia.spool.log`.
**Fuentes complementarias:** evidencias 01, 06, 09, 11 y 13, y comprobaciones puntuales como SYSDBA, citadas en cada hallazgo.

**Entorno:** Oracle AI Database 26ai Free 23.26.3.0.0 en Docker. Imagen oficial `container-registry.oracle.com/database/free:latest`; contenedor `oralab-26ai` (host `1798f1f0fffc`, recreado en la Parte C); volumen `oralab-26ai-data`. DBID 1509902213, base creada el 2026-07-05 y CDB con FREEPDB1.

## Hallazgos

| # | Sección | Evidencia (valor exacto) | Riesgo | Acción | Prioridad |
|---|---|---|---|---|---|
| 1 | 1 · 4 | `LOG_MODE = ARCHIVELOG`, pero `db_recovery_file_dest` vacío y `_size = 0`. 13 archived logs (2017 MB) en `$ORACLE_HOME/dbs/arch1_*.dbf`, el destino por defecto, del 2026-07-05 al 2026-11-07. Ninguna política de borrado ni copia RMAN | Los archivados crecen sin límite en la misma carpeta y el mismo volumen que el SPFILE y el password file. Si llenan el disco, ARCn no puede archivar y la base se detiene. Sin copias RMAN, tampoco sirven para recuperar | Configurar FRA con tamaño (`db_recovery_file_dest` y `_size`), copias RMAN y política de retención o borrado de archivados (Lab 5, Parte L) | **Alta** |
| 2 | 4 | 2 control files, los dos en `/opt/oracle/oradata/FREE/` (mismo volumen y carpeta). 3 grupos de redo de 200 MB con **1 miembro** cada uno | Punto único de fallo: perder ese disco o un borrado accidental deja la base sin control file ni redo online, y se pierde lo confirmado que aún no está archivado | Multiplexar los control files en otra ubicación y añadir un segundo miembro por grupo de redo (Lab 5, Partes J y K) | **Alta** |
| 3 | 4 · evidencia 11 | `/opt/oracle/diag` vive en la capa del contenedor. El alert log empieza el **2026-07-05**, en la imagen, y tiene **0 líneas de octubre** | Al recrear el contenedor (Parte C) se perdió todo el historial de diagnóstico del 9 de octubre al 7 de noviembre. En un incidente real faltaría justo lo que necesita el postmortem | Llevar `diagnostic_dest` al volumen, o montar `/opt/oracle/diag` como volumen propio, o enviar el alert log a un sistema centralizado | **Media** |
| 4 | 6 | `ALTURA_MAX` vacía en ADMIN_CLINICA (8 índices), ADMIN_FINTECH (6), ADMIN_LOGISTICA (6) y ADMIN_RETAIL (7). Solo ADMIN_ACADEMIA tiene estadísticas, por V002 | El optimizador usa estimaciones por defecto (dynamic sampling) para esos esquemas: planes poco fiables en cuanto tengan datos | `DBMS_STATS.GATHER_SCHEMA_STATS` en los cuatro esquemas y confirmar que el job automático de estadísticas está activo | Media |
| 5 | 6 | ADMIN_ACADEMIA: 2 de 9 índices con `clustering_factor > 0,5 × num_rows` | Recorrer esos índices por rangos cuesta casi una lectura de tabla por fila: el índice compensa en muchos menos casos (umbral de la Parte L) | Identificar los dos índices y analizar si su orden casa con el acceso real (Lab 5, Parte E) | Baja |
| 6 | 7 | En FREEPDB1, 9 usuarios locales no mantenidos por Oracle. Tres con contraseña: `ALUMNO`, `ORDS_PUBLIC_USER` y `PDBADMIN` (comprobado como SYSDBA). **Comprobado:** `PDBADMIN` inicia sesión en FREEPDB1 con la misma `ORACLE_PWD` de SYS. La contraseña entró por la entrada estándar y no se imprimió. La imagen oficial usa `ORACLE_PWD` para SYS, SYSTEM y PDBADMIN al crear la base. Ninguna cuenta de la casa tiene el rol DBA | Una única contraseña abre SYS, SYSTEM y PDBADMIN: si se filtra una, caen las tres | Cambiar la contraseña de PDBADMIN (o bloquearlo si no se usa) y revisar ALUMNO y ORDS_PUBLIC_USER | Media |
| 7 | 1 | `FORCE_LOGGING = YES`. Viene de la imagen: `ALTER DATABASE FORCE LOGGING` en la parte de julio del alert log | Ninguno grave: todo genera redo, incluso NOLOGGING, lo que protege la recuperación. El coste es más redo en cargas masivas | Documentarlo como decisión de la imagen; tenerlo en cuenta al dimensionar la FRA | Baja |
| 8 | 10 | 6 `ORA-` en 24 h: `ORA-00800` ×4 (VKTM y LGWR, al arrancar), `ORA-65025` ×1 a las 11:40 y `ORA-959` ×1 a las 11:45 | `ORA-00800`: ruido conocido, porque al contenedor le falta `CAP_SYS_NICE`. `ORA-65025` y `ORA-959` los provoqué yo (Parte I: DROP con la PDB abierta; Parte L: `DROP TABLESPACE IF EXISTS` cuando aún no existía). Ningún error real | Documentar `ORA-00800` como conocido y excluirlo de las alertas | — |
| 9 | 2 · 9 | ASMM: `sga_target = 1536M`, shared pool 896 MB y buffer cache 592 MB, sin ajustes desde el arranque. PGA: objetivo 512 MB, máximo usado 464 MB y `over allocation count = 0` | Sin riesgo con la carga actual. El asesor de SGA no aporta nada en una base sin carga real (Parte G) | Revisar tras carga real (Lab 5, banco TiendaSur) | — |

Sano: CDB y FREEPDB1 en READ WRITE. C##OPS_RO común, sin privilegios `ANY` de escritura y con lectura del alert log (Parte J). Los 5 `ADMIN_*` en `NO AUTHENTICATION` (Parte D). Los datafiles de negocio en `FREE/FREEPDB1` con `MAXSIZE 1G` y ocupación del 0,6-2,3 % (Parte C). Solo se publica el puerto 1521. El listener anuncia los servicios `free` y `freepdb1`. `16-verificacion-final.sh`: TODO OK.

## Resumen para dirección

1. La base funciona y está limpia: los errores heredados del Lab 3 (contraseñas expuestas y archivos fuera de su sitio) están corregidos y comprobados.
2. Aún no está protegida ante una avería de disco: hace falta una zona de copias con límite, copias automáticas y duplicar los archivos críticos. Es el trabajo del Lab 5.
3. Mientras tanto, hay que guardar los registros de diagnóstico fuera del contenedor y cambiar una contraseña de administración compartida.
