-- scripts/lab5/05-reto-revision.sql — reto de la Parte F: revisión de código de una consulta del panel de atención al cliente
-- Se ejecuta como SYSDBA: bash scripts/ops/sysdba.sh scripts/lab5/05-reto-revision.sql <evidencia>
-- Crea los índices temporales de la Parte F para la prueba y los BORRA al final (como 05-sargabilidad.sql).
WHENEVER SQLERROR EXIT FAILURE
SET LINESIZE 220 PAGESIZE 50 FEEDBACK OFF VERIFY OFF TAB OFF
ALTER SESSION SET CONTAINER = FREEPDB1;
SET SERVEROUTPUT ON FORMAT WRAPPED
DECLARE PROCEDURE quitar(p VARCHAR2) IS BEGIN EXECUTE IMMEDIATE p; EXCEPTION WHEN OTHERS THEN NULL; END;
BEGIN quitar('DROP INDEX tiendasur.ix_cli_telefono'); quitar('DROP INDEX tiendasur.ix_cli_apellidos'); END;
/
CREATE INDEX tiendasur.ix_cli_telefono ON tiendasur.cliente (telefono);
CREATE INDEX tiendasur.ix_cli_apellidos ON tiendasur.cliente (apellidos);
PROMPT == Lo que trae el PR (las dos ramas rompen la regla 1 y, por tanto, la 5) ==
EXEC lab_tools.medir.consulta('PR original', q'[SELECT * FROM tiendasur.cliente WHERE SUBSTR(telefono, 1, 3) = '600' OR UPPER(apellidos) = 'GIL']')
PROMPT == ¿Qué guarda de verdad la columna apellidos? (dos apellidos, con mayúscula inicial) ==
SELECT SUM(CASE WHEN UPPER(apellidos) = 'GIL' THEN 1 ELSE 0 END) AS upper_igual_gil, COUNT(*) AS con_gil_en_algun_sitio, SUM(CASE WHEN apellidos LIKE '% Gil' THEN 1 ELSE 0 END) AS segundo_apellido_gil,
       SUM(CASE WHEN apellidos LIKE 'Gil %' THEN 1 ELSE 0 END) AS primer_apellido_gil
  FROM tiendasur.cliente WHERE UPPER(apellidos) = 'GIL' OR apellidos LIKE '% Gil' OR apellidos LIKE 'Gil %';
PROMPT == Reescritura 1: misma semántica, columnas desnudas (LIKE con prefijo y la columna tal cual se guarda) ==
EXEC lab_tools.medir.consulta('reescrita OR', q'[SELECT * FROM tiendasur.cliente WHERE telefono LIKE '600%' OR apellidos = 'Gil']')
EXEC lab_tools.medir.consulta('reescrita UNION', q'[SELECT * FROM tiendasur.cliente WHERE telefono LIKE '600%' UNION SELECT * FROM tiendasur.cliente WHERE apellidos = 'Gil']')
PROMPT == Reescritura 2: si lo que se busca es el PRIMER apellido Gil (prefijo: sargable) ==
EXEC lab_tools.medir.consulta('primer apellido Gil', q'[SELECT * FROM tiendasur.cliente WHERE telefono LIKE '600%' OR apellidos LIKE 'Gil %']')
PROMPT == Limpieza ==
DROP INDEX tiendasur.ix_cli_telefono;
DROP INDEX tiendasur.ix_cli_apellidos;
SELECT COUNT(*) AS indices_tiendasur FROM dba_indexes WHERE owner = 'TIENDASUR';
EXIT
