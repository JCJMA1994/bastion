#!/usr/bin/env python3
"""Empaqueta art/source en atlas para la app (app/assets/art/):

- troops@<escala>_<página>.webp + .json (formato TexturePacker "hash")
- ground/<tema>@<escala>.webp
- manifest.json, que la app lee para saber qué hay

Las escalas salen de art/spec.json (1x = 40 px por pulgada, 2x = 80, 4x = 160).
Añadir arte no exige tocar código: basta con seguir la convención de nombres.

Uso: python3 tool/art/pack_art.py
"""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'art' / 'source'
OUT = ROOT / 'app' / 'assets' / 'art'
PAD = 2


def shelf_pack(items, max_size):
    """Reparte (nombre, imagen) en páginas con estantes; devuelve
    [(ancho, alto, [(nombre, imagen, x, y)])]."""
    items = sorted(items, key=lambda it: (-it[1].size[1], it[0]))
    pages = []
    current, x, y, shelf_h, width = [], 0, 0, 0, 0
    for name, img in items:
        w, h = img.size[0] + PAD, img.size[1] + PAD
        if x + w > max_size:
            x, y, shelf_h = 0, y + shelf_h, 0
        if y + h > max_size:
            pages.append((width, y + shelf_h, current))
            current, x, y, shelf_h, width = [], 0, 0, 0, 0
        current.append((name, img, x, y))
        x += w
        shelf_h = max(shelf_h, h)
        width = max(width, x)
    if current:
        pages.append((width, y + shelf_h, current))
    return pages


def main():
    spec = json.loads((ROOT / 'art' / 'spec.json').read_text())
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.rglob('*'):
        if old.is_file():
            old.unlink()

    families = {}
    for family in ('troops', 'terrain', 'effects'):
        folder = SRC / family
        families[family] = [
            (path.relative_to(folder).with_suffix('').as_posix(),
             Image.open(path).convert('RGBA'))
            for path in sorted(folder.rglob('*.png'))
        ] if folder.exists() else []

    manifest = {
        'version': 2,
        'pxPerInch': {s: spec['pxPerInch'] * k for s, k in spec['scales'].items()},
        'factions': spec['factions'],
        'troops': {name: info['states'] for name, info in spec['troops'].items()},
        'terrain': spec.get('terrain', {}),
        'effects': {name: info['frames'] for name, info in spec.get('effects', {}).items()},
        'atlases': {family: {} for family in families},
        'ground': {},
    }

    for family, sources in families.items():
        for scale, factor in spec['scales'].items():
            scaled = []
            for key, img in sources:
                w0, h0 = img.size
                size = (max(1, round(w0 * factor)), max(1, round(h0 * factor)))
                scaled.append((key, img.resize(size, Image.LANCZOS)))
            files = []
            for i, (w, h, placed) in enumerate(shelf_pack(scaled, spec['maxPage'])):
                page = Image.new('RGBA', (w, h), (0, 0, 0, 0))
                frames = {}
                for key, img, x, y in placed:
                    page.paste(img, (x, y))
                    iw, ih = img.size
                    frames[key] = {
                        'frame': {'x': x, 'y': y, 'w': iw, 'h': ih},
                        'rotated': False,
                        'trimmed': False,
                        'spriteSourceSize': {'x': 0, 'y': 0, 'w': iw, 'h': ih},
                        'sourceSize': {'w': iw, 'h': ih},
                    }
                stem = f'{family}@{scale}_{i}'
                if family == 'troops':
                    # Contornos finos y máscara de bando: sin pérdida.
                    page.save(OUT / f'{stem}.webp', lossless=True, quality=100, method=6)
                else:
                    # Terreno y efectos llevan textura: con pérdida de alta calidad.
                    page.save(OUT / f'{stem}.webp', quality=90, alpha_quality=100, method=6)
                (OUT / f'{stem}.json').write_text(json.dumps({
                    'frames': frames,
                    'meta': {'image': f'{stem}.webp', 'size': {'w': w, 'h': h},
                             'scale': str(factor), 'app': 'bastion/pack_art.py'},
                }, ensure_ascii=False, separators=(',', ':')))
                files.append(f'{stem}.json')
            manifest['atlases'][family][scale] = files

    (OUT / 'ground').mkdir(exist_ok=True)
    for theme in spec['ground']:
        img = Image.open(SRC / 'ground' / f'{theme}.png').convert('RGB')
        entry = {}
        for scale, factor in spec['scales'].items():
            size = round(img.size[0] * factor)
            name = f'ground/{theme}@{scale}.webp'
            img.resize((size, size), Image.LANCZOS).save(OUT / name, quality=88, method=6)
            entry[scale] = name
        manifest['ground'][theme] = entry

    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    total = sum(p.stat().st_size for p in OUT.rglob('*') if p.is_file())
    pages = {fam: {s: len(f) for s, f in by.items()} for fam, by in manifest['atlases'].items()}
    print(f'Atlas generados en {OUT.relative_to(ROOT)}: páginas {pages}, '
          f'{total / 1024:.0f} KB en total')


if __name__ == '__main__':
    main()
