"""White Suits, Postal Inspectors and HU-MAN — hand-drawn parts on a 40x50 canvas (sole on row 47).

Shared letters:  skin S s q (light, mid, shadow)   hair r R   cloth C c K (light, mid, dark)
                 shirt t   tie/trim k   belt u   shades x   lens glint X   mouth m
                 trousers J j   shoes Z z   gun B b M   fx F f
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from spr import *

W0, W, H = 40, 52, 50
SOLE, HIP = 47, 26

PAL = {
    'suit': {
        'o': '#1c1428', 'S': '#f2c7a0', 's': '#d79c78', 'q': '#a86c56', 'r': '#3a2a24', 'R': '#5c4436',
        'C': '#f4f1ea', 'c': '#cfcabf', 'K': '#9b95a6', 't': '#1c1a22', 'k': '#d8433b', 'u': '#1c1a22',
        'x': '#14121a', 'X': '#8ea8c8', 'm': '#7a3a34', 'J': '#e9e5dc', 'j': '#bdb7ad', 'Z': '#1b1820', 'z': '#3a3640',
        'B': '#3a3f4a', 'b': '#1f2229', 'M': '#6a707c', 'F': '#fff3b8', 'f': '#ffae42',
    },
    'postal': {
        'o': '#1c1428', 'S': '#c98e68', 's': '#a86c4e', 'q': '#7c4c3a', 'r': '#22202a', 'R': '#2f4a8a',
        'C': '#3e5ca0', 'c': '#2a4078', 'K': '#18264a', 't': '#e8e6de', 'k': '#d8433b', 'u': '#7a5a2a',
        'x': '#14121a', 'X': '#8ea8c8', 'm': '#5a2a24', 'J': '#2a3a66', 'j': '#1a264a', 'Z': '#1b1820', 'z': '#3a3640',
        'B': '#7a4a24', 'b': '#4a2c16', 'M': '#4a4e58', 'F': '#fff3b8', 'f': '#ffae42',
    },
    'human': {
        'o': '#1c1428', 'S': '#f0b48a', 's': '#cf8c66', 'q': '#9a5c44', 'r': '#141019', 'R': '#2b2434',
        'C': '#3a3649', 'c': '#23202d', 'K': '#100e16', 't': '#e7b53b', 'k': '#f6d43a', 'u': '#e7b53b',
        'x': '#0c0a10', 'X': '#d8e8ff', 'm': '#8a4a3a', 'J': '#4a6aa8', 'j': '#2f4a80', 'Z': '#efebe2', 'z': '#aaa4b8',
        'B': '#c9ced6', 'b': '#7d8594', 'M': '#4ff0d8', 'F': '#fff3b8', 'f': '#ffae42',
    },
}

# ------------------------------------------------------------------ heads (12 wide)
HEADS = {
    'suit': {
        'se': G("""
...rrrrr....
..rRRrrrrr..
.rrrrrrrrrr.
.rrSSSSSssr.
.rSSSSSSSsq.
.sxxxxSxxxq.
.SxXxxSxXxq.
.SSSSSSSssq.
..SSSmmmsq..
..SSSSSsqq..
...ssssqq...
"""),
        'ne': G("""
...rrrrr....
..rRRrrrrr..
.rRrrrrrrrr.
.rrrrrrrrrr.
.rrrrrrrrrq.
.rrrrrrrrsq.
.SrrrrrrSsq.
.SSrrrrSSsq.
..SSSSSSsq..
..SSSSSsqq..
...ssssqq...
"""),
    },
    'postal': {
        'se': G("""
...RRRRRR...
..RRCCCRRRR.
.RRRRRtRRRR.
.KKKKKKKKKKKKK
.rSSSSSSssr.
.SSxxSSSxxq.
.SSSSSSSSsq.
.SSSSSSSssq.
..SSSmmmsq..
..SSSSSsqq..
...ssssqq...
"""),
        'ne': G("""
...RRRRRR...
..RRRRRRRRR.
.RRRRRRRRRR.
KKKKKKKKKKK.
.rrrrrrrrrr.
.rrrrrrrrsq.
.SrrrrrrSsq.
.SSrrrrSSsq.
..SSSSSSsq..
..SSSSSsqq..
...ssssqq...
"""),
    },
    'human': {
        'se': G("""
...rrrrrr...
..rRRRrrrr..
.rrrrrrrrrrrrr
.SSSSSSSSSsq.
SSSSSSSSSSsq.
SxxxxxSxxxxq.
SxXxxxSxXxxq.
SSSSSSSSSssq.
SSSSSmmmmssq.
SSSSSSSSSssq.
.SSSSSSSssq..
"""),
        'ne': G("""
...rrrrrr...
..rRRRrrrr..
rrrrrrrrrrr.
.rrrrrrrrrsq
.rrrrrrrrrsq
.SrrrrrrrSsq
.SSSSSSSSSsq
.SSSSSSSSSsq
.SSSSSSSSssq
.SSSSSSSSssq
..SSSSSSssq.
"""),
    },
}
MOUTHS = {'shut': None, 'open': G("mmm\nm.m"), 'yell': G("mmmm\nmmmm")}

# ------------------------------------------------------------------ torsos (16 wide, top = canvas row 11)
TORSOS = {
    'suit': {
        'se': G("""
......Ssq.......
...CCCttkCCc....
..CCCCtkkCCCcK..
.CCCCCtkkCCCCcK.
.CCCCCCkkCCCCcK.
.CCCCCCkCCCCCcK.
.CCCCCCcCCCCCcK.
.CCCcCCcCCCCCcK.
.CCCCCCcCCCCCcK.
.CCCCCCcCCCCcKK.
..CCCCCcCCCCcK..
..uuuuuuuuuuuu..
..CCCCCCCCCCcK..
..CCCCCcCCCCcK..
"""),
        'ne': G("""
......SSq.......
...CCCCCCCCc....
..CCCCCCCCCCcK..
.CCCCCCCCCCCCcK.
.CCCCCCCCCCCCcK.
.CCCCCCcCCCCCcK.
.CCCCCCcCCCCCcK.
.CCCCCCcCCCCCcK.
.CCCCCCcCCCCCcK.
.CCCCCCcCCCCcKK.
..CCCCCcCCCCcK..
..uuuuuuuuuuuu..
..CCCCCCCCCCcK..
..CCCCCcCCCCcK..
"""),
    },
    'postal': {
        'se': G("""
......Ssq.......
...CCCttkCCc....
..CCCCtkkCCCuK..
.CCttCCkkCCuCcK.
.CCttCCkkCuCCcK.
.CCCCCCkCuCCCcK.
.CCCCCCcuCCCCcK.
.CCCCCCuCCCCCcK.
.CCCCCuCCCCCCcK.
.CCCCuCcCCCCcKK.
..CCuCCcCCCCcK..
..uuuuuuuuuuuu..
..JJJJJJJJJJjj..
..JJJJJjJJJJjj..
"""),
        'ne': G("""
......SSq.......
...CCCCCCCCc....
..CCuCCCCCCCcK..
.CCCCuCCCCCCCcK.
.CCCCCuCCCCCCcK.
.CCCCCCuCCCCCcK.
.CCCCCCcuCCCCcK.
.CCCCCCcCuCCCcK.
.CCCCCCcCCuCCcK.
.CCCCCCcCCCuCKK.
..CCCCCcCCCCuK..
..uuuuuuuuuuuu..
..JJJJJJJJJJjj..
..JJJJJjJJJJjj..
"""),
    },
    'human': {
        'se': G("""
.....tSSsq......
...CtCkkkCtc....
..CCCCCkCtCCcK..
.CCCCCCCCtCCCcK.
.CCCttCCCtCCCcK.
.CCCttCCCtCCCcK.
.CCCCCCCCtCCCcK.
.CCCCKKKKtKKCcK.
.CCCCKccctccKcK.
.CCCCCCCCtCCcKK.
..CCCCCCCtCCcK..
..tttttttttttt..
..JJJJJJJJJJjj..
..JJJJJjJJJJjj..
"""),
        'ne': G("""
.....tSSq.......
...tCCCCCCtc....
..CCCCCCCCCCcK..
.CCCCCCCCCCCCcK.
.CCCCCCCCCCCCcK.
.CCCCCCCCCCCCcK.
.CCCCCCCCCCCCcK.
.CCCCCCCCCCCCcK.
.CCCCCCCCCCCCcK.
.CCCCCCCCCCCcKK.
..CCCCCCCCCCcK..
..tttttttttttt..
..JJJJJJJJJJjj..
..JJJJJjJJJJjj..
"""),
    },
}

# ------------------------------------------------------------------ arms: grid, shoulder, hand. 'u' = cuff colour.
ARMS = {
    'hang': (G("""
CCc
CCc
CCc
CCc
CcK
CcK
CcK
uuu
SSq
SSq
"""), (1, 0), (1, 9)),
    'fwd': (G("""
CCc..
.CCc.
.CCc.
..CCc
..CcK
..CcK
...uuu
...SSq
...SSq
"""), (1, 0), (4, 8)),
    'back': (G("""
..CCc
..CCc
.CCc.
.CCc.
CCc..
CcK..
uuu..
SSq..
SSq..
"""), (3, 0), (1, 8)),
    'up': (G("""
SSq
SSq
uuu
CCc
CCc
CCc
CCc
CCc
"""), (1, 7), (1, 0)),
    'flail': (G("""
...SSq
..uuu.
.CCc..
CCc...
CCc...
"""), (1, 4), (4, 0)),
    'slam': (G("""
.SSSSq
.SSSSq
.uuuu.
.CCcc.
CCCc..
CCc...
CCc...
"""), (1, 6), (3, 0)),
}
GUN_ARMS = {   # aim arms with the gun baked in (hand-drawn per variant)
    'suit': {'se': (G("""
CCCCCCcuSSBBBBBBM
CCCCCcKuSSBBBBBb.
.........Sbb.....
..........bb.....
"""), (0, 0), (16, 0)),
             'ne': (G("""
.......BM
......BBb
....SSBb.
...uSS...
..CcK....
.CCc.....
CCc......
"""), (0, 6), (8, 0))},
    'postal': {'se': (G("""
CCCCCCcuSSbBBBBBBBBBBMM
CCCCCcKuSSBBBBMMMMMMMMM
.......bbSbbb..........
"""), (0, 0), (22, 0)),
               'ne': (G("""
..........MM
........BBMM
......BBBb..
....SSBb....
...uSS......
..CcK.......
.CCc........
CCc.........
"""), (0, 7), (11, 0))},
    'human': {'se': (G("""
.........MMMMM........
CCCCCCtuSSBBBBBBBBBBMMM
CCCCCcKtSSBBBBBBBBBBbMM
........SbbbMMM........
.........bb............
"""), (0, 1), (22, 1)),
              'ne': (G("""
..........MMM
........BBBMM
......BBBBb..
....SSBBb....
...tSS.......
..CcK........
.CCc.........
CCc..........
"""), (0, 7), (12, 0))},
}

SHOE = {
    'plant': G("""
JJj..
ZZZZz
zzzzz
"""),
    'heel': G("""
JJj.
ZZZz
.zzz
"""),
    'toe': G("""
JJj..
.ZZZz
..zzz
"""),
    'lift': G("""
JJj..
ZZZZz
.zzzz
"""),
    'back': G("""
JJj.
zZZZZ
zzzzz
"""),
    'back_heel': G("""
JJj.
zZZZ
zzzz
"""),
}

SHOULDER = {'se': ((14, 13), (27, 13)), 'ne': ((27, 13), (14, 13))}
HIPX = {'se': (16, 21), 'ne': (21, 16)}


def limb(g, x0, y0, x1, y1):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for s in range(n + 1):
        x = round(x0 + (x1 - x0) * s / n); y = round(y0 + (y1 - y0) * s / n)
        for i, c in enumerate('JJj'):
            if 0 <= y < H and 0 <= x + i < len(g[0]): g[y][x + i] = c


def leg(g, hx, foot, kdx=0, bob=0):
    x, shoe, sole = foot
    ay = sole - 2
    hy = HIP + bob
    ky = (hy + ay) // 2; kx = (hx + x) // 2 + kdx
    limb(g, hx, hy, kx, ky); limb(g, kx, ky, x, ay)
    stamp(g, SHOE[shoe], x, ay)


def compose_raw(v, f, arms=('hang', 'hang'), near=None, far=None, bob=0, head=0, lean=0, mouth='shut', knees=(0, 0), flash=False):
    g = blank(W0, H)
    nh, fh = HIPX[f]
    pl = 'plant' if f == 'se' else 'back'
    near = near or (nh - 1, pl, SOLE); far = far or (fh, pl, SOLE)
    hand = [None, None]

    def arm(k, s, i):
        a, (ax, ay), (hx, hy) = GUN_ARMS[v][f] if k == 'gun' else ARMS[k]
        x0, y0 = s[0] + lean - ax, s[1] + bob - ay
        stamp(g, a, x0, y0); hand[i] = (x0 + hx, y0 + hy)

    sh = SHOULDER[f]
    arm(arms[1], sh[1], 1)
    leg(g, fh, far, knees[1], bob); leg(g, nh, near, knees[0], bob)
    stamp(g, TORSOS[v][f], 12 + lean, 11 + bob)
    hd = copy(HEADS[v][f])
    if f == 'se' and MOUTHS[mouth] is not None: stamp(hd, MOUTHS[mouth], 5, 8)
    stamp(g, hd, 14 + lean, 0 + bob + head)
    arm(arms[0], sh[0], 0)
    if flash and hand[0]:
        hx, hy = hand[0]
        fl = G("""
..F..
.FfF.
FffFFF
.FfF.
..F..
""") if f == 'se' else G("""
.F.
FfF
.F.
""")
        stamp(g, fl, hx + 1, hy - 2)
    return outline(g), hand[0]


def compose(*a, **k):
    g, hd = compose_raw(*a, **k)
    pad = (W - W0) // 2
    return [['.'] * pad + r + ['.'] * pad for r in g], (hd[0] + pad, hd[1]) if hd else None


WALK_SE = [
    ((19, 'plant', 47), (13, 'toe', 47), 0, (0, 0), ('back', 'fwd')),
    ((18, 'plant', 47), (13, 'heel', 45), 1, (1, -1), ('back', 'fwd')),
    ((16, 'plant', 47), (15, 'lift', 44), 0, (1, 2), ('hang', 'hang')),
    ((15, 'toe', 47), (18, 'lift', 45), -1, (0, 2), ('fwd', 'back')),
    ((14, 'toe', 47), (21, 'plant', 47), 0, (0, 0), ('fwd', 'back')),
    ((13, 'heel', 45), (20, 'plant', 47), 1, (-1, 1), ('fwd', 'back')),
    ((15, 'lift', 44), (18, 'plant', 47), 0, (2, 1), ('hang', 'hang')),
    ((18, 'lift', 45), (16, 'toe', 47), -1, (2, 0), ('back', 'fwd')),
]
WALK_NE = [
    ((22, 'back', 47), (15, 'back_heel', 45), 0, (0, 0), ('back', 'fwd')),
    ((22, 'back', 47), (15, 'back_heel', 44), 1, (0, 0), ('back', 'fwd')),
    ((21, 'back', 47), (16, 'back_heel', 45), 0, (0, 0), ('hang', 'hang')),
    ((21, 'back_heel', 46), (16, 'back', 47), -1, (0, 0), ('fwd', 'back')),
    ((21, 'back_heel', 45), (15, 'back', 47), 0, (0, 0), ('fwd', 'back')),
    ((21, 'back_heel', 44), (15, 'back', 47), 1, (0, 0), ('fwd', 'back')),
    ((21, 'back_heel', 45), (16, 'back', 47), 0, (0, 0), ('hang', 'hang')),
    ((22, 'back', 47), (16, 'back_heel', 46), -1, (0, 0), ('back', 'fwd')),
]


def build_variant(v, boss=False):
    frames, anims = {}, {}

    def add(anim, name, gh, ms, loop=True):
        frames[name] = (gh[0], gh[1], None)
        a = anims.setdefault(anim, {'frames': [], 'ms': [], 'loop': loop})
        a['frames'].append(name); a['ms'].append(ms)

    for f in ('se', 'ne'):
        WALK = WALK_SE if f == 'se' else WALK_NE
        for i, (bob, lag) in enumerate([(0, 0), (0, 0), (1, 0), (1, 1), (1, 1), (0, 1)]):
            add(f + '_idle', f'{f}_idle{i}', compose(v, f, ('hang', 'hang'), bob=bob, head=lag - bob), [400, 260, 380, 400, 260, 300][i])
        for i, (n, fa, bob, kn, arms) in enumerate(WALK):
            add(f + '_walk', f'{f}_walk{i}', compose(v, f, arms, n, fa, bob=bob, head=1 if bob < 0 else 0, knees=kn), 95)
            add(f + '_aimwalk', f'{f}_aimwalk{i}', compose(v, f, ('gun', 'fwd' if f == 'se' else 'hang'), n, fa, bob=bob, knees=kn), 95)
        add(f + '_aim', f'{f}_aim0', compose(v, f, ('gun', 'fwd' if f == 'se' else 'hang')), 600)
        add(f + '_aim', f'{f}_aim1', compose(v, f, ('gun', 'fwd' if f == 'se' else 'hang'), bob=1, head=-1), 500)
        add(f + '_fire', f'{f}_fire0', compose(v, f, ('gun', 'fwd' if f == 'se' else 'hang'), lean=-1, head=-1, mouth='open', flash=True), 60, loop=False)
        add(f + '_fire', f'{f}_fire1', compose(v, f, ('gun', 'fwd' if f == 'se' else 'hang'), lean=-1), 80, loop=False)
        add(f + '_fire', f'{f}_fire2', compose(v, f, ('gun', 'fwd' if f == 'se' else 'hang')), 120, loop=False)
        add(f + '_hurt', f'{f}_hurt0', compose(v, f, ('flail', 'flail'), lean=-2, head=-1, mouth='open'), 80, loop=False)
        add(f + '_hurt', f'{f}_hurt1', compose(v, f, ('hang', 'flail'), lean=-1, mouth='open'), 140, loop=False)
        for i in range(4):
            add(f + '_talk', f'{f}_talk{i}', compose(v, f, ('fwd' if i in (1, 2) else 'hang', 'hang'), bob=i % 2, mouth='open' if i % 2 == 0 else 'shut'), 120)
        # death: knocked back, knees go, topple, bounce, lie still
        add(f + '_die', f'{f}_die0', compose(v, f, ('flail', 'flail'), lean=-2, head=-1, mouth='yell'), 110, loop=False)
        add(f + '_die', f'{f}_die1', compose(v, f, ('hang', 'flail'), bob=4, head=1, knees=(4, 4), lean=-1, mouth='open'), 160, loop=False)
        lay = rot90(compose(v, f, ('up', 'up'), mouth='open')[0], cw=(f == 'se'))
        rows = [r for r in lay if any(c != '.' for c in r)]
        rows = [(r + ['.'] * W)[:W] if len(r) < W else r[(len(r) - W) // 2:(len(r) - W) // 2 + W] for r in rows]
        g2 = blank(W, H); stamp(g2, rows, 0, SOLE - len(rows) - 2)
        add(f + '_die', f'{f}_die2', (g2, None), 90, loop=False)
        g3 = blank(W, H); stamp(g3, rows, 0, SOLE - len(rows) + 1)
        add(f + '_die', f'{f}_die3', (g3, None), 1000, loop=False)
        if boss:
            # ground slam: wind up overhead, crouch, smash, recover
            add(f + '_slam', f'{f}_slam0', compose(v, f, ('slam', 'slam'), bob=-1, head=0, mouth='yell'), 260, loop=False)
            add(f + '_slam', f'{f}_slam1', compose(v, f, ('slam', 'slam'), bob=-3, head=-1, mouth='yell',
                near=(HIPX[f][0] - 1, 'toe' if f == 'se' else 'back_heel', 45), far=(HIPX[f][1], 'toe' if f == 'se' else 'back_heel', 44)), 140, loop=False)
            add(f + '_slam', f'{f}_slam2', compose(v, f, ('fwd', 'fwd'), bob=5, head=1, knees=(4, 4), mouth='open',
                near=(HIPX[f][0] - 3, 'plant' if f == 'se' else 'back', 47), far=(HIPX[f][1] + 2, 'plant' if f == 'se' else 'back', 47)), 220, loop=False)
            add(f + '_slam', f'{f}_slam3', compose(v, f, ('hang', 'hang'), bob=2, knees=(2, 2)), 180, loop=False)
            # hurl: reach back, heave forward
            add(f + '_throw', f'{f}_throw0', compose(v, f, ('up', 'back'), lean=-2, bob=1, mouth='yell'), 220, loop=False)
            add(f + '_throw', f'{f}_throw1', compose(v, f, ('fwd', 'fwd'), lean=2, mouth='open',
                near=(HIPX[f][0] + 3, 'plant' if f == 'se' else 'back', 47)), 200, loop=False)
            add(f + '_throw', f'{f}_throw2', compose(v, f, ('fwd', 'hang'), lean=1), 160, loop=False)
            # flex (intro / summon): BY THE POWER OF NEVADA
            add(f + '_flex', f'{f}_flex0', compose(v, f, ('up', 'up'), bob=-1, mouth='yell'), 300)
            add(f + '_flex', f'{f}_flex1', compose(v, f, ('up', 'up'), bob=0, head=1, mouth='open'), 300)
    return frames, anims


VARIANTS = {'suit': False, 'postal': False, 'human': True}
LEGEND = PAL['suit']


def build():
    return build_variant('suit')
