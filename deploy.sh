#!/usr/bin/env bash
#
# Despliega el codigo MQL5 del repositorio en la carpeta MQL5 del terminal MetaTrader 5.
#
# El repositorio es la fuente de verdad. La carpeta del terminal es un destino
# desechable: nunca se edita codigo directamente dentro del terminal.
#
# Cada subcarpeta 4points/ del destino se borra y se vuelve a copiar, de modo que
# los ficheros eliminados en el repositorio no queden colgando en el terminal.
# Solo se toca 4points/, nunca el resto del contenido del terminal.
#
# Configuracion: define MT5_TERMINAL_DIR por variable de entorno o en deploy.config
# (copia deploy.config.example). Debe apuntar a la carpeta que CONTIENE MQL5/, por
# ejemplo:  .../AppData/Roaming/MetaQuotes/Terminal/<terminal-id>
#
# Uso:  ./deploy.sh [--dry-run]
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $arg" >&2; exit 2 ;;
  esac
done

if [[ -f "$REPO_DIR/deploy.config" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_DIR/deploy.config"
fi

if [[ -z "${MT5_TERMINAL_DIR:-}" ]]; then
  echo "ERROR: MT5_TERMINAL_DIR no esta definido." >&2
  echo "Copia deploy.config.example a deploy.config y ajusta la ruta." >&2
  exit 1
fi

TARGET="$MT5_TERMINAL_DIR/MQL5"

if [[ ! -d "$TARGET" ]]; then
  echo "ERROR: no existe la carpeta $TARGET" >&2
  echo "Comprueba que MT5_TERMINAL_DIR apunta a la carpeta que contiene MQL5/." >&2
  exit 1
fi

echo "Origen : $REPO_DIR/MQL5"
echo "Destino: $TARGET"
echo

copied=0
for sub in Include Indicators Experts Scripts; do
  src="$REPO_DIR/MQL5/$sub/4points"
  [[ -d "$src" ]] || continue

  dst="$TARGET/$sub"
  count=$(find "$src" -type f ! -name '.gitkeep' | wc -l | tr -d ' ')
  echo "  $sub/4points  ($count ficheros)"

  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$dst"
    rm -rf "${dst:?}/4points"
    cp -R "$src" "$dst/"
  fi
  copied=$((copied + count))
done

echo
if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry run: no se ha copiado nada. Total que se copiaria: $copied ficheros."
else
  echo "Deploy completado: $copied ficheros. Recompila desde MetaEditor."
fi
