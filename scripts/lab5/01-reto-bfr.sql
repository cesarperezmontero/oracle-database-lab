-- scripts/lab5/01-reto-bfr.sql — reto de la Parte B: filas reales por bloque de PEDIDO (y de CLIENTE) frente a NUM_ROWS / BLOCKS
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh scripts/lab5/01-reto-bfr.sql <evidencia>
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 160 PAGESIZE 50 FEEDBACK OFF
COLUMN tabla FORMAT A8
ALTER SESSION SET CONTAINER = FREEPDB1;
PROMPT == Filas por bloque medidas con DBMS_ROWID (TBS_TIENDASUR es BIGFILE) frente a la media de las estadísticas ==
SELECT a.tabla, a.bloques_con_filas, a.min_filas, a.media, a.max_filas, ROUND(t.num_rows / t.blocks, 1) AS num_rows_entre_blocks
  FROM (SELECT 'PEDIDO' AS tabla, COUNT(*) AS bloques_con_filas, MIN(n) AS min_filas, ROUND(AVG(n), 1) AS media, MAX(n) AS max_filas
          FROM (SELECT COUNT(*) n FROM tiendasur.pedido GROUP BY DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE'))
        UNION ALL
        SELECT 'CLIENTE', COUNT(*), MIN(n), ROUND(AVG(n), 1), MAX(n)
          FROM (SELECT COUNT(*) n FROM tiendasur.cliente GROUP BY DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE'))) a
  JOIN dba_tables t ON t.owner = 'TIENDASUR' AND t.table_name = a.tabla;
PROMPT == Distribución: cuántos bloques de PEDIDO tienen cada número de filas ==
SELECT n AS filas_en_el_bloque, COUNT(*) AS bloques
  FROM (SELECT COUNT(*) n FROM tiendasur.pedido GROUP BY DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID, 'BIGFILE'))
 GROUP BY n ORDER BY n;
PROMPT == Longitud de fila de PEDIDO (VSIZE): mínimo, media y máximo ==
SELECT MIN(l) AS min_bytes, ROUND(AVG(l), 1) AS media_bytes, MAX(l) AS max_bytes FROM (
  SELECT VSIZE(id_pedido) + VSIZE(id_cliente) + VSIZE(fecha_pedido) + VSIZE(estado) + VSIZE(importe) + VSIZE(canal) + VSIZE(codigo_postal) AS l
    FROM tiendasur.pedido);
SELECT pct_free FROM dba_tables WHERE owner = 'TIENDASUR' AND table_name = 'PEDIDO';
EXIT
