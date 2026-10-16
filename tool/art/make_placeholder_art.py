#!/usr/bin/env python3
"""Genera el arte PROVISIONAL de Bastión en art/source/, con la convención de
la especificación del plan de arte: figuras vistas desde arriba mirando a la
derecha, a 160 px por pulgada, con máscara de color de bando sombreada.

Es arte procedural (formas con relieve, contorno y textura), no ilustración
de artista: sirve para jugar y probar la tubería mientras llega el arte
definitivo, que sustituye estos archivos manteniendo los nombres.

Uso: python3 tool/art/make_placeholder_art.py [troops] [terrain] [effects] [ground]
     (sin argumentos genera todo)
"""
import json
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from paint import Painter, lying, seamless_noise  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'art' / 'source'
SPEC = json.loads((ROOT / 'art' / 'spec.json').read_text())
PPI = SPEC['pxPerInch']
BASE_R = PPI / 2  # radio de la peana en px del master

PALETTES = {
    # Compañía: caqui y cuero, casco plano de acero.
    'compania': dict(cloth=(112, 102, 74), dark=(84, 76, 54), pack=(118, 98, 64),
                     roll=(132, 120, 96), helmet=(96, 98, 88), skin=(206, 164, 130),
                     wood=(128, 86, 50), steel=(74, 78, 84), silver=(200, 204, 210),
                     leather=(96, 66, 40), spike=False),
    # Columna: gris azulado, casco con punta.
    'columna': dict(cloth=(78, 88, 102), dark=(58, 66, 78), pack=(92, 84, 72),
                    roll=(112, 108, 100), helmet=(56, 58, 62), skin=(200, 158, 124),
                    wood=(116, 80, 48), steel=(70, 74, 80), silver=(196, 200, 206),
                    leather=(70, 52, 36), spike=True),
}


# ------------------------------------------------------------------ tropas

def soldier(p, c, gear, ox=0.0, oy=0.0, s=1.0):
    """Soldado visto desde arriba, mirando a +x, centrado en (ox, oy) con
    escala s. `gear`: fusil, carabina, precision, hacha, lanzallamas, sable,
    baqueta o nada. Devuelve la punta del arma (para el fogonazo)."""
    T = lambda x, y: (ox + x * s, oy + y * s)  # noqa: E731

    def E(x0, y0, x1, y1):
        return p.ellipse(*T(x0, y0), *T(x1, y1))

    def R(x0, y0, x1, y1, r=0.08):
        return p.rrect(*T(x0, y0), *T(x1, y1), r * s)

    def L(pts, w):
        return p.stroke([T(x, y) for x, y in pts], w * s)

    tip = None
    if gear == 'lanzallamas':
        for y0, y1 in ((-0.31, -0.02), (0.02, 0.31)):
            p.layer(R(-0.74, y0, -0.24, y1, 0.12), (92, 98, 82), texture=0.15)
            p.layer(L([(-0.62, y0 + 0.02), (-0.62, y1 - 0.02)], 0.035), (54, 56, 50), bevel=0.02,
                    outline=0)
            p.layer(L([(-0.38, y0 + 0.02), (-0.38, y1 - 0.02)], 0.035), (54, 56, 50), bevel=0.02,
                    outline=0)
    elif gear not in ('nada', 'baqueta', 'sable'):  # oficiales y jinetes sin mochila
        p.layer(E(-0.72, -0.30, -0.50, 0.30), c['roll'], texture=0.25)
        p.layer(R(-0.62, -0.26, -0.22, 0.26, 0.07), c['pack'], texture=0.2)
        p.layer(L([(-0.55, -0.24), (-0.55, 0.24)], 0.03), c['leather'], bevel=0.02, outline=0)

    # Torso y hombreras (color de bando).
    p.layer(E(-0.40, -0.46, 0.22, 0.46), c['cloth'], texture=0.18)
    p.layer(L([(-0.30, -0.36), (0.12, 0.34)], 0.05), c['leather'], bevel=0.02, outline=0.015)
    p.layer(E(-0.22, -0.49, 0.06, -0.29), (0, 0, 0), team=True, bevel=0.05)
    p.layer(E(-0.22, 0.29, 0.06, 0.49), (0, 0, 0), team=True, bevel=0.05)

    if gear == 'hacha':
        p.layer(E(-0.24, 0.30, 0.06, 0.58), c['leather'], texture=0.2)  # bolsa de granadas
        for gx in (-0.14, -0.02):
            p.layer(E(gx - 0.06, 0.36, gx + 0.06, 0.48), (70, 74, 64), bevel=0.03)
        p.layer(L([(-0.02, -0.36), (0.30, -0.30), (0.52, -0.30)], 0.15), c['dark'])
        p.layer(L([(0.20, -0.30), (0.95, -0.30)], 0.07), c['wood'], bevel=0.03)
        p.layer(p.poly([T(0.80, -0.30), T(1.02, -0.58), T(1.10, -0.42), T(1.02, -0.30)]),
                c['silver'], bevel=0.03)
        p.layer(E(0.46, -0.37, 0.58, -0.23), c['skin'], bevel=0.03)
        tip = T(1.0, -0.3)
    elif gear == 'sable':
        p.layer(L([(-0.02, 0.36), (0.22, 0.38), (0.36, 0.34)], 0.15), c['dark'])
        p.layer(L([(0.38, 0.34), (1.02, 0.60)], 0.05), c['silver'], bevel=0.02)
        p.layer(E(0.30, 0.26, 0.44, 0.42), (190, 150, 70), bevel=0.03)  # guarda dorada
        p.layer(L([(-0.02, -0.36), (0.16, -0.28)], 0.14), c['dark'])
    elif gear == 'baqueta':
        p.layer(L([(-0.02, -0.34), (0.28, -0.20), (0.48, -0.10)], 0.15), c['dark'])
        p.layer(L([(0.10, -0.10), (1.05, -0.10)], 0.05), c['wood'], bevel=0.02)
        p.layer(E(0.98, -0.16, 1.14, -0.04), (90, 80, 70), bevel=0.03)
        p.layer(E(0.42, -0.16, 0.54, -0.04), c['skin'], bevel=0.03)
    elif gear != 'nada':
        length = {'fusil': 1.12, 'carabina': 0.82, 'precision': 1.22, 'lanzallamas': 0.95}[gear]
        y = 0.22
        p.layer(L([(-0.02, 0.36), (0.25, 0.33), (0.40, y + 0.02)], 0.16), c['dark'])
        p.layer(L([(-0.02, -0.36), (0.30, -0.20), (0.62, y - 0.02)], 0.15), c['dark'])
        if gear == 'lanzallamas':
            p.layer(L([(-0.40, 0.20), (-0.20, 0.52), (0.20, 0.42), (0.34, y)], 0.05),
                    (40, 40, 38), bevel=0.02, outline=0.01)
            p.layer(L([(0.28, y), (length, y)], 0.10), c['steel'], bevel=0.03)
            p.layer(E(length - 0.06, y - 0.08, length + 0.08, y + 0.08), (60, 62, 64))
        else:
            p.layer(L([(0.05, y), (0.45, y)], 0.13), c['wood'], bevel=0.04, texture=0.2)
            p.layer(L([(0.42, y), (length, y)], 0.065), c['steel'], bevel=0.025)
            if gear == 'fusil':
                p.layer(L([(length, y), (length + 0.24, y)], 0.035), c['silver'], bevel=0.015)
                length += 0.24
            if gear == 'precision':
                p.layer(L([(0.46, y - 0.10), (0.82, y - 0.10)], 0.07), (40, 42, 46), bevel=0.025)
        p.layer(E(0.34, y - 0.07, 0.48, y + 0.07), c['skin'], bevel=0.03)
        p.layer(E(0.56, y - 0.065, 0.69, y + 0.065), c['skin'], bevel=0.03)
        tip = T(length, y)

    # Cabeza: casco (con punta en la columna), gorra o sombrero.
    if gear == 'carabina':
        p.layer(E(-0.36, -0.32, 0.26, 0.32), (110, 92, 66), texture=0.15)  # sombrero de ala
        p.layer(E(-0.20, -0.17, 0.10, 0.17), (96, 80, 56), bevel=0.05)
    elif gear == 'sable':
        p.layer(E(-0.25, -0.20, 0.15, 0.20), c['dark'])
        p.layer(E(0.06, -0.13, 0.25, 0.13), (40, 36, 30), bevel=0.03)  # visera
        p.layer(E(-0.22, -0.07, -0.08, 0.07), (0, 0, 0), team=True, bevel=0.03)  # penacho
    else:
        p.layer(E(-0.27, -0.22, 0.17, 0.22), c['helmet'], light=0.75)
        if c['spike']:
            p.layer(E(-0.08, -0.05, 0.02, 0.05), c['silver'], bevel=0.02)
    return tip


def muzzle_flash(p, tip, size=1.0):
    """Fogonazo y humo en `tip`, en unidades de dibujo (no en píxeles)."""
    if tip is None:
        return
    x, y = tip
    star = p.poly([(x - 0.05 * size, y - 0.14 * size), (x + 0.42 * size, y),
                   (x - 0.05 * size, y + 0.14 * size), (x + 0.10 * size, y)])
    p.glow(star, (255, 196, 90), blur=0.05)
    p.glow(p.ellipse(x - 0.06 * size, y - 0.07 * size, x + 0.14 * size, y + 0.07 * size),
           (255, 246, 210), blur=0.04)
    for k in range(3):
        sx = x + (0.30 + 0.16 * k) * size
        sy = y + (0.06 if k % 2 else -0.05) * size
        r = (0.07 + 0.03 * k) * size
        p.glow(p.ellipse(sx - r, sy - r, sx + r, sy + r), (210, 206, 198), blur=0.06,
               strength=0.55)


def horse_and_rider(p, c, firing=False):
    coat, dark = (118, 82, 52), (64, 44, 30)
    for lx, ly in ((0.42, -0.36), (0.42, 0.36), (-0.70, -0.34), (-0.70, 0.34)):
        p.layer(p.ellipse(lx - 0.09, ly - 0.07, lx + 0.09, ly + 0.07), dark, bevel=0.03)
    p.layer(p.stroke([(-1.0, 0.0), (-1.24, 0.08), (-1.42, 0.02)], 0.12), (48, 34, 24),
            bevel=0.04, texture=0.3)
    p.layer(p.ellipse(-1.06, -0.33, -0.42, 0.33), coat, texture=0.15)
    p.layer(p.ellipse(-0.96, -0.36, 0.62, 0.36), coat, texture=0.15)
    p.layer(p.poly([(0.42, -0.19), (0.96, -0.12), (0.96, 0.12), (0.42, 0.19)]), coat,
            texture=0.15)
    p.layer(p.ellipse(0.84, -0.15, 1.36, 0.15), coat, texture=0.15)
    p.layer(p.ellipse(1.20, -0.11, 1.44, 0.11), (92, 64, 42), bevel=0.04)
    for ey in (-0.13, 0.13):
        p.layer(p.ellipse(0.84, ey - 0.05, 0.96, ey + 0.05), dark, bevel=0.02)
    p.layer(p.stroke([(0.40, 0.0), (0.95, 0.0)], 0.07), (40, 28, 20), bevel=0.02, outline=0)
    p.layer(p.rrect(-0.66, -0.52, 0.20, 0.52, 0.08), (0, 0, 0), team=True, bevel=0.05)
    p.layer(p.rrect(-0.36, -0.30, 0.0, 0.30, 0.08), c['leather'], bevel=0.04)
    tip = soldier(p, c, 'sable', ox=-0.16, oy=0.0, s=0.92)
    if firing:
        muzzle_flash(p, tip, 0.8)


def cannon(p, c, firing=False):
    bronze = (156, 112, 58)
    p.layer(p.poly([(-0.10, -0.10), (-1.22, -0.06), (-1.22, 0.06), (-0.10, 0.10)]), c['wood'],
            texture=0.25)
    p.layer(p.rrect(-1.34, -0.14, -1.18, 0.14, 0.03), c['steel'])
    p.layer(p.stroke([(-0.12, -0.70), (-0.12, 0.70)], 0.10), c['steel'], bevel=0.03)
    for wy in (-0.68, 0.68):
        p.layer(p.rrect(-0.58, wy - 0.07, 0.34, wy + 0.07, 0.07), c['wood'], texture=0.2)
        for wx in (-0.58, 0.28):  # llantas de hierro
            p.layer(p.rrect(wx, wy - 0.075, wx + 0.06, wy + 0.075, 0.03), c['steel'],
                    bevel=0.02, outline=0)
        hub_y = wy + (0.10 if wy > 0 else -0.10)
        p.layer(p.ellipse(-0.20, hub_y - 0.06, -0.04, hub_y + 0.06), c['steel'], bevel=0.03)
    p.layer(p.poly([(-0.26, -0.17), (1.14, -0.11), (1.14, 0.11), (-0.26, 0.17)]), bronze,
            light=0.8, texture=0.1)
    for bx in (0.10, 0.62, 1.02):
        p.layer(p.stroke([(bx, -0.15), (bx, 0.15)], 0.04), (120, 84, 40), bevel=0.02, outline=0)
    p.layer(p.ellipse(1.08, -0.14, 1.22, 0.14), bronze, light=0.8)
    p.layer(p.ellipse(-0.40, -0.10, -0.22, 0.10), bronze, light=0.8)
    soldier(p, c, 'baqueta', ox=-0.90, oy=-0.80, s=0.72)
    soldier(p, c, 'nada', ox=-0.90, oy=0.80, s=0.72)
    if firing:
        muzzle_flash(p, (1.22, 0.0), 1.6)


TROOP_GEAR = {
    'capitana': 'sable', 'lanceros': 'fusil', 'exploradores': 'carabina',
    'tiradores': 'precision', 'granaderos': 'hacha', 'zapadores': 'lanzallamas',
}


def capitana_extras(p, c):
    """Capa (color de bando) y bandera, por debajo de la figura."""
    p.layer(p.poly([(-0.22, -0.46), (-0.78, -0.40), (-0.86, 0.0), (-0.78, 0.40), (-0.22, 0.46)]),
            (0, 0, 0), team=True, bevel=0.06, texture=0.15)
    p.layer(p.stroke([(-0.36, 0.40), (-0.36, -0.92)], 0.05), c['wood'], bevel=0.02)
    p.layer(p.poly([(-0.36, -0.92), (0.10, -0.86), (0.42, -0.94), (0.18, -0.68),
                    (0.44, -0.60), (-0.36, -0.58)]), (0, 0, 0), team=True, bevel=0.04)


def troop(profile, faction, state):
    info = SPEC['troops'][profile]
    size = info['canvas']
    c = PALETTES[faction]
    p = Painter(size, size, BASE_R)
    firing = state == 'disparo'
    if profile == 'batidores':
        horse_and_rider(p, c)
    elif profile == 'canon':
        cannon(p, c, firing)
    else:
        if profile == 'capitana':
            capitana_extras(p, c)
        tip = soldier(p, c, TROOP_GEAR[profile])
        if firing:
            muzzle_flash(p, tip, 1.4 if profile == 'zapadores' else 1.0)
    fig, team = p.finish()
    if state == 'caida':
        fig = lying(fig)
        team = lying(team, fade=0.0)
    return fig, team


# ----------------------------------------------------------------- terreno

def terrain_piece(kind, piece, w_in, h_in):
    p = Painter(round(w_in * PPI), round(h_in * PPI), PPI)  # unidad = 1 pulgada
    rnd = random.Random(f'{kind}/{piece}')
    hw, hh = w_in / 2, h_in / 2
    stone, mortar, brick = (150, 138, 118), (92, 84, 72), (150, 92, 70)

    def bricks(x0, y0, x1, y1, course=0.16, length=0.32):
        p.layer(p.rrect(x0, y0, x1, y1, 0.03), stone, texture=0.25)
        y, row = y0, 0
        while y < y1 - 0.02:
            p.layer(p.stroke([(x0 + 0.02, y), (x1 - 0.02, y)], 0.018), mortar, bevel=0.005,
                    outline=0)
            x = x0 + (length / 2 if row % 2 else 0)
            while x < x1:
                p.layer(p.stroke([(x, y), (x, min(y + course, y1))], 0.016), mortar,
                        bevel=0.005, outline=0)
                x += length
            y += course
            row += 1

    def rubble(n, spread_x, spread_y, scale=1.0):
        for _ in range(n):
            cx, cy = rnd.uniform(-spread_x, spread_x), rnd.uniform(-spread_y, spread_y)
            r = rnd.uniform(0.06, 0.16) * scale
            pts = [(cx + r * math.cos(a) * rnd.uniform(0.7, 1.2),
                    cy + r * math.sin(a) * rnd.uniform(0.7, 1.2))
                   for a in sorted(rnd.uniform(0, 2 * math.pi) for _ in range(6))]
            p.layer(p.poly(pts), brick if rnd.random() < 0.35 else stone, bevel=0.03,
                    texture=0.25)

    if kind == 'ruinas':
        if piece == 'muro':
            bricks(-hw + 0.05, -hh + 0.12, hw - 0.25, hh - 0.12)
            rubble(5, 0.25, hh * 0.6) if False else None
            for _ in range(4):
                cx = rnd.uniform(hw - 0.35, hw - 0.1)
                cy = rnd.uniform(-hh + 0.1, hh - 0.1)
                p.layer(p.rrect(cx - 0.08, cy - 0.05, cx + 0.08, cy + 0.05, 0.02), stone,
                        bevel=0.02)
        elif piece == 'esquina':
            bricks(-hw + 0.05, -hh + 0.05, hw - 0.05, -hh + 0.5)
            bricks(-hw + 0.05, -hh + 0.05, -hw + 0.5, hh - 0.15)
            rubble(6, hw * 0.4, hh * 0.4)
        elif piece == 'piso_alto':
            wood = (126, 98, 70)
            p.layer(p.rrect(-hw + 0.05, -hh + 0.05, hw - 0.05, hh - 0.05, 0.04), wood,
                    texture=0.3)
            x = -hw + 0.05
            while x < hw - 0.1:
                x += 0.22
                p.layer(p.stroke([(x, -hh + 0.08), (x, hh - 0.08)], 0.02), (82, 62, 42),
                        bevel=0.005, outline=0)
            for edge in ((-hw + 0.05, -hh + 0.05, hw - 0.05, -hh + 0.2),
                         (-hw + 0.05, hh - 0.2, hw - 0.05, hh - 0.05)):
                p.layer(p.rrect(*edge, 0.02), (96, 72, 48), bevel=0.03)
            p.layer(p.poly([(0.3, 0.1), (0.9, 0.2), (0.8, 0.8), (0.2, 0.6)]), (40, 32, 26),
                    bevel=0.0, light=0.0)
            rubble(4, hw * 0.5, hh * 0.5, 0.8)
        else:
            rubble(10, hw * 0.55, hh * 0.55)
    elif kind == 'bosque':
        tree = piece.startswith('arbol')
        greens = [(58, 92, 50), (66, 102, 56), (52, 84, 46), (74, 108, 60)]
        r_main = min(hw, hh) * (0.92 if tree else 0.86)
        p.layer(p.ellipse(-r_main, -r_main, r_main, r_main), (40, 64, 36), bevel=0.08,
                texture=0.4)
        for _ in range(9 if tree else 5):
            a, d = rnd.uniform(0, 2 * math.pi), rnd.uniform(0, r_main * 0.55)
            cx, cy = d * math.cos(a), d * math.sin(a)
            r = rnd.uniform(0.32, 0.45) * r_main
            p.layer(p.ellipse(cx - r, cy - r, cx + r, cy + r), rnd.choice(greens),
                    bevel=0.07, texture=0.45, light=0.6, outline=0.012)
    elif kind == 'crater':
        r = min(hw, hh) * 0.95
        p.layer(p.ellipse(-r, -r, r, r), (122, 104, 80), bevel=0.12, texture=0.35, light=0.6)
        ri = r * 0.72
        p.layer(p.ellipse(-ri, -ri, ri, ri), (76, 62, 48), bevel=-0.10, texture=0.35,
                outline=0)
        ri2 = r * 0.4
        p.layer(p.ellipse(-ri2, -ri2, ri2, ri2), (56, 46, 36), bevel=-0.06, texture=0.3,
                outline=0)
        rubble(7, r * 0.8, r * 0.8, 0.6)
    elif kind == 'muro_bajo':
        if piece == 'tramo':
            for x0 in (-hw, 0.0):
                p.layer(p.rrect(x0 + 0.02, -hh + 0.06, x0 + hw - 0.02, hh - 0.06, 0.06),
                        stone, bevel=0.05, texture=0.3)
        else:
            p.layer(p.ellipse(-hw + 0.03, -hh + 0.03, hw - 0.03, hh - 0.03), stone, bevel=0.05,
                    texture=0.3)
    elif kind == 'parapeto':
        sand = (176, 154, 112)
        n = 6
        for row, dy in enumerate((-0.2, 0.2)):
            for i in range(n):
                x0 = -hw + i * w_in / n + (0.12 if row else 0.0)
                if x0 + w_in / n > hw + 0.01:
                    continue
                p.layer(p.rrect(x0 + 0.02, dy - 0.2, x0 + w_in / n - 0.02, dy + 0.2, 0.12),
                        sand, bevel=0.06, texture=0.35)
    elif kind == 'objetivo':
        wood = (132, 100, 62)
        p.layer(p.rrect(-0.30, -0.22, 0.30, 0.22, 0.03), wood, texture=0.3)
        for x in (-0.10, 0.10):
            p.layer(p.stroke([(x, -0.20), (x, 0.20)], 0.015), (88, 64, 40), bevel=0.005,
                    outline=0)
        for cx, cy in ((-0.27, -0.19), (0.27, -0.19), (-0.27, 0.19), (0.27, 0.19)):
            p.layer(p.rrect(cx - 0.04, cy - 0.04, cx + 0.04, cy + 0.04, 0.01), (70, 72, 76),
                    bevel=0.015)
        p.layer(p.stroke([(-0.12, -0.08), (0.12, 0.08)], 0.03), (240, 232, 210), bevel=0.0,
                outline=0)
        p.layer(p.stroke([(-0.12, 0.08), (0.12, -0.08)], 0.03), (240, 232, 210), bevel=0.0,
                outline=0)
        if piece == 'central':
            p.layer(p.stroke([(-0.32, 0.0), (-0.32, -0.46)], 0.03), (90, 66, 40), bevel=0.01)
            p.layer(p.poly([(-0.32, -0.46), (0.12, -0.40), (-0.32, -0.30)]), (226, 176, 70),
                    bevel=0.02)
    return p.finish()[0]


# ----------------------------------------------------------------- efectos

def effect_frame(effect, i, frames, canvas):
    p = Painter(canvas, canvas, canvas / 2)  # unidad = medio lienzo
    t = (i + 0.5) / frames
    rnd = random.Random(f'{effect}{i}')
    if effect == 'fogonazo':
        s = 0.5 + 0.45 * t
        fade = 1 - t
        star = p.poly([(-0.25 * s, -0.4 * s), (0.95 * s, 0), (-0.25 * s, 0.4 * s), (0.1 * s, 0)])
        p.glow(star, (255, 180, 70), blur=0.08, strength=fade)
        p.glow(p.ellipse(-0.3 * s, -0.3 * s, 0.3 * s, 0.3 * s), (255, 236, 180), blur=0.08,
               strength=fade)
    elif effect == 'humo':
        for k in range(5):
            a = k * 1.3
            d = 0.15 + 0.4 * t
            r = 0.18 + 0.35 * t
            cx, cy = d * math.cos(a), d * math.sin(a) * 0.6
            p.glow(p.ellipse(cx - r, cy - r, cx + r, cy + r), (206, 200, 190), blur=0.12,
                   strength=0.75 * (1 - t))
    elif effect == 'impacto':
        r = 0.25 + 0.6 * t
        ring = p.ellipse(-r, -r, r, r)
        p.glow(ring, (170, 140, 100), blur=0.15, strength=0.7 * (1 - t))
        for k in range(10):
            a = rnd.uniform(0, 2 * math.pi)
            d = r * rnd.uniform(0.6, 1.1)
            q = 0.04
            p.layer(p.ellipse(d * math.cos(a) - q, d * math.sin(a) - q, d * math.cos(a) + q,
                              d * math.sin(a) + q), (110, 90, 64), bevel=0.01, outline=0)
    elif effect == 'explosion':
        fire = max(0.0, 1 - t * 1.6)
        r = 0.3 + 0.62 * t
        p.glow(p.ellipse(-r, -r, r, r), (70, 62, 56), blur=0.1, strength=0.85 * (1 - t * 0.6))
        if fire > 0:
            rf = r * 0.85
            p.glow(p.ellipse(-rf, -rf, rf, rf), (240, 120, 40), blur=0.1, strength=fire)
            rc = r * 0.5
            p.glow(p.ellipse(-rc, -rc, rc, rc), (255, 220, 140), blur=0.08, strength=fire)
            rw = r * 0.22
            p.glow(p.ellipse(-rw, -rw, rw, rw), (255, 250, 230), blur=0.05, strength=fire)
        for k in range(14):
            a = rnd.uniform(0, 2 * math.pi)
            d = r * rnd.uniform(0.7, 1.15)
            q = 0.018
            p.layer(p.ellipse(d * math.cos(a) - q, d * math.sin(a) - q, d * math.cos(a) + q,
                              d * math.sin(a) + q), (60, 50, 42), bevel=0.005, outline=0)
    return p.finish()[0]


# ------------------------------------------------------------------- suelo

def ground(path, size=1024):
    """Suelo de tierra y hierba que se repite sin costuras."""
    mix = seamless_noise(size, [(6, 1.0), (14, 0.6), (40, 0.35)], 1913)
    fine = seamless_noise(size, [(128, 1.0)], 7)
    dirt = Image.new('RGB', (size, size), (98, 88, 66))
    grass = Image.new('RGB', (size, size), (70, 86, 54))
    mask = mix.point(lambda v: max(0, min(255, int((v - 110) * 3))))
    img = Image.composite(grass, dirt, mask)
    shade = fine.point(lambda v: int(128 + (v - 128) * 0.5))
    img = Image.blend(img, Image.merge('RGB', [shade] * 3), 0.12)
    d = ImageDraw.Draw(img)
    rnd = random.Random(20)

    def wrapped(fn, x, y):
        for dx in (-size, 0, size):
            for dy in (-size, 0, size):
                fn(x + dx, y + dy)

    for _ in range(1600):  # matas de hierba
        x, y = rnd.uniform(0, size), rnd.uniform(0, size)
        if mask.getpixel((int(x) % size, int(y) % size)) < 90:
            continue
        col = rnd.choice([(84, 104, 62), (60, 78, 46), (96, 112, 70)])
        for _k in range(3):
            a = rnd.uniform(-2.4, -0.7)
            ln = rnd.uniform(5, 11)
            wrapped(lambda X, Y: d.line([(X, Y), (X + ln * math.cos(a), Y + ln * math.sin(a))],
                                        fill=col, width=2), x, y)
    for _ in range(500):  # piedrecillas
        x, y = rnd.uniform(0, size), rnd.uniform(0, size)
        r = rnd.uniform(1.5, 3.5)
        col = rnd.choice([(132, 124, 110), (112, 104, 92), (150, 140, 124)])
        wrapped(lambda X, Y: d.ellipse([X - r, Y - r, X + r, Y + r], fill=col), x, y)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def _job(job):
    family, args = job
    if family == 'troops':
        faction, profile, state = args
        fig, team = troop(profile, faction, state)
        folder = OUT / 'troops' / faction
        folder.mkdir(parents=True, exist_ok=True)
        fig.save(folder / f'{profile}_{state}.png')
        team.save(folder / f'{profile}_{state}_mask.png')
        return 2
    if family == 'terrain':
        kind, piece, w_in, h_in = args
        path = OUT / 'terrain' / kind / f'{piece}.png'
        path.parent.mkdir(parents=True, exist_ok=True)
        terrain_piece(kind, piece, w_in, h_in).save(path)
        return 1
    if family == 'effects':
        effect, i, frames, canvas = args
        path = OUT / 'effects' / f'{effect}_{i:02d}.png'
        path.parent.mkdir(parents=True, exist_ok=True)
        effect_frame(effect, i, frames, canvas).save(path)
        return 1
    ground(OUT / 'ground' / 'tierra.png')
    return 0


def main():
    from multiprocessing import Pool
    only = set(sys.argv[1:]) or {'troops', 'terrain', 'effects', 'ground'}
    jobs = []
    if 'troops' in only:
        jobs += [('troops', (f, p, s)) for f in SPEC['factions']
                 for p, info in SPEC['troops'].items() for s in info['states']]
    if 'terrain' in only:
        jobs += [('terrain', (k, p, w, h)) for k, pieces in SPEC['terrain'].items()
                 for p, (w, h) in pieces.items()]
    if 'effects' in only:
        jobs += [('effects', (e, i, info['frames'], info['canvas']))
                 for e, info in SPEC['effects'].items() for i in range(info['frames'])]
    if 'ground' in only:
        jobs.append(('ground', ()))
    with Pool() as pool:
        count = sum(pool.map(_job, jobs))
    print(f'Arte provisional: {count} piezas generadas en {OUT} ({", ".join(sorted(only))})')


if __name__ == '__main__':
    main()
