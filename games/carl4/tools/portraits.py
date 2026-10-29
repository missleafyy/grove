"""Dialogue portraits: 40x40 front-facing pixel busts with talk + blink frames.
Heads are built from shape masks (cranium, jaw) with offset-shadow shading (light from upper left),
then hand-drawn feature stamps (eyes, mouths, hats, glasses) go on top.
    python3 tools/portraits.py out.png     # preview sheet
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
from spr import *

S = 40


def mask(fn):
    return [[fn(x, y) for x in range(S)] for y in range(S)]


def paint(g, m, c):
    for y in range(S):
        for x in range(S):
            if m[y][x]: g[y][x] = c


def band(m, dx, dy):
    """Pixels of m whose neighbour at (+dx, +dy) is outside m: the rim on that side."""
    out = [[False] * S for _ in range(S)]
    for y in range(S):
        for x in range(S):
            if not m[y][x]: continue
            for k in range(1, max(abs(dx), abs(dy)) + 1):
                xx, yy = x + (dx and (k if dx > 0 else -k)), y + (dy and (k if dy > 0 else -k))
                if not (0 <= xx < S and 0 <= yy < S) or not m[yy][xx]:
                    out[y][x] = True
                    break
    return out


def shade(g, m, mid, dark, light, deep=None):
    """Mid fill, a crescent of shadow on the right/bottom, a rim light on the upper left."""
    paint(g, m, mid)
    paint(g, band(m, 3, 2), dark)
    if deep: paint(g, band(m, 1, 1), deep)
    lm = band(m, -2, -2)
    for y in range(S):
        for x in range(S):
            if lm[y][x] and x < S * 0.55 and y < S * 0.6: g[y][x] = light


def ellipse(cx, cy, rx, ry):
    return lambda x, y: ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1


def union(*fs): return lambda x, y: any(f(x, y) for f in fs)
def inter(*fs): return lambda x, y: all(f(x, y) for f in fs)
def box(x0, y0, x1, y1): return lambda x, y: x0 <= x < x1 and y0 <= y < y1


def finish(g):
    return outline(g, 'o')


# ------------------------------------------------------------------ CARL
CARL_PAL = {
    'o': '#1c1428', 'K': '#141019', 'k': '#2b2434', 'j': '#4c4359',
    'D': '#1d5a52', 'A': '#2c8a74', 'a': '#4db896', 'L': '#8fe2bb',
    'E': '#0b1a10', 'e': '#2b9a2c', 'i': '#86ec58', 'w': '#ffffff', 'm': '#163a2e',
    'n': '#23202d', 'N': '#3a3649', 'g': '#e7b53b', 'G': '#a26c1c', 'Y': '#f6d43a', 'y': '#c08e1c', 'r': '#d8433b',
}
CARL_EYE = {
    'open': G("""
..EEEE....
.EEEEEEE..
EEiieeEEE.
EEiwweEEEE
EEeweeEEEE
.EEeeEEEE.
..EEEEEE..
"""),
    'shut': G("""
..........
..........
..........
.EEEEEEEE.
..AAAAAA..
..........
..........
"""),
}


def carl(frame):
    g = blank(S, S)
    # Hoodie shoulders.
    body = union(ellipse(20, 44, 17, 10))
    shade(g, mask(body), 'n', 'K', 'N')
    rect(g, 18, 34, 4, 6, 'g'); rect(g, 19, 34, 1, 6, 'h' if False else 'Y')
    # Neck.
    paint(g, mask(box(17, 29, 23, 35)), 'A')
    # Head: wide cranium tapering to a small chin.
    cran = ellipse(20, 15, 13.5, 11)
    jaw = inter(ellipse(20, 20, 9.5, 12.5), box(0, 14, S, S))
    head = union(cran, jaw)
    shade(g, mask(head), 'a', 'A', 'L', 'D')
    # Cap (worn backwards): dome over the top, band, snap strap gap at the front.
    cap = inter(ellipse(20, 13, 14.5, 10.5), box(0, 0, S, 9))
    shade(g, mask(cap), 'k', 'K', 'j')
    rect(g, 6, 8, 28, 2, 'K')
    rect(g, 17, 7, 6, 2, 'a'); rect(g, 17, 8, 6, 1, 'A')   # strap gap shows forehead
    rect(g, 19, 1, 2, 1, 'g')
    # Eyes: big almonds, wide set, slightly tilted.
    eye = CARL_EYE['shut' if frame == 'blink' else 'open']
    stamp(g, eye, 8, 14)
    stamp(g, flip(eye) if frame == 'blink' else eye, 22, 14)
    # Mouth.
    if frame == 'talk':
        stamp(g, G("""
.mmmm.
mmEEmm
mErrEm
.mmmm.
"""), 17, 24)
    else:
        rect(g, 18, 26, 4, 1, 'm')
    # Bow tie.
    stamp(g, G("""
YY..YY
YyYYyY
YY..YY
"""), 17, 33)
    return finish(g)


# ------------------------------------------------------------------ OLD FACE
OF_PAL = {
    'o': '#071209', 'K': '#0d1a12', 'k': '#16301f', 'j': '#2a6a3c', 'J': '#5fd38a',
    'M': '#e04fb0', 'm': '#8a2a6c', 'w': '#ffd6f0', 'e': '#5fd38a', 'E': '#0d1a12',
}


def old_face(frame, t=0):
    g = blank(S, S)
    head = union(ellipse(20, 19, 13, 15), inter(ellipse(20, 24, 10, 14), box(0, 18, S, S)))
    hm = mask(head)
    paint(g, hm, 'K')
    # Wireframe: latitude + longitude lines in four greens.
    for y in range(S):
        for x in range(S):
            if not hm[y][x]: continue
            lat = (y - 4) % 6 == 0
            lon = abs(((x - 20) * 15 / max(4, 14 - abs(y - 19) * 0.45))) % 8 < 0.9
            if lat or lon: g[y][x] = 'j' if x < 20 else 'k'
    paint(g, band(hm, -1, -1), 'J')
    paint(g, band(hm, 2, 1), 'k')
    # Magenta almond eyes with a green waveform pupil.
    shut = frame == 'blink'
    for ex in (9, 23):
        if shut:
            rect(g, ex, 17, 8, 1, 'M')
        else:
            stamp(g, G("""
..MMMMM...
.MMMMMMMM.
MMEEEEEEMM
.MEEEEEEM.
..MMMMMM..
"""), ex - 1, 15)
            wave = [0, -1, 0, 1, 0, -1] if frame != 'talk' else [1, 0, -1, 0, 1, 0]
            for i, dy in enumerate(wave):
                g[17 + max(0, dy)][ex + 1 + i] = 'e'
                if dy < 0: g[16][ex + 1 + i] = 'w'
    # え nose.
    stamp(g, G("""
.JJ.
..J.
JJJJ
.JJ.
J.JJ
"""), 18, 22)
    # Mouth: a green line, or an open waveform when talking.
    if frame == 'talk':
        stamp(g, G("""
.J...J.
J.J.J.J
...J...
"""), 17, 29)
    else:
        rect(g, 17, 30, 7, 1, 'J')
    return finish(g)


# ------------------------------------------------------------------ HU-MAN
HU_PAL = {
    'o': '#1c1428', 'S': '#f0b48a', 's': '#cf8c66', 'q': '#9a5c44', 'l': '#ffd2b0',
    'H': '#141019', 'h': '#2b2434', 'x': '#0c0a10', 'X': '#d8e8ff', 'Q': '#3a3649',
    'm': '#8a4a3a', 'w': '#ffffff', 'C': '#3a3649', 'c': '#23202d', 'g': '#e7b53b', 'r': '#f6d43a',
}


def human(frame):
    g = blank(S, S)
    shade(g, mask(ellipse(20, 45, 19, 11)), 'C', 'c', 'Q')
    rect(g, 15, 35, 10, 5, 'w'); rect(g, 19, 35, 2, 5, 'r')    # shirt + yellow tie
    paint(g, mask(box(15, 29, 25, 36)), 's')
    # Square jaw: a rounded box head.
    head = union(inter(box(9, 7, 31, 32), lambda x, y: not ((x < 11 or x > 28) and (y < 9 or y > 29))),
                 box(10, 6, 30, 33))
    shade(g, mask(head), 'S', 's', 'l', 'q')
    # Chin cleft + jaw line.
    g[30][20] = 'q'; g[31][20] = 'q'
    # Slick hair with a hard part.
    hair = union(box(8, 3, 32, 10), ellipse(20, 6, 12, 4))
    shade(g, mask(hair), 'H', 'H', 'h')
    rect(g, 13, 4, 1, 6, 'h')
    rect(g, 8, 10, 2, 5, 'H'); rect(g, 30, 10, 2, 5, 'H')
    # Sunglasses: wide bar, two lenses with a white glint.
    rect(g, 9, 14, 22, 2, 'x')
    for lx in (10, 21):
        rect(g, lx, 15, 9, 4, 'x')
        rect(g, lx + 1, 15, 2, 1, 'X')
    # Big grin / talking.
    if frame == 'talk':
        stamp(g, G("""
mmmmmmmm
mwwwwwwm
.mmmmmm.
"""), 16, 24)
    else:
        stamp(g, G("""
q......q
.mwwwwm.
"""), 16, 24)
    return finish(g)


# ------------------------------------------------------------------ White Suit / Postal Inspector
SUIT_PAL = {
    'o': '#1c1428', 'S': '#f2c7a0', 's': '#d79c78', 'q': '#a86c56', 'l': '#ffe0c4',
    'r': '#3a2a24', 'R': '#5c4436', 'C': '#f4f1ea', 'c': '#cfcabf', 'K': '#9b95a6',
    'x': '#14121a', 'X': '#8ea8c8', 'm': '#7a3a34', 't': '#1c1a22', 'w': '#ffffff', 'k': '#d8433b',
}
POSTAL_PAL = dict(SUIT_PAL, **{
    'S': '#c98e68', 's': '#a86c4e', 'q': '#7c4c3a', 'l': '#e0ab84',
    'C': '#3e5ca0', 'c': '#2a4078', 'K': '#18264a', 'r': '#22202a', 'R': '#2f4a8a', 't': '#e8e6de', 'k': '#e7b53b',
})


def suit(frame, postal=False):
    g = blank(S, S)
    shade(g, mask(ellipse(20, 45, 18, 11)), 'C', 'c', 'w' if not postal else 'C', 'K')
    rect(g, 17, 35, 6, 5, 't' if not postal else 'w'); rect(g, 19, 36, 2, 4, 'k' if not postal else 't')
    paint(g, mask(box(16, 28, 24, 36)), 's')
    head = union(ellipse(20, 18, 10.5, 12.5))
    shade(g, mask(head), 'S', 's', 'l', 'q')
    if postal:
        # Peaked cap with a gold badge.
        shade(g, mask(union(ellipse(20, 8, 12, 5.5), box(8, 8, 32, 11))), 'C', 'c', 'R')
        rect(g, 7, 11, 26, 2, 'K')
        rect(g, 18, 6, 4, 3, 'k')
    else:
        shade(g, mask(inter(ellipse(20, 12, 11.5, 8.5), box(0, 0, S, 12))), 'r', 'r', 'R')
        rect(g, 9, 11, 2, 4, 'r'); rect(g, 29, 11, 2, 4, 'r')
    # Shades.
    rect(g, 11, 16, 18, 1, 'x')
    for lx in (12, 21):
        rect(g, lx, 16, 7, 3, 'x')
        g[16][lx + 1] = 'X'
    # Earpiece.
    if not postal:
        g[19][9] = 'x'; g[20][9] = 'x'
    if frame == 'talk':
        stamp(g, G("""
.mmmm.
mmwwmm
.mmmm.
"""), 17, 24)
    else:
        rect(g, 17, 25, 6, 1, 'm')
    return finish(g)


PORTRAITS = {
    'CARL': (carl, CARL_PAL),
    'OLD FACE': (old_face, OF_PAL),
    'HU-MAN': (human, HU_PAL),
    'WHITE SUIT': (lambda f: suit(f), SUIT_PAL),
    'POSTAL INSPECTOR': (lambda f: suit(f, True), POSTAL_PAL),
}
FRAMES = ['idle', 'talk', 'blink']


def build():
    out = []
    for name, (fn, pal) in PORTRAITS.items():
        for f in FRAMES:
            out.append((name, f, fn(f), pal))
    return out


if __name__ == '__main__':
    from PIL import Image
    fr = build()
    im = Image.new('RGBA', (len(FRAMES) * S, len(PORTRAITS) * S), (60, 50, 70, 255))
    for i, (n, f, g, pal) in enumerate(fr):
        im.alpha_composite(to_img(g, pal), ((i % len(FRAMES)) * S, (i // len(FRAMES)) * S))
    im = im.resize((im.width * 6, im.height * 6), Image.NEAREST)
    im.save(sys.argv[1])
