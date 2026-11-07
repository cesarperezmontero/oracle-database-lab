# Runbook: pérdida de un datafile de aplicación (FREEPDB1)

**Para:** la persona de guardia, aunque no haya hecho el Lab 5. **Probado:** simulacro D del Lab 5, 2026-11-07, con RTO de 13 s y RPO = 0.

## 1. Síntoma

Las consultas sobre un tablespace fallan con tres errores juntos:

```
ORA-01116: error in opening database file 16                         <- qué número de archivo
ORA-01110: data file 16: '/opt/oracle/oradata/FREE/FREEPDB1/academia01.dbf'   <- qué ruta
ORA-27041: unable to open file / Linux-x86_64 Error: 2: No such file or directory   <- causa en el SO
```

En el alert log puede aparecer además **`ORA-63999: data file suffered media failure`**: un proceso de fondo (CKPT) detectó el fallo y **Oracle cerró la PDB entera** para protegerla. Al reabrirla también puede salir `ORA-01113: file N needs media recovery` en **otros** archivos de la PDB. Es un efecto del cierre brusco: Oracle los recupera solo con el redo online al abrir.

## 2. Comprobaciones previas (no tocar nada hasta tenerlas)

```sql
-- como SYSDBA (docker exec -it oralab-26ai sqlplus / as sysdba)
SELECT log_mode FROM v$database;                       -- debe ser ARCHIVELOG; si no, solo cabe restaurar y PERDER datos
SELECT name, open_mode FROM v$pdbs;                    -- ¿FREEPDB1 sigue READ WRITE o ya está MOUNTED?
SELECT file#, error FROM v$recover_file;               -- qué archivos necesitan recuperación
```

```
RMAN> LIST BACKUP OF DATAFILE 16;                       -- tiene que haber una copia; sin ella, escalar (punto 5)
```

## 3. Reparación: elegir el camino según el estado de la PDB

**Camino 1: FREEPDB1 sigue en READ WRITE.** Solo ese tablespace está caído y el resto de la PDB da servicio.

```sql
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER DATABASE DATAFILE 16 OFFLINE;
```

**Camino 2: FREEPDB1 está MOUNTED** (Oracle la cerró por `ORA-63999`; es el que me tocó). Si `v$pdbs` aún dice que se está cerrando, **esperar a que quede MOUNTED** antes de restaurar: un cierre a medias y un RESTORE a la vez se pisan.

**Los dos caminos siguen igual:**

```
RMAN> RESTORE DATAFILE 16;
RMAN> RECOVER DATAFILE 16;      -- aplica redo archivado (FRA) + online desde la copia: aquí se recupera lo confirmado después
```

```sql
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER DATABASE DATAFILE 16 ONLINE;
ALTER PLUGGABLE DATABASE FREEPDB1 OPEN;   -- solo en el camino 2 (en el 1 ya está abierta)
```

## 4. Verificar que funcionó

```sql
SELECT name, open_mode FROM v$pdbs;          -- FREEPDB1 READ WRITE: no cerrar el incidente antes
SELECT file#, error FROM v$recover_file;     -- ninguna fila
-- fila de control: un dato confirmado DESPUÉS de la copia debe estar (en el simulacro, estudiante 104 = EGRESADO)
SELECT estado FROM admin_academia.aca_estudiantes WHERE estudiante_id = 104;
```

Revisar el alert log desde la hora del fallo: no debe quedar ningún `ORA-` nuevo después de `Completed: ALTER DATABASE DATAFILE 16 ONLINE`.

## 5. A quién avisar

- **Al empezar:** al responsable de la aplicación de esa PDB (servicio degradado; si es el camino 2, **caída de toda FREEPDB1**) y al DBA titular.
- **Escalar de inmediato** si no hay copia (`LIST BACKUP` vacío), la base está en NOARCHIVELOG o `RECOVER` pide un archivado que no está en la FRA. Hay pérdida de datos y la decisión no es de guardia.
- **Al cerrar:** al equipo de sistemas, por la causa del disco (el `Linux Error: 2` dice que el archivo desapareció). Abrir un postmortem sin culpables con RTO, RPO y qué se cambia.
