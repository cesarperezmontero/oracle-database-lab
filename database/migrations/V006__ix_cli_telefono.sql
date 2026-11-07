-- database/migrations/V006__ix_cli_telefono.sql
-- Reto de la Parte G del Lab 5 (defiende tu propio índice), medido con scripts/lab5/06-reto-v006.sql:
--   + ix_cli_telefono  Q5 (atención al cliente: email = :x OR telefono = :x). Sin él, el OR lee CLIENTE entera
--                      (1486 lecturas); con él, BITMAP OR de dos RANGE SCAN: 6 lecturas. Solo por teléfono: 1486 -> 3.
--                      100 000 valores distintos (0,001 % por valor).
--                      Coste medido: INSERT en CLIENTE de 10,1 a 12,2 bloques por fila (+254 bytes de redo); 3 MB.
--                      No es prefijo de ningún otro índice (IX_CLI_PAIS_CIUDAD, PK_CLIENTE, UX_CLI_DNI, UX_CLI_EMAIL).
--   Ciclo de vida: vigilar DBA_INDEX_USAGE tras un cierre de mes completo; si no se usa, INVISIBLE y DROP por migración.
-- Idempotente: si ix_cli_telefono ya existe, no hace nada.
SET FEEDBACK ON
ALTER SESSION SET CONTAINER = FREEPDB1;
WHENEVER SQLERROR EXIT SUCCESS
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_indexes WHERE owner = 'TIENDASUR' AND index_name = 'IX_CLI_TELEFONO';
  IF n > 0 THEN RAISE_APPLICATION_ERROR(-20006, 'V006 ya aplicada: IX_CLI_TELEFONO existe, no se hace nada'); END IF;
END;
/
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE INDEX tiendasur.ix_cli_telefono ON tiendasur.cliente (telefono) ONLINE;
SET LINESIZE 150 PAGESIZE 50
COLUMN table_name FORMAT A8
COLUMN index_name FORMAT A20
SELECT table_name, index_name, uniqueness, visibility FROM dba_indexes WHERE owner = 'TIENDASUR' AND table_name = 'CLIENTE' ORDER BY index_name;
EXIT
