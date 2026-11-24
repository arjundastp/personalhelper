"""Draws the DayMate launcher PNGs (the adaptive icon itself is the vector in res/drawable).

Usage: python3 tools/make_icon.py <res dir> [preview.png]
"""
import sys
from PIL import Image, ImageDraw

GREEN, DARK, BAND = (0, 168, 132), (0, 128, 105), (217, 253, 211)


def draw(size):
    s = size * 4  # supersample, then downscale for smooth edges
    k = s / 108
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=GREEN)
    box = lambda x0, y0, x1, y1: [x0 * k, y0 * k, x1 * k, y1 * k]
    d.rounded_rectangle(box(30, 36, 78, 79), radius=7 * k, fill='white')
    d.rounded_rectangle(box(30, 36, 78, 50), radius=7 * k, fill=BAND)
    d.rectangle(box(30, 43, 78, 47), fill=BAND)
    for x in (39.5, 61.5):
        d.rounded_rectangle(box(x, 29, x + 7, 41), radius=1.5 * k, fill='white')
    pts = [(42 * k, 62 * k), (50 * k, 70 * k), (66 * k, 54 * k)]
    d.line(pts, fill=DARK, width=int(6 * k), joint='curve')
    for p in (pts[0], pts[-1]):
        r = 3 * k
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=DARK)
    return img.resize((size, size), Image.LANCZOS)


if __name__ == '__main__':
    res = sys.argv[1]
    for folder, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        draw(px).save(f'{res}/mipmap-{folder}/ic_launcher.png')
    if len(sys.argv) > 2:
        draw(512).save(sys.argv[2])
    print('icons written')
