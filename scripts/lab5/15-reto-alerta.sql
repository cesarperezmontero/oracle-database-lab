-- scripts/lab5/15-reto-alerta.sql — reto de la Parte P: una consulta que devuelve UNA fila solo cuando hay que despertar a alguien
-- Recuperabilidad (sección 3 + 7 del runbook): FRA por encima del 85 % o ninguna copia RMAN correcta en las últimas 24 h.
-- Sin filas = todo bien. Pensada para un sistema de alertas: SQLcl · C##OPS_RO · servicio FREE (bash scripts/ops/ro.sh <este archivo>)
@scripts/ops/marca
SPOOL docs/bitacora/lab5/evidencia/spool/&marca._15-reto-alerta.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 200 PAGESIZE 50 FEEDBACK ON
COLUMN alerta FORMAT A120
PROMPT == Alerta de recuperabilidad (0 filas = no despertar a nadie) ==
SELECT 'CRITICO: ' || LISTAGG(motivo, ' | ') WITHIN GROUP (ORDER BY motivo) AS alerta
  FROM (SELECT 'FRA al ' || ROUND(100 * (space_used - space_reclaimable) / NULLIF(space_limit, 0), 1) || ' % (umbral 85 %)' AS motivo
          FROM v$recovery_file_dest
         WHERE 100 * (space_used - space_reclaimable) / NULLIF(space_limit, 0) > 85
        UNION ALL
        SELECT 'ninguna copia RMAN COMPLETED en 24 h'
          FROM dual
         WHERE NOT EXISTS (SELECT 1 FROM v$rman_backup_job_details WHERE status = 'COMPLETED' AND end_time > SYSDATE - 1))
HAVING COUNT(*) > 0;
PROMPT == Valores actuales, para comprobar a mano que la consulta no dispara sin motivo ==
SELECT ROUND(100 * (space_used - space_reclaimable) / NULLIF(space_limit, 0), 1) AS fra_pct_no_reclamable,
       (SELECT COUNT(*) FROM v$rman_backup_job_details WHERE status = 'COMPLETED' AND end_time > SYSDATE - 1) AS copias_rman_24h
  FROM v$recovery_file_dest;
SPOOL OFF
