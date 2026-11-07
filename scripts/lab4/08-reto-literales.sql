-- scripts/lab4/08-reto-literales.sql — reto de la Parte G: sentencias que la aplicación ejecuta con literales
-- Misma forma, distinto literal = mismo FORCE_MATCHING_SIGNATURE con muchos SQL_ID distintos.
-- SQLcl · C##OPS_RO · servicio FREE (CONTAINER_DATA = ALL: ve los cursores de todas las PDB)
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._08-reto-literales.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
COLUMN force_matching_signature FORMAT 99999999999999999999
COLUMN ejemplo FORMAT A80
PROMPT == Firmas con más de 50 sentencias distintas (candidatas a variables de enlace) ==
SELECT con_id, force_matching_signature,
       COUNT(DISTINCT sql_id) AS sentencias, SUM(executions) AS ejecuciones,
       ROUND(SUM(sharable_mem) / 1024) AS kb_shared_pool,
       MIN(SUBSTR(sql_text, 1, 80)) AS ejemplo
  FROM v$sql
 WHERE force_matching_signature <> 0
 GROUP BY con_id, force_matching_signature
HAVING COUNT(DISTINCT sql_id) > 50
 ORDER BY sentencias DESC;
SPOOL OFF
