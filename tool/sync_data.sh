#!/usr/bin/env bash
# Copia los datos canónicos (data/) a los assets de la app.
set -euo pipefail
cd "$(dirname "$0")/.."
cp data/*.json app/assets/data/
echo "Datos sincronizados en app/assets/data/"
