"""Gun overlay sprites held in Carl's hand. One hand-drawn side view per gun kind (pointing right, '@' = grip
pixel under the hand); the other poses are clean pixel shears of it (2:1 slopes) so steps stay even.
Every gun is recoloured per manufacturer."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from spr import *

CELL_W, CELL_H = 30, 18
KINDS = ['pistol', 'smg', 'shotgun', 'rifle', 'launcher']
POSES = ['se_aim', 'se_low', 'se_tilt', 'ne_aim', 'ne_low', 'ne_tilt']
MAKERS = {
    'Pretend Co.':              {'B': '#6a4a9a', 'b': '#3c2a5c', 'T': '#e7b53b', 'R': '#1d1c24', 'M': '#2b2140'},
    'Prop Pills Arms':          {'B': '#f2efe6', 'b': '#b9b4ac', 'T': '#d8433b', 'R': '#3a3a42', 'M': '#8a2a24'},
    'Mall of the Future':       {'B': '#c9ced6', 'b': '#7d8594', 'T': '#4ff0d8', 'R': '#23262e', 'M': '#3b4250'},
    'Sequel Committee Surplus': {'B': '#6a7646', 'b': '#3f4728', 'T': '#c9b46a', 'R': '#7d5631', 'M': '#2f3524'},
    "Garf's":                   {'B': '#e0782e', 'b': '#9a4a1c', 'T': '#d8433b', 'R': '#b98952', 'M': '#5a2a14'},
    'Postal Service':           {'B': '#2f4a8a', 'b': '#1c2c5a', 'T': '#f5f3ec', 'R': '#1b1720', 'M': '#101830'},
}
BASE = {'o': '#1c1428', 'a': '#4db896', 'A': '#2c8a74', 'g': '#e7b53b', 'F': '#fff3b8', 'f': '#ffae42', 'X': '#7de3ff'}

SIDE = {
    'pistol': G("""
.TTTT.....
BBBBBBBBBM
bBBBBBBBbM
.aAa@b....
.aA.RR....
....RR....
"""),
    'smg': G("""
.....TTTTT......
M..BBBBBBBBBBMMM
MMbBBBBBBBBBb...
M....aA@bb......
.....aARb.bb....
.......RR.bb....
"""),
    'shotgun': G("""
..........T.........
RRRRbBBBBBBBBBBBBBBM
RRRRRbBBBMMMMMMMMMMM
...RR.aA@bTTTTT.....
......aARR..........
"""),
    'rifle': G("""
.........bMMMMb.......
.........bXMMMb.......
RRRRRbBBBBBBBBBBMMMMMM
RRRRRRBBBBBBBTbb.....M
...RRR.aA@bb..........
.......aARR...........
"""),
    'launcher': G("""
...........bMb........
..MBBBBBBBBBBBBBBBTTb.
.MMBBBBBTBBBBBBBBBTTbM
MMMBBBBBTBBBBBBBBBTTbM
..MbbbbbbbbbbbbbbbTTb.
......aA@b..bR........
......aARR....R.......
"""),
}


def find(g, ch):
    for y, r in enumerate(g):
        for x, c in enumerate(r):
            if c == ch: return x, y
    return None


def shear(g, ax, ay, k, compress=1.0):
    """Shift each column vertically by floor((x - ax) * k) (negative k tilts up), optionally drop columns."""
    H, W = len(g), len(g[0])
    keep = [x for x in range(W) if compress >= 1 or (x == ax) or ((x - ax) * compress) % 1 < compress]
    out = blank(len(keep) + 2, H + 80)
    nax = keep.index(ax) + 1
    for nx, x in enumerate(keep):
        dy = int((x - ax) * k // 1) if k >= 0 else -int(((x - ax) * -k) // 1)
        for y in range(H):
            c = g[y][x]
            if c != "." and 0 <= y + 40 + dy < H + 80: out[y + 40 + dy][nx + 1] = c
    return out, (nax, ay + 40)


def pose(kind, p):
    g = copy(SIDE[kind])
    ax, ay = find(g, '@'); g[ay][ax] = 'R'
    if p == 'se_aim': out, anc = shear(g, ax, ay, 0)
    elif p == 'se_low': out, anc = shear(g, ax, ay, 0.5)
    elif p == 'se_tilt': out, anc = shear(g, ax, ay, -0.5)
    elif p == 'ne_aim': out, anc = shear(g, ax, ay, -0.5, compress=0.55)
    elif p == 'ne_low': out, anc = shear(g, ax, ay, 0.5, compress=0.55)
    else: out, anc = shear(g, ax, ay, -1.0, compress=0.55)
    out = outline(out)
    # crop to the cell around the anchor: anchor sits at (10, 9) in the cell
    cell = blank(CELL_W, CELL_H)
    stamp(cell, out, 10 - anc[0], 9 - anc[1])
    return cell


def build():
    frames, legends = [], []
    for maker, cols in MAKERS.items():
        leg = dict(BASE); leg.update(cols)
        for kind in KINDS:
            for p in POSES:
                frames.append((f'{maker}|{kind}|{p}', pose(kind, p), leg))
    return frames


if __name__ == '__main__':
    fr = build()
    out = sys.argv[1]
    imgs = [(n, g) for n, g, l in fr[:30]]
    sheet(imgs, fr[0][2], out, k=6, cols=6)
