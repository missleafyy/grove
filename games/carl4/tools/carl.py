"""Builds Carl's sprite frames from carl_parts. Keys are hand-placed per frame (no rig): body bob, head lag,
lean, which hand-drawn arm and shoe stamps to use, and where each foot lands."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from spr import *
from carl_parts import *

W, H = 40, 36
OX = 4
SOLE, HIP = 33, 26
SHOULDER = {'se': ((14, 19), (25, 19)), 'ne': ((25, 19), (14, 19))}
HIPX = {'se': (16, 20), 'ne': (21, 16)}       # near, far hip x


def line(g, x0, y0, x1, y1, c1, c2):
    """2px-wide limb segment: c1 on the left column, c2 on the right."""
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    for s in range(n + 1):
        x = round(x0 + (x1 - x0) * s / n); y = round(y0 + (y1 - y0) * s / n)
        if 0 <= y < H:
            if 0 <= x < W: g[y][x] = c1
            if 0 <= x + 1 < W: g[y][x + 1] = c2


def leg(g, hx, foot, knee_dx=0, bob=0):
    """foot = (x, shoe, sole_row). Draws hip -> knee -> ankle, then the shoe."""
    x, shoe, sole = foot
    ay = sole - 2
    hy = HIP + bob
    ky = (hy + ay) // 2
    kx = (hx + x) // 2 + knee_dx
    line(g, hx, hy, kx, ky, 'P', 'p')
    line(g, kx, ky, x, ay, 'P', 'p')
    stamp(g, SHOE[shoe], x, ay)


def compose(f, arms=('hang', 'hang'), near=None, far=None, bob=0, head=0, lean=0, eyes='open', mouth='shut',
            knees=(0, 0), extra=None, head_dx=0):
    g = blank(W, H)
    nh, fh = HIPX[f]
    if near is None: near = (nh - 1, 'plant' if f == 'se' else 'back', SOLE)
    if far is None: far = (fh, 'plant' if f == 'se' else 'back', SOLE)
    sh = SHOULDER[f]
    hand = [None, None]

    def arm(k, s, i):
        if k is None: return
        a, (ax, ay), (hx, hy) = ARM[k]
        x0, y0 = s[0] + lean - ax, s[1] + bob - ay
        stamp(g, a, x0, y0)
        hand[i] = (x0 + hx, y0 + hy)

    arm(arms[1], sh[1], 1)
    leg(g, fh, far, knees[1], bob)
    leg(g, nh, near, knees[0], bob)
    stamp(g, TORSO[f], 13 + lean, 17 + bob)
    hd = copy(HEAD[f])
    if f == 'se':
        for eg, ex, ey in EYES[eyes]: stamp(hd, eg, ex, ey)
        mg, mx, my = MOUTH[mouth]; stamp(hd, mg, mx, my)
    stamp(g, hd, 11 + lean + head_dx, 0 + bob + head)
    arm(arms[0], sh[0], 0)
    if extra: extra(g)
    return outline(g), hand[0]


# ------------------------------------------------------------------ animation tables
RUN_SE = [  # near foot, far foot, bob, knee bends, arms (near, far)
    ((19, 'plant', 33), (12, 'toe', 33), 0, (0, 0), ('back', 'fwd')),
    ((18, 'plant', 33), (12, 'heel', 31), 1, (1, -1), ('back', 'fwd')),
    ((16, 'plant', 33), (15, 'lift', 30), 0, (1, 2), ('hang', 'hang')),
    ((14, 'toe', 33), (18, 'lift', 31), -1, (0, 2), ('fwd', 'back')),
    ((13, 'toe', 33), (21, 'plant', 33), 0, (0, 0), ('fwd', 'back')),
    ((12, 'heel', 31), (20, 'plant', 33), 1, (-1, 1), ('fwd', 'back')),
    ((15, 'lift', 30), (18, 'plant', 33), 0, (2, 1), ('hang', 'hang')),
    ((18, 'lift', 31), (16, 'toe', 33), -1, (2, 0), ('back', 'fwd')),
]
RUN_NE = [
    ((22, 'back', 33), (15, 'back_heel', 31), 0, (0, 0), ('back', 'fwd')),
    ((22, 'back', 33), (15, 'back_heel', 30), 1, (0, 0), ('back', 'fwd')),
    ((21, 'back', 33), (16, 'back_heel', 31), 0, (0, 0), ('hang', 'hang')),
    ((21, 'back_heel', 32), (16, 'back', 33), -1, (0, 0), ('fwd', 'back')),
    ((21, 'back_heel', 31), (15, 'back', 33), 0, (0, 0), ('fwd', 'back')),
    ((21, 'back_heel', 30), (15, 'back', 33), 1, (0, 0), ('fwd', 'back')),
    ((21, 'back_heel', 31), (16, 'back', 33), 0, (0, 0), ('hang', 'hang')),
    ((22, 'back', 33), (16, 'back_heel', 32), -1, (0, 0), ('back', 'fwd')),
]


def glow(g, x, y, big):
    stamp(g, G("""
.F.
FfF
.F.
""") if not big else G("""
..F..
.FfF.
FffFF
.FfF.
..F..
"""), x - (1 if not big else 2), y - (1 if not big else 2))


def build():
    frames = {}   # name -> (grid, hand, gun pose)
    anims = {}

    def add(anim, name, grid_hand, pose, ms, loop=True):
        g, hd = grid_hand
        frames[name] = (g, hd, pose)
        a = anims.setdefault(anim, {'frames': [], 'ms': [], 'loop': loop})
        a['frames'].append(name); a['ms'].append(ms)

    for f in ('se', 'ne'):
        low = f + '_low'
        aimp = 'se_aim' if f == 'se' else 'ne_aim'
        aim_arm = 'aim' if f == 'se' else 'aim_ne'
        RUN = RUN_SE if f == 'se' else RUN_NE
        # idle: breathe (head lags the body by a frame), blink near the end
        idle = [(0, 0, 'open'), (0, 0, 'open'), (1, 0, 'open'), (1, 1, 'open'), (1, 1, 'open'), (0, 1, 'half'), (0, 0, 'shut'), (0, 0, 'half')]
        ims = [420, 300, 380, 420, 300, 70, 90, 70]
        for i, (bob, lag, eyes) in enumerate(idle):
            add(f + '_idle', f'{f}_idle{i}', compose(f, ('hang', 'hang'), bob=bob, head=lag - bob, eyes=eyes), low, ims[i])
        for i, (n, fa, bob, kn, arms) in enumerate(RUN):
            add(f + '_run', f'{f}_run{i}', compose(f, arms, n, fa, bob=bob, head=1 if bob < 0 else 0, knees=kn, lean=1), low, 75)
            add(f + '_aimrun', f'{f}_aimrun{i}', compose(f, (aim_arm, 'fwd' if f == 'se' else 'hang'), n, fa, bob=bob, knees=kn), aimp, 75)
        # aim / fire: snap back a pixel and squint on the shot, settle over two frames
        add(f + '_aim', f'{f}_aim0', compose(f, (aim_arm, 'fwd' if f == 'se' else 'hang'), eyes='focus'), aimp, 500)
        add(f + '_aim', f'{f}_aim1', compose(f, (aim_arm, 'fwd' if f == 'se' else 'hang'), bob=1, head=-1, eyes='focus'), aimp, 500)
        add(f + '_fire', f'{f}_fire0', compose(f, (aim_arm, 'fwd' if f == 'se' else 'hang'), lean=-1, head=-1, eyes='half', mouth='grit'), aimp, 50, loop=False)
        add(f + '_fire', f'{f}_fire1', compose(f, (aim_arm, 'fwd' if f == 'se' else 'hang'), lean=-1, eyes='half', mouth='grit'), aimp, 60, loop=False)
        add(f + '_fire', f'{f}_fire2', compose(f, (aim_arm, 'fwd' if f == 'se' else 'hang')), aimp, 90, loop=False)
        # reload: gun tips up to the chest, other hand yanks the mag, slaps it home
        rl = [('chest', 'hang', 0, 'open', 120), ('chest', 'back', 1, 'open', 160), ('chest', 'chest', 1, 'open', 200),
              ('chest', 'chest', 0, 'wide', 90), ('chest', 'fwd', 0, 'open', 120)]
        for i, (a0, a1, bob, e, ms) in enumerate(rl):
            add(f + '_reload', f'{f}_reload{i}', compose(f, (a0, a1), bob=bob, eyes=e), f + '_tilt', ms)
        # jump: crouch, launch (stretched legs), tuck, fall, land squash
        add(f + '_jump', f'{f}_jump0', compose(f, ('back', 'back'), bob=2, head=1, knees=(2, 2),
            near=(HIPX[f][0] - 1, 'plant' if f == 'se' else 'back', 33), far=(HIPX[f][1], 'plant' if f == 'se' else 'back', 33)), low, 60, loop=False)
        add(f + '_jump', f'{f}_jump1', compose(f, ('up', 'up'), bob=-2, head=1, eyes='wide',
            near=(HIPX[f][0] - 1, 'toe' if f == 'se' else 'back_heel', 33), far=(HIPX[f][1], 'toe' if f == 'se' else 'back_heel', 32)), low, 120, loop=False)
        add(f + '_air', f'{f}_air0', compose(f, ('out', 'out'), bob=-1, knees=(2, 3),
            near=(HIPX[f][0], 'lift' if f == 'se' else 'back_heel', 31), far=(HIPX[f][1] + 1, 'lift' if f == 'se' else 'back_heel', 30)), low, 140)
        add(f + '_air', f'{f}_air1', compose(f, ('out', 'out'), bob=-1, head=-1, knees=(2, 3),
            near=(HIPX[f][0], 'lift' if f == 'se' else 'back_heel', 31), far=(HIPX[f][1] + 1, 'lift' if f == 'se' else 'back_heel', 30)), low, 140)
        add(f + '_land', f'{f}_land0', compose(f, ('out', 'out'), bob=2, head=1, knees=(-1, 1),
            near=(HIPX[f][0] - 2, 'plant' if f == 'se' else 'back', 33), far=(HIPX[f][1] + 1, 'plant' if f == 'se' else 'back', 33)), low, 70, loop=False)
        add(f + '_land', f'{f}_land1', compose(f, ('hang', 'hang'), bob=1), low, 80, loop=False)
        # hover: arms up, feet paddling, eyes wide
        for i in range(4):
            add(f + '_hover', f'{f}_hover{i}', compose(f, ('up', 'up'), bob=-1 + (i % 2), eyes='wide', mouth='open' if i < 2 else 'shut',
                near=(HIPX[f][0] - (i % 2), 'toe' if f == 'se' else 'back_heel', 32 - (i % 2)),
                far=(HIPX[f][1] + ((i + 1) % 2), 'toe' if f == 'se' else 'back_heel', 31 + (i % 2))), low, 110)
        # dash: lean hard into it, arms trail
        add(f + '_dash', f'{f}_dash0', compose(f, ('back', 'back'), lean=2, head=1, bob=1, eyes='half', knees=(2, 0),
            near=(HIPX[f][0] + 3, 'lift' if f == 'se' else 'back_heel', 31), far=(HIPX[f][1] - 4, 'toe' if f == 'se' else 'back', 33)), low, 220, loop=False)
        # melee: wind-up, smack, follow through
        add(f + '_melee', f'{f}_melee0', compose(f, ('back', 'hang'), lean=-1, head=-1, eyes='half', mouth='grit'), None, 70, loop=False)
        add(f + '_melee', f'{f}_melee1', compose(f, ('punch' if f == 'se' else 'aim_ne', 'back'), lean=2, eyes='wide', mouth='open',
            near=(HIPX[f][0] + 2, 'plant' if f == 'se' else 'back', 33)), None, 130, loop=False)
        add(f + '_melee', f'{f}_melee2', compose(f, ('fwd', 'hang'), lean=1, eyes='open'), None, 120, loop=False)
        # tractor beam: off hand reaches out, glow flickers
        for i in range(2):
            def fx(g, i=i, f=f):
                pass
            add(f + '_tractor', f'{f}_tractor{i}', compose(f, ('reach' if f == 'se' else 'aim_ne', 'hang'), bob=i, eyes='wide', mouth='open'), None, 90)
        # hurt
        add(f + '_hurt', f'{f}_hurt0', compose(f, ('flail', 'flail'), lean=-2, head=-1, eyes='hurt', mouth='open'), low, 90, loop=False)
        add(f + '_hurt', f'{f}_hurt1', compose(f, ('hang', 'flail'), lean=-1, eyes='hurt', mouth='grit'), low, 120, loop=False)
        # talk (dialogue): mouth flaps
        for i, (m, e) in enumerate([('open', 'open'), ('shut', 'open'), ('open', 'wide'), ('shut', 'open')]):
            add(f + '_talk', f'{f}_talk{i}', compose(f, ('hang', 'fwd' if i % 2 else 'hang'), bob=i % 2, eyes=e, mouth=m), low, 110)
        # death: recoil, buckle, topple (rotated whole body), bounce, still
        g0, _ = compose(f, ('flail', 'flail'), lean=-2, head=-1, eyes='hurt', mouth='open')
        add(f + '_die', f'{f}_die0', (g0, None), None, 110, loop=False)
        g1, _ = compose(f, ('hang', 'hang'), bob=3, head=1, eyes='shut', knees=(3, 3))
        add(f + '_die', f'{f}_die1', (g1, None), None, 150, loop=False)
        lay = rot90(compose(f, ('up', 'up'), eyes='shut', mouth='open')[0], cw=(f == 'se'))
        # rotated grid is 40 tall x 36 wide: keep the opaque rows, pad to the canvas width, drop it on the ground
        rows = [r + ['.'] * (W - len(r)) for r in lay if any(c != '.' for c in r)]
        g2 = blank(W, H); stamp(g2, rows, 0, SOLE - len(rows) + 1 - 2)
        add(f + '_die', f'{f}_die2', (g2, None), None, 90, loop=False)
        g3 = blank(W, H); stamp(g3, rows, 0, SOLE - len(rows) + 1)
        add(f + '_die', f'{f}_die3', (g3, None), None, 900, loop=False)
    return frames, anims
