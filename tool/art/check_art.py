#!/usr/bin/env python3
"""Valida art/source contra art/spec.json: que no falte ninguna pieza, que
los nombres sigan la convención, que cada figura tenga su máscara y que los
tamaños y la transparencia sean los acordados.

Uso: python3 tool/art/check_art.py  (código 1 si hay errores)
"""
import json
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'art' / 'source'
NAME = re.compile(r'^[a-z0-9_]+\.png$')


def check() -> list[str]:
    spec = json.loads((ROOT / 'art' / 'spec.json').read_text())
    errors: list[str] = []

    def opened(path: Path):
        if not path.exists():
            errors.append(f'Falta {path.relative_to(ROOT)}')
            return None
        try:
            return Image.open(path)
        except OSError as e:
            errors.append(f'No se puede abrir {path.relative_to(ROOT)}: {e}')
            return None

    for faction in spec['factions']:
        for profile, info in spec['troops'].items():
            size = info['canvas']
            for state in info['states']:
                base = SRC / 'troops' / faction / f'{profile}_{state}'
                fig = opened(base.with_suffix('.png'))
                mask = opened(Path(f'{base}_mask.png'))
                for img, label in ((fig, 'figura'), (mask, 'máscara')):
                    if img is None:
                        continue
                    where = f'{faction}/{profile}_{state} ({label})'
                    if img.size != (size, size):
                        errors.append(f'{where}: mide {img.size}, se esperaba {size}×{size}')
                    if img.mode != 'RGBA':
                        errors.append(f'{where}: debe tener canal alfa (RGBA), es {img.mode}')
                    elif img.getchannel('A').getbbox() is None:
                        errors.append(f'{where}: está vacía (todo transparente)')

    ppi = spec['pxPerInch']
    for kind, pieces in spec.get('terrain', {}).items():
        for piece, (w_in, h_in) in pieces.items():
            img = opened(SRC / 'terrain' / kind / f'{piece}.png')
            if img is None:
                continue
            expected = (round(w_in * ppi), round(h_in * ppi))
            if img.size != expected:
                errors.append(f'terrain/{kind}/{piece}: mide {img.size}, se esperaba '
                              f'{expected[0]}×{expected[1]} ({w_in}\" × {h_in}\")')
            if img.mode != 'RGBA':
                errors.append(f'terrain/{kind}/{piece}: debe tener canal alfa (RGBA)')

    for effect, info in spec.get('effects', {}).items():
        for i in range(info['frames']):
            img = opened(SRC / 'effects' / f'{effect}_{i:02d}.png')
            if img is not None and img.size != (info['canvas'], info['canvas']):
                errors.append(f'effects/{effect}_{i:02d}: mide {img.size}, se esperaba '
                              f'{info["canvas"]}×{info["canvas"]}')

    for theme, size in spec['ground'].items():
        img = opened(SRC / 'ground' / f'{theme}.png')
        if img is not None and img.size != (size, size):
            errors.append(f'ground/{theme}: mide {img.size}, se esperaba {size}×{size}')

    for path in SRC.rglob('*'):
        if path.is_file() and not NAME.match(path.name):
            errors.append(f'Nombre fuera de convención: {path.relative_to(ROOT)} '
                          '(minúsculas, dígitos y _, extensión .png)')
    return errors


def main() -> int:
    errors = check()
    if errors:
        print('\n'.join(errors))
        print(f'\n{len(errors)} problemas en el arte.')
        return 1
    print('Arte válido: no falta ninguna pieza y todo cumple la especificación.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
