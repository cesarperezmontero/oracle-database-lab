-- scripts/lab5/03-reto-q9.sql — reto de la Parte D: ¿haría cubriente IX_PED_FECHA para Q9 (los 20 pedidos más recientes, todas las columnas)?
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh scripts/lab5/03-reto-q9.sql <evidencia>. Solo mide: no crea nada.
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 200 PAGESIZE 50 FEEDBACK OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED
PROMPT == Q9 tal cual: 20 pedidos más recientes, todas las columnas ==
EXEC lab_tools.medir.consulta('Q9 con ix_ped_fecha', q'[SELECT * FROM tiendasur.pedido ORDER BY fecha_pedido DESC FETCH FIRST 20 ROWS ONLY]')
PROMPT == Tamaños para decidir: la tabla frente al índice que ya existe ==
COLUMN segment_name FORMAT A14
SELECT segment_name, segment_type, ROUND(bytes / 1048576, 1) AS mb, blocks
  FROM dba_segments WHERE owner = 'TIENDASUR' AND segment_name IN ('PEDIDO', 'IX_PED_FECHA') ORDER BY segment_type DESC;
EXIT
