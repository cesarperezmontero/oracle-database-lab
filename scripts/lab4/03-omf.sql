-- scripts/lab4/03-omf.sql — reto de la Parte C: que un CREATE TABLESPACE sin ruta no vuelva a dejar archivos fuera del volumen
-- Oracle Managed Files (OMF) en FREEPDB1: db_create_file_dest apunta a la raíz del volumen.
-- SCOPE = BOTH: vale ya (memoria) y tras reiniciar (SPFILE, guardado para esta PDB).
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh scripts/lab4/03-omf.sql <evidencia>
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET LINESIZE 200 PAGESIZE 50 FEEDBACK ON
COLUMN name FORMAT A20
COLUMN value FORMAT A22
COLUMN file_name FORMAT A100
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SYSTEM SET db_create_file_dest = '/opt/oracle/oradata' SCOPE = BOTH;
SELECT name, value, ispdb_modifiable FROM v$parameter WHERE name = 'db_create_file_dest';
SELECT name, value FROM v$spparameter WHERE name = 'db_create_file_dest';
PROMPT == Prueba: CREATE TABLESPACE sin cláusula DATAFILE ==
CREATE TABLESPACE tbs_x;
SELECT file_name, ROUND(bytes / 1048576) AS mb, autoextensible, ROUND(maxbytes / 1048576) AS max_mb
  FROM dba_data_files WHERE tablespace_name = 'TBS_X';
-- Con OMF, DROP ... INCLUDING CONTENTS borra también el archivo
DROP TABLESPACE tbs_x INCLUDING CONTENTS;
EXIT
