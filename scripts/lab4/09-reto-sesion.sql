-- scripts/lab4/09-reto-sesion.sql — reto de la Parte H: ¿qué sesión está consumiendo ahora mismo?
-- SID (Oracle), SPID (PID Linux dentro del contenedor) y PGA del proceso servidor que la atiende.
-- SQLcl · C##OPS_RO · servicio FREE (CONTAINER_DATA = ALL: ve las sesiones de todas las PDB)
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._09-reto-sesion.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
COLUMN username FORMAT A10
COLUMN pdb FORMAT A9
COLUMN spid FORMAT A8
COLUMN program FORMAT A26
COLUMN sql_text FORMAT A60
PROMPT == Sesiones de usuario ACTIVAS (menos la mía), de más a menos PGA ==
SELECT s.sid, s.serial#, s.username, c.name AS pdb, p.spid, s.program,
       ROUND(p.pga_used_mem / 1048576, 1) AS pga_usada_mb,
       ROUND(p.pga_alloc_mem / 1048576, 1) AS pga_asignada_mb,
       s.last_call_et AS seg_en_curso,
       SUBSTR(q.sql_text, 1, 60) AS sql_text
  FROM v$session s
  JOIN v$process p ON p.addr = s.paddr
  JOIN v$containers c ON c.con_id = s.con_id
  LEFT JOIN v$sql q ON q.sql_id = s.sql_id AND q.child_number = s.sql_child_number AND q.con_id = s.con_id
 WHERE s.type = 'USER' AND s.status = 'ACTIVE'
   AND s.sid <> SYS_CONTEXT('USERENV', 'SID')
 ORDER BY p.pga_alloc_mem DESC;
SPOOL OFF
