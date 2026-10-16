"""Pequeño motor de "pintura" para el arte provisional: formas con relieve
(luz arriba a la izquierda), contorno y textura, para que las piezas
parezcan miniaturas pintadas vistas desde arriba.

Cada forma es una máscara en escala de grises; `Painter.layer` la rellena con
un color, le aplica luz, sombra y contorno y la compone sobre la figura. Las
capas de color de bando se pintan además en la máscara de bando, en gris con
su sombreado: la app multiplica ese gris por el color del bando.
"""
import math
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 2  # supermuestreo


def _shift(mask, dx, dy):
    """Desplaza sin envolver (lo que sale por un borde se pierde)."""
    out = Image.new('L', mask.size, 0)
    out.paste(mask, (int(dx), int(dy)))
    return out


class Painter:
    def __init__(self, w, h, unit):
        """Lienzo de w×h px finales; `unit` = px finales de una unidad de
        dibujo (el radio de la peana en las tropas)."""
        self.W, self.H = w * SS, h * SS
        self.u = unit * SS
        self.cx, self.cy = self.W / 2, self.H / 2
        self.fig = Image.new('RGBA', (self.W, self.H), (0, 0, 0, 0))
        self.team = Image.new('RGBA', (self.W, self.H), (0, 0, 0, 0))
        self.size = (w, h)

    # -------------------------------------------------------- coordenadas
    def P(self, x, y):
        return (self.cx + x * self.u, self.cy + y * self.u)

    def box(self, x0, y0, x1, y1):
        a, b = self.P(x0, y0), self.P(x1, y1)
        return [min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])]

    def px(self, v):
        return max(1, int(v * self.u))

    # ------------------------------------------------------------ máscaras
    def mask(self):
        m = Image.new('L', (self.W, self.H), 0)
        return m, ImageDraw.Draw(m)

    def ellipse(self, x0, y0, x1, y1):
        m, d = self.mask()
        d.ellipse(self.box(x0, y0, x1, y1), fill=255)
        return m

    def rrect(self, x0, y0, x1, y1, r=0.08):
        m, d = self.mask()
        d.rounded_rectangle(self.box(x0, y0, x1, y1), radius=self.px(r), fill=255)
        return m

    def poly(self, pts):
        m, d = self.mask()
        d.polygon([self.P(x, y) for x, y in pts], fill=255)
        return m

    def stroke(self, pts, width):
        m, d = self.mask()
        d.line([self.P(x, y) for x, y in pts], fill=255, width=self.px(width), joint='curve')
        for x, y in (pts[0], pts[-1]):
            r = self.px(width) / 2
            cx, cy = self.P(x, y)
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
        return m

    # -------------------------------------------------------------- pintar
    def _noise(self):
        if not hasattr(self, '_noise_img'):
            n = Image.effect_noise((self.W // 4 + 1, self.H // 4 + 1), 40)
            self._noise_img = n.resize((self.W, self.H), Image.BILINEAR)
        return self._noise_img

    def _shade(self, mask, color, bevel, outline, light, texture):
        """Devuelve (capa, (x, y)) recortada al recuadro de la forma."""
        bbox = mask.getbbox()
        if bbox is None:
            return None, (0, 0)
        b = max(1, self.px(abs(bevel)))
        o = max(1, self.px(outline)) if outline else 0
        m = b * 2 + o * 2 + 4
        x0, y0 = max(0, bbox[0] - m), max(0, bbox[1] - m)
        x1, y1 = min(self.W, bbox[2] + m), min(self.H, bbox[3] + m)
        mask = mask.crop((x0, y0, x1, y1))
        # Luz arriba a la izquierda; en formas cóncavas (bevel < 0), al revés.
        sx = b if bevel >= 0 else -b
        hi = ImageChops.multiply(ImageChops.subtract(mask, _shift(mask, sx, sx)), mask)
        lo = ImageChops.multiply(ImageChops.subtract(mask, _shift(mask, -sx, -sx)), mask)
        hi = hi.filter(ImageFilter.GaussianBlur(b * 0.6))
        lo = lo.filter(ImageFilter.GaussianBlur(b * 0.6))
        layer = Image.new('RGB', mask.size, color)
        if texture:
            n = self._noise().crop((x0, y0, x1, y1)).point(
                lambda v: int(128 + (v - 128) * texture))
            layer = ImageChops.overlay(layer, Image.merge('RGB', [n] * 3))
        layer = layer.convert('RGBA')
        white = Image.new('RGBA', mask.size, (255, 250, 235, 0))
        white.putalpha(hi.point(lambda v: int(v * light)))
        black = Image.new('RGBA', mask.size, (20, 16, 12, 0))
        black.putalpha(lo.point(lambda v: int(v * 0.55)))
        layer.alpha_composite(white)
        layer.alpha_composite(black)
        layer.putalpha(mask)
        if o:
            ring = ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(o * 2 + 1)), mask)
            edge = Image.new('RGBA', mask.size, (22, 18, 14, 0))
            edge.putalpha(ring.point(lambda v: int(v * 0.85)))
            edge.alpha_composite(layer)
            layer = edge
        return layer, (x0, y0)

    def layer(self, mask, color, team=False, bevel=0.07, outline=0.035, light=0.55,
              texture=0.0):
        """Pinta la forma. Si `team`, va también a la máscara de bando con su
        sombreado en gris (el color lo pone la app)."""
        if team:
            grey, at = self._shade(mask, (226, 226, 226), bevel, 0, light, texture)
            if grey is not None:
                self.team.alpha_composite(grey, dest=at)
            color = (196, 190, 178)  # base neutra por si falta la máscara
        shaded, at = self._shade(mask, color, bevel, outline, light, texture)
        if shaded is None:
            return
        self.fig.alpha_composite(shaded, dest=at)
        if not team:
            # La app pinta la máscara de bando encima de toda la figura: lo
            # que una pieza posterior tapa se borra de la máscara.
            box = (at[0], at[1], at[0] + shaded.size[0], at[1] + shaded.size[1])
            region = self.team.crop(box)
            alpha = ImageChops.subtract(region.getchannel('A'), shaded.getchannel('A'))
            region.putalpha(alpha)
            self.team.paste(region, at)

    def glow(self, mask, color, blur=0.08, strength=1.0):
        """Luz sin relieve (fogonazos, brasas)."""
        m = mask.filter(ImageFilter.GaussianBlur(self.px(blur)))
        g = Image.new('RGBA', mask.size, color + (0,))
        g.putalpha(m.point(lambda v: int(v * strength)))
        self.fig.alpha_composite(g)

    def finish(self):
        w, h = self.size
        fig = self.fig.resize((w, h), Image.LANCZOS)
        team = self.team.resize((w, h), Image.LANCZOS)
        return fig, team


def lying(img, angle=-75, fade=0.55):
    """Variante "caída": tumbada, apagada y algo transparente."""
    img = img.rotate(angle, resample=Image.BICUBIC)
    r, g, b, a = img.split()
    rgb = Image.merge('RGB', (r, g, b))
    grey = rgb.convert('L').convert('RGB')
    out = Image.blend(rgb, grey, fade).convert('RGBA')
    out.putalpha(a.point(lambda v: int(v * 0.88)))
    return out


def seamless_noise(size, octaves, seed):
    """Ruido continuo que se repite sin costuras: media ponderada de octavas
    de ruido aleatorio en mosaico, ampliadas con interpolación bicúbica."""
    rnd = random.Random(seed)
    acc = None
    total = 0.0
    for cells, weight in octaves:
        tile = Image.new('L', (cells, cells))
        tile.putdata([rnd.randint(0, 255) for _ in range(cells * cells)])
        big = Image.new('L', (cells * 3, cells * 3))
        for i in range(3):
            for j in range(3):
                big.paste(tile, (i * cells, j * cells))
        up = big.resize((size * 3, size * 3), Image.BICUBIC).crop((size, size, size * 2, size * 2))
        total += weight
        acc = up if acc is None else Image.blend(acc, up, weight / total)
    return acc


def ang(deg):
    return math.radians(deg)
