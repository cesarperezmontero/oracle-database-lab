#!/usr/bin/env bash
# scripts/lab5/12-reto-fra.sh — reto de la Parte M: cuánto crece la FRA al repetir 12-undo-y-redo.sql (en ARCHIVELOG)
# Uso: bash scripts/lab5/12-reto-fra.sh
set -euo pipefail
source scripts/deployment/env/00-config.sh
LOG="$EVID_LAB5/script/$(ts)_12-reto-fra.script.log"
fra() {
  printf "SET HEADING OFF FEEDBACK OFF PAGESIZE 0\nALTER SYSTEM ARCHIVE LOG CURRENT;\nSELECT space_used FROM v\$recovery_file_dest;\nEXIT\n" \
    | docker exec -i "$CONT_NAME" sqlplus -s -L / as sysdba | tr -dc '0-9'
}
{
  ANTES=$(fra)          # se archiva primero lo pendiente: así solo se mide el redo del script
  echo "FRA usada antes : $ANTES bytes"
  bash scripts/ops/sysdba.sh scripts/lab5/12-undo-y-redo.sql | grep -E 'filas|ROLLBACK'
  DESPUES=$(fra)
  echo "FRA usada después: $DESPUES bytes"
  echo "Crecimiento de la FRA: $(( (DESPUES - ANTES) / 1024 )) KB"
} | tee "$LOG"
