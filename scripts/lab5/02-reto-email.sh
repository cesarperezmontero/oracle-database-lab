#!/usr/bin/env bash
# scripts/lab5/02-reto-email.sh — reto de la Parte C: altura medida de UX_CLI_EMAIL y su radiografía frente a PK_CLIENTE
# Uso: bash scripts/lab5/02-reto-email.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
TS=$(ts)
docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba <<'SQL' | tee "$EVID_LAB5/script/${TS}_02-reto-email.script.log"
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 170 PAGESIZE 50 FEEDBACK OFF
COLUMN name FORMAT A14
ALTER SESSION SET CONTAINER = FREEPDB1;
PROMPT == UX_CLI_EMAIL frente a PK_CLIENTE: INDEX_STATS (VALIDATE STRUCTURE, solo en laboratorio: bloquea la tabla) ==
CREATE GLOBAL TEMPORARY TABLE IF NOT EXISTS lab_tools.reto_index_stats ON COMMIT PRESERVE ROWS AS SELECT * FROM index_stats WHERE 1 = 0;
TRUNCATE TABLE lab_tools.reto_index_stats;
ANALYZE INDEX tiendasur.ux_cli_email VALIDATE STRUCTURE;
INSERT INTO lab_tools.reto_index_stats SELECT * FROM index_stats;
ANALYZE INDEX tiendasur.pk_cliente VALIDATE STRUCTURE;
INSERT INTO lab_tools.reto_index_stats SELECT * FROM index_stats;
SELECT name, height AS altura, lf_rows AS entradas, lf_blks AS hojas, br_blks AS ramas,
       ROUND(lf_rows_len / lf_rows, 1) AS bytes_entrada_hoja, ROUND(br_rows_len / NULLIF(br_rows, 0), 1) AS bytes_entrada_rama,
       FLOOR(br_blk_len / (br_rows_len / NULLIF(br_rows, 0))) AS fo_max, ROUND(lf_rows / lf_blks) AS entradas_por_hoja, pct_used
  FROM lab_tools.reto_index_stats ORDER BY name;
TRUNCATE TABLE lab_tools.reto_index_stats;
DROP TABLE lab_tools.reto_index_stats PURGE;
EXIT
SQL
for IDX in UX_CLI_EMAIL PK_CLIENTE; do
  bash scripts/ops/grafico-indice.sh TIENDASUR "$IDX" "$EVID_LAB5/script/${TS}_02-grafico-reto-${IDX}.script.log" | sed -n '/resumen/,/Pista/p'
done
