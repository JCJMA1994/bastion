#!/usr/bin/env bash
# Valida y empaqueta el arte (art/source → app/assets/art).
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tool/art/check_art.py
python3 tool/art/pack_art.py
