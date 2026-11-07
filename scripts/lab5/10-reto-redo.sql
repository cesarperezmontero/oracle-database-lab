-- scripts/lab5/10-reto-redo.sql — reto de la Parte K: cambios de log por hora y tamaño de redo para la carga de TiendaSur
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh scripts/lab5/10-reto-redo.sql <evidencia>. Solo lee.
SET LINESIZE 160 PAGESIZE 50 FEEDBACK OFF
PROMPT == Cambios de log por hora (hoy, UTC) ==
SELECT TO_CHAR(first_time, 'YYYY-MM-DD HH24') AS hora, COUNT(*) AS cambios_de_log
  FROM v$log_history WHERE first_time > TRUNC(SYSDATE) GROUP BY TO_CHAR(first_time, 'YYYY-MM-DD HH24') ORDER BY 1;
PROMPT == Redo archivado de hoy, por hora (lo que de verdad se generó) ==
SELECT TO_CHAR(first_time, 'YYYY-MM-DD HH24') AS hora, COUNT(*) AS archivados, ROUND(SUM(blocks * block_size) / 1048576) AS mb_redo
  FROM v$archived_log WHERE first_time > TRUNC(SYSDATE) GROUP BY TO_CHAR(first_time, 'YYYY-MM-DD HH24') ORDER BY 1;
PROMPT == Detalle de la hora de la carga de TiendaSur (V004 aplicada a las 14:2x UTC) ==
SELECT sequence#, TO_CHAR(first_time, 'HH24:MI:SS') AS inicio, TO_CHAR(next_time, 'HH24:MI:SS') AS fin, ROUND(blocks * block_size / 1048576) AS mb
  FROM v$archived_log WHERE first_time > TRUNC(SYSDATE) ORDER BY sequence#;
SELECT ROUND(bytes / 1048576) AS mb_por_grupo, COUNT(*) AS grupos FROM v$log GROUP BY bytes;
EXIT
