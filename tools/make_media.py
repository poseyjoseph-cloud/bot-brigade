"""Paint Bot Brigade's custom textures as 32-bit TGA files (power-of-two sizes for WoW 3.3.5)."""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

GOLD_HI = (232, 200, 120)
GOLD = (176, 140, 64)
GOLD_LO = (90, 66, 26)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def ring_disc(size=512):
    """Dark smoky disc with a teal heart, double gold rim, dotted inner track and an inner hub ring."""
    s = size * 2  # supersample
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    c = s / 2
    R = s / 2 - 8
    px = img.load()
    for y in range(s):
        for x in range(s):
            d = math.hypot(x - c, y - c) / R
            if d > 1:
                continue
            if d < 0.3:
                col = lerp((24, 52, 62, 200), (10, 13, 18, 214), d / 0.3)
            elif d < 0.62:
                col = lerp((10, 13, 18, 214), (8, 10, 14, 228), (d - 0.3) / 0.32)
            else:
                col = lerp((8, 10, 14, 228), (5, 6, 9, 240), (d - 0.62) / 0.38)
            px[x, y] = col
    d = ImageDraw.Draw(img)

    def circle(r, color, width):
        d.ellipse((c - r, c - r, c + r, c + r), outline=color, width=width)

    circle(R, (0, 0, 0, 255), 6)
    circle(R - 6, GOLD + (255,), 6)
    circle(R - 12, (0, 0, 0, 255), 3)
    circle(R - 17, GOLD_LO + (150,), 2)
    # dotted track
    track = R - 26
    for i in range(120):
        a = i / 120 * 2 * math.pi
        x, y = c + track * math.cos(a), c + track * math.sin(a)
        d.ellipse((x - 2.2, y - 2.2, x + 2.2, y + 2.2), fill=GOLD + (140,))
    # hub ring
    return img.resize((size, size), Image.LANCZOS)


def icon_frame(size=64):
    """Square bevelled gold frame; transparent middle. Icon sits in the inner 44/52 of the frame."""
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    b = s // 13  # border thickness ~ 4px at 52
    d.rectangle((0, 0, s - 1, s - 1), fill=(0, 0, 0, 255))
    for i in range(b - 4):
        t = i / max(1, b - 5)
        col = lerp(GOLD_HI, GOLD_LO, t) + (255,)
        d.rectangle((4 + i, 4 + i, s - 5 - i, s - 5 - i), outline=col, width=1)
    d.rectangle((b, b, s - 1 - b, s - 1 - b), fill=(0, 0, 0, 255))
    d.rectangle((b + 3, b + 3, s - 4 - b, s - 4 - b), fill=(0, 0, 0, 0))
    return img.resize((size, size), Image.LANCZOS)


def glow(size=128):
    """Soft gold halo used behind the active mode's icon (drawn with ADD blending)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = size * 0.22
    d.rounded_rectangle((m, m, size - m, size - m), radius=size * 0.06, outline=(255, 210, 60, 255), width=int(size * 0.05))
    img = img.filter(ImageFilter.GaussianBlur(size * 0.06))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((m, m, size - m, size - m), radius=size * 0.04, outline=(255, 214, 80, 255), width=int(size * 0.025))
    return img


def panel_bg(w=256, h=64):
    """Strip background: near-black with a faint vertical sheen."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        col = lerp((16, 19, 26, 232), (5, 6, 9, 240), t)
        for x in range(w):
            px[x, y] = col
    return img


ring_disc().save(os.path.join(OUT, "RingDisc.tga"))
panel_bg().save(os.path.join(OUT, "Panel.tga"))
for f in sorted(os.listdir(OUT)):
    print(f, Image.open(os.path.join(OUT, f)).size)


def round_frame(size=128):
    """Gold bevelled ring with a transparent middle. The art circle fills the inner 76% of it."""
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    c = s / 2
    outer = s / 2 - 2
    inner = outer * 0.76
    px = img.load()
    for y in range(s):
        for x in range(s):
            d = math.hypot(x - c, y - c)
            if d > outer or d < inner - 6:
                continue
            if d < inner:
                px[x, y] = (0, 0, 0, 255)          # thin black seat under the art edge
                continue
            t = (d - inner) / (outer - inner)       # 0 inner edge .. 1 outer edge
            # bevel: bright on the upper-left, darker lower-right
            light = 0.5 - 0.5 * ((x - c) + (y - c)) / (d * 1.42 + 1e-6)
            band = 1 - abs(t - 0.5) * 2
            base = lerp(GOLD_LO, GOLD_HI, max(0.0, min(1.0, 0.35 + 0.65 * light * band + 0.15 * band)))
            if t > 0.9 or t < 0.08:
                base = (12, 8, 2)
            px[x, y] = base + (255,)
    return img.resize((size, size), Image.LANCZOS)


def round_glow(size=128):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = size * 0.2
    d.ellipse((m, m, size - m, size - m), outline=(255, 205, 60, 255), width=int(size * 0.06))
    img = img.filter(ImageFilter.GaussianBlur(size * 0.05))
    d = ImageDraw.Draw(img)
    d.ellipse((m + 2, m + 2, size - m - 2, size - m - 2), outline=(255, 220, 90, 255), width=int(size * 0.025))
    return img


round_frame().save(os.path.join(OUT, "RoundFrame.tga"))
round_glow().save(os.path.join(OUT, "RoundGlow.tga"))
