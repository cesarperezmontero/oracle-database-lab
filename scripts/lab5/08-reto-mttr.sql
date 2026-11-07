-- scripts/lab5/08-reto-mttr.sql — reto de la Parte I: cuánto crece el redo pendiente y el MTTR estimado con una carga, sin checkpoint
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh scripts/lab5/08-reto-mttr.sql <evidencia>
-- La carga es el paso 1 de 13-lgwr-dbwn.sql: UPDATE de las 20 000 filas de ACA_ESTUDIANTES sin cambiar el valor.
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 160 PAGESIZE 50 FEEDBACK OFF
PROMPT == Punto de partida: checkpoint, para medir solo lo que añade la carga ==
ALTER SYSTEM CHECKPOINT;
EXEC DBMS_SESSION.SLEEP(5)
SELECT 'antes' AS momento, estimated_mttr, actual_redo_blks, recovery_estimated_ios FROM v$instance_recovery;
ALTER SESSION SET CONTAINER = FREEPDB1;
UPDATE admin_academia.aca_estudiantes SET estado = estado;
COMMIT;
ALTER SESSION SET CONTAINER = CDB$ROOT;
EXEC DBMS_SESSION.SLEEP(5)
SELECT 'despues' AS momento, estimated_mttr, actual_redo_blks, recovery_estimated_ios FROM v$instance_recovery;
EXIT
