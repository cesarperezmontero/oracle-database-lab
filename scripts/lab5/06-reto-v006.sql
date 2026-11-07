-- scripts/lab5/06-reto-v006.sql — reto de la Parte G: defender (o no) un índice que V005 no cubre
-- Candidato: IX_CLI_TELEFONO para Q5 (identificar a quien llama al centro de atención: email = :x OR telefono = :x).
-- Mide las cinco preguntas con el índice creado de forma TEMPORAL y lo BORRA al final: V006 no se aplica en este laboratorio.
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh scripts/lab5/06-reto-v006.sql <evidencia>
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 220 PAGESIZE 50 FEEDBACK OFF VERIFY OFF TAB OFF
COLUMN index_name FORMAT A18
COLUMN columnas FORMAT A40
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED
BEGIN EXECUTE IMMEDIATE 'DROP INDEX tiendasur.ix_cli_telefono'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
COLUMN tel NEW_VALUE tel NOPRINT
SELECT telefono AS tel FROM tiendasur.cliente WHERE id_cliente = 4711;
DEFINE ins = "BEGIN FOR i IN 1 .. 2000 LOOP INSERT INTO tiendasur.cliente (id_cliente, dni, email, nombre, apellidos, telefono, pais, ciudad, fecha_alta) VALUES (900000 + i, 'Y' || LPAD(i, 7, '0') || 'Q', 'v006_' || i || '@tiendasur.es', 'N', 'A B', TO_CHAR(700000000 + i * 37), 'ES', 'Lorca', SYSDATE); END LOOP; END;"
PROMPT ===== ANTES (sin IX_CLI_TELEFONO) =====
EXEC lab_tools.medir.consulta('Q5 OR antes', q'[SELECT id_cliente, nombre, apellidos FROM tiendasur.cliente WHERE email = '&tel' OR telefono = '&tel']')
EXEC lab_tools.medir.consulta('Q5 solo telefono antes', q'[SELECT id_cliente, nombre, apellidos FROM tiendasur.cliente WHERE telefono = '&tel']')
EXEC lab_tools.medir.dml('CLIENTE 2000 INSERT antes', q'[&ins]', 2000)
PROMPT ===== Pregunta 4 · REDUNDANCIA: ¿algún índice de CLIENTE empieza ya por TELEFONO? =====
SELECT i.index_name, LISTAGG(c.column_name, ', ') WITHIN GROUP (ORDER BY c.column_position) AS columnas
  FROM dba_indexes i JOIN dba_ind_columns c ON c.index_owner = i.owner AND c.index_name = i.index_name
 WHERE i.owner = 'TIENDASUR' AND i.table_name = 'CLIENTE' GROUP BY i.index_name ORDER BY 1;
PROMPT ===== Pregunta 2 · VIABILIDAD: claves distintas de TELEFONO =====
SELECT num_distinct AS claves, ROUND(100 / num_distinct, 4) AS pct_por_valor FROM dba_tab_col_statistics
 WHERE owner = 'TIENDASUR' AND table_name = 'CLIENTE' AND column_name = 'TELEFONO';
CREATE INDEX tiendasur.ix_cli_telefono ON tiendasur.cliente (telefono) ONLINE;
PROMPT ===== DESPUÉS (con IX_CLI_TELEFONO temporal) =====
EXEC lab_tools.medir.consulta('Q5 OR despues', q'[SELECT id_cliente, nombre, apellidos FROM tiendasur.cliente WHERE email = '&tel' OR telefono = '&tel']')
EXEC lab_tools.medir.consulta('Q5 solo telefono despues', q'[SELECT id_cliente, nombre, apellidos FROM tiendasur.cliente WHERE telefono = '&tel']')
EXEC lab_tools.medir.dml('CLIENTE 2000 INSERT despues', q'[&ins]', 2000)
SELECT segment_name AS index_name, ROUND(bytes / 1048576, 1) AS mb, (SELECT leaf_blocks FROM dba_indexes WHERE owner = 'TIENDASUR' AND index_name = 'IX_CLI_TELEFONO') AS hojas
  FROM dba_segments WHERE owner = 'TIENDASUR' AND segment_name = 'IX_CLI_TELEFONO';
PROMPT ===== Limpieza: V006 NO se aplica en este laboratorio =====
DROP INDEX tiendasur.ix_cli_telefono;
SELECT COUNT(*) AS indices_cliente FROM dba_indexes WHERE owner = 'TIENDASUR' AND table_name = 'CLIENTE';
EXIT
