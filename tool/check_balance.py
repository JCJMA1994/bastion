#!/usr/bin/env python3
"""Comprueba el resultado del simulador de duelos.

Uso: python3 tool/check_balance.py duelos.json [--min 0.35] [--max 0.65]

Falla (código 1) si algún perfil gana menos de --min o más de --max de sus
duelos de media. Pensado para CI: avisa de desequilibrios tras tocar datos.
"""
import json
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    args = sys.argv[2:]
    low = float(args[args.index('--min') + 1]) if '--min' in args else 0.35
    high = float(args[args.index('--max') + 1]) if '--max' in args else 0.65
    data = json.load(open(sys.argv[1]))
    bad = []
    print(f"{'perfil':14}{'victorias':>10}{'coste':>7}")
    for pid, row in sorted(data['perfiles'].items(), key=lambda kv: -kv[1]['victorias']):
        rate = row['victorias']
        flag = '' if low <= rate <= high else '  ← fuera de rango'
        if flag:
            bad.append(pid)
        print(f"{pid:14}{rate*100:>9.0f}%{row['coste']:>7}{flag}")
    if bad:
        print(f"\nDesequilibrados ({low:.0%}–{high:.0%}): {', '.join(bad)}")
        return 1
    print(f"\nTodos los perfiles entre {low:.0%} y {high:.0%}.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
