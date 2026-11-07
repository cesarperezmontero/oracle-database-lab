-- scripts/lab4/13-reto-matriculas.sql — reto de la Parte L: dimensionar ACA_MATRICULAS (predicción frente a realidad)
-- SQLcl · C##OPS_RO · servicio FREEPDB1 (solo diccionario: no lee datos de negocio)
-- Uso: bash scripts/ops/ro.sh scripts/lab4/13-reto-matriculas.sql FREEPDB1
@scripts/ops/marca
SPOOL docs/bitacora/lab4/evidencia/spool/&marca._13-reto-matriculas.spool.log
SET SQLFORMAT DEFAULT
SET LINESIZE 160 PAGESIZE 100 FEEDBACK OFF
COLUMN column_name FORMAT A18
COLUMN data_type FORMAT A14
PROMPT == 1. Antes de mirar las estadísticas: estructura declarada (base de la predicción) ==
SELECT column_id, column_name, data_type, data_length, nullable
  FROM dba_tab_columns WHERE owner = 'ADMIN_ACADEMIA' AND table_name = 'ACA_MATRICULAS' ORDER BY column_id;
PROMPT == 2. Después: lo que dicen las estadísticas (tamaño medio REAL de cada columna y de la fila) ==
SELECT column_name, avg_col_len FROM dba_tab_columns
 WHERE owner = 'ADMIN_ACADEMIA' AND table_name = 'ACA_MATRICULAS' ORDER BY column_id;
SELECT t.num_rows AS r, t.avg_row_len AS r_bytes, t.blocks AS bloques_bajo_hwm, t.pct_free,
       s.blocks AS bloques_asignados, s.extents,
       FLOOR((8192 - 96) * (1 - t.pct_free / 100) / t.avg_row_len) AS bfr_u3,
       CEIL(t.num_rows / FLOOR((8192 - 96) * (1 - t.pct_free / 100) / t.avg_row_len)) AS b_u3,
       ROUND(t.num_rows / NULLIF(t.blocks, 0), 1) AS filas_por_bloque_real
  FROM dba_tables t JOIN dba_segments s ON s.owner = t.owner AND s.segment_name = t.table_name
 WHERE t.owner = 'ADMIN_ACADEMIA' AND t.table_name = 'ACA_MATRICULAS';
SPOOL OFF
