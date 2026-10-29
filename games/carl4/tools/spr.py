"""spr — text-grid pixel sprite helpers for CARL 4's billboard characters.

Parts are hand-drawn grids ('.' clear). Characters are composed per frame from parts, then the silhouette
gets a 1px plum outline. Two facings are drawn: 'se' (front three-quarter, facing screen-right) and
'ne' (back three-quarter, facing away to screen-right); the game mirrors them for the other two.
"""
import os, json
from PIL import Image, ImageDraw


def G(text):
    rows = [r for r in text.strip('\n').split('\n')]
    rows = [r.split('|', 1)[1] if '|' in r else r for r in rows]
    w = max(len(r.rstrip()) for r in rows)
    return [list(r.rstrip().ljust(w, '.').replace(' ', '.')) for r in rows]


def blank(w, h): return [['.'] * w for _ in range(h)]
def copy(g): return [r[:] for r in g]
def flip(g): return [r[::-1] for r in g]


def stamp(dst, src, x, y):
    if src is None: return dst
    for j, row in enumerate(src):
        for i, c in enumerate(row):
            if c == '.': continue
            xx, yy = x + i, y + j
            if 0 <= yy < len(dst) and 0 <= xx < len(dst[0]):
                dst[yy][xx] = '.' if c == '_' else c
    return dst


def rect(g, x, y, w, h, c):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 <= yy < len(g) and 0 <= xx < len(g[0]): g[yy][xx] = c


def outline(g, c='o'):
    H, W = len(g), len(g[0])
    src = copy(g)
    for y in range(H):
        for x in range(W):
            if src[y][x] != '.': continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= x + dx < W and 0 <= y + dy < H and src[y + dy][x + dx] not in '.':
                    g[y][x] = c
                    break
    return g


def rot90(g, cw=True):
    H, W = len(g), len(g[0])
    if cw: return [[g[H - 1 - x][y] for x in range(H)] for y in range(W)]
    return [[g[x][W - 1 - y] for x in range(H)] for y in range(W)]


def shift(g, dx, dy):
    H, W = len(g), len(g[0]); n = blank(W, H)
    for y in range(H):
        for x in range(W):
            sx, sy = x - dx, y - dy
            if 0 <= sx < W and 0 <= sy < H: n[y][x] = g[sy][sx]
    return n


def rgba(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def to_img(g, legend):
    H, W = len(g), len(g[0]); im = Image.new('RGBA', (W, H)); p = im.load()
    for y in range(H):
        for x in range(W):
            c = g[y][x]
            if c == '.': continue
            p[x, y] = rgba(legend[c]) if c in legend else (255, 0, 255, 255)
    return im


def sheet(frames, legend, out, k=5, cols=12, bg=(150, 128, 104)):
    w, h = len(frames[0][1][0]), len(frames[0][1])
    cols = min(cols, len(frames)); rows = (len(frames) + cols - 1) // cols
    pad, lab = 4, 11
    S = Image.new('RGBA', (pad + cols * (w * k + pad), pad + rows * (h * k + pad + lab) + h + pad * 2), bg + (255,))
    d = ImageDraw.Draw(S)
    for i, (name, g) in enumerate(frames):
        im = to_img(g, legend).resize((w * k, h * k), Image.NEAREST)
        x0, y0 = pad + (i % cols) * (w * k + pad), pad + (i // cols) * (h * k + pad + lab)
        S.alpha_composite(im, (x0, y0)); d.text((x0, y0 + h * k), name, fill=(255, 245, 230))
    yb = pad + rows * (h * k + pad + lab)
    for i, (name, g) in enumerate(frames[:cols * 2]):
        S.alpha_composite(to_img(g, legend), (pad + i * (w + 2), yb))
    S.save(out)


def gif(frames, legend, out, ms, k=6, bg=(150, 128, 104)):
    ims = []
    for g in frames:
        im = to_img(g, legend); b = Image.new('RGBA', im.size, bg + (255,)); b.alpha_composite(im)
        ims.append(b.resize((im.width * k, im.height * k), Image.NEAREST).convert('RGB'))
    ims[0].save(out, save_all=True, append_images=ims[1:], duration=ms, loop=0)


def check(name, g, w=None):
    widths = {len(r) for r in g}
    if w and max(widths) > w: print(f'WARN {name}: width {max(widths)} > {w}')
    return g
