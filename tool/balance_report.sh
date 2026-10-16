#!/usr/bin/env bash
# Informe de balance local: modelo analítico + simulador + comprobación.
# Uso: tool/balance_report.sh [batallas] [campañas]
set -euo pipefail
cd "$(dirname "$0")/.."
BATTLES="${1:-200}"
CAMPAIGNS="${2:-100}"
mkdir -p build/balance
python3 tool/balance_model.py data/units.json | tee build/balance/modelo.txt
(cd packages/rules_engine && dart run bin/simulate.dart duelos --batallas "$BATTLES" --json ../../build/balance/duelos.json) | tee build/balance/duelos.txt
(cd packages/rules_engine && dart run bin/simulate.dart campana --campanas "$CAMPAIGNS") | tee build/balance/campana.txt
python3 tool/check_balance.py build/balance/duelos.json
