"""Carl — hand-drawn parts (32x36 canvas, sole on row 33, origin [16, 34]).

Legend letters:
  cap    K k j          skin   D A a L        eye  E e i w      mouth m
  hoodie H n N          gold   G g h          bow  Y y
  pants  P p            shoe   W V R          fx   F f T t
"""
from spr import G

LEGEND = {
    'o': '#1c1428', 'K': '#141019', 'k': '#2b2434', 'j': '#4c4359',
    'D': '#1d5a52', 'A': '#2c8a74', 'a': '#4db896', 'L': '#8fe2bb',
    'E': '#0b1a10', 'e': '#2b9a2c', 'i': '#86ec58', 'w': '#ffffff', 'm': '#163a2e',
    'H': '#100e16', 'n': '#23202d', 'N': '#3a3649',
    'G': '#a26c1c', 'g': '#e7b53b', 'h': '#ffe28c',
    'Y': '#f6d43a', 'y': '#c08e1c',
    'P': '#1c1b25', 'p': '#2f2d3c',
    'W': '#efebe2', 'V': '#aaa4b8', 'R': '#5d5868',
    'F': '#fff3b8', 'f': '#ffae42',
    'T': '#c8ffe4', 't': '#3fdc8f',
}

# ------------------------------------------------------------------ heads (18 wide, top = canvas row 0)
HEAD = {
    'se': G("""
......kkkkkk......
....kkjjjkkkkk....
...kkjjkkkkkkkkk..
jjkkjkkkkkkkkkkkk.
KKKKKKKKKKKKKgKKKA
.KKLLaaaaaaaaaaaaA
.LLLaaaaaaaaaaaaaA
.LLaaaaaaaaaaaaaaA
.Laaaaaaaaaaaaaa.A
.aaaaaaaaaaaaaaaAA
.aaaaaaaaaaaaaaaA.
..aaaaaaaaaaaaaaA.
..aaaaaaaaaaaaaAA.
...aaaaaaaaaaaaA..
...AaaaaaaaaaDAA..
....AaaaaaaaaaA...
.....AAaaaaaaA....
.......AAAAA......
"""),
    'ne': G("""
......kkkkkk......
....kkjjjkkkkk....
...kjjkkkkkkkkk...
..kjkkkkkkkkkkkk..
.kkkkkkkkkkkkkkkk.
.KKKKKKKKKKKKKKKA.
jjjjjjKKKKKKKKaaA.
KKKKKKKKKKKaaaaAA.
.KKKKKKKaaaaaaaAA.
.LLLaaaaaaaaaaaAA.
.LLaaaaaaaaaaaaaA.
.Laaaaaaaaaaaaa.A.
..aaaaaaaaaaaaaAA.
...aaaaaaaaaaaAA..
....aaaaaaaaaAA...
.....AaaaaaaAA....
.......AAAAA......
"""),
}

# Eye stamps for the 'se' head: list of (grid, x, y). Near eye is big and slants up toward its outer
# (left) corner; the far eye is narrower and slants up to the right.
EYES = {
    'open': [(G("""
.ooo...
oEEEoo.
oEiieEo
oEiwEEo
.ooooo.
"""), 3, 8), (G("""
..oo.
.oEEo
oEieo
oEwEo
.ooo.
"""), 12, 8)],
    'focus': [(G("""
ooo....
oEEoo..
oEieEEo
.oEiwEo
..oooo.
"""), 3, 8), (G("""
...oo
.ooEo
oEieo
oEwEo
.ooo.
"""), 12, 8)],
    'half': [(G("""
_______
ooooo..
oEieEoo
.oEiwEo
..oooo.
"""), 3, 8), (G("""
.....
.oooo
oEieo
oEwEo
.ooo.
"""), 12, 8)],
    'shut': [(G("""
.......
.......
oooooo.
..oooo.
.......
"""), 3, 8), (G("""
.....
.....
.oooo
ooo..
.....
"""), 12, 8)],
    'hurt': [(G("""
.o.....
..o..o.
...oo..
..o..o.
.......
"""), 3, 8), (G("""
.....
.o.o.
..o..
.o.o.
.....
"""), 12, 8)],
    'wide': [(G("""
oooo...
oEEEoo.
oEiiEEo
oEiwEEo
.ooooo.
"""), 3, 7), (G("""
..ooo
.oEEo
oEiEo
oEwEo
.ooo.
"""), 12, 7)],
}
MOUTH = {'shut': (G("mm"), 9, 15), 'open': (G("mm\nmm"), 9, 14), 'grit': (G("mmm"), 8, 15)}

# ------------------------------------------------------------------ torso (14 wide, top = canvas row 17)
TORSO = {
    'se': G("""
.....gaAg.....
....gNYyYgH...
..NNnnnygnnH..
.NNnnnnngnnnH.
.NnnhnnngnnnH.
.NnnnnnngnnnH.
.NnnHHHHgHHnH.
.NnnHnnngnnHH.
..ggggggggggg.
"""),
    'ne': G("""
....gAAg......
...gNNNNgnH...
..NNnnnnnnnH..
.NNnnnnnnnnnH.
.NnnnnnnnnnnH.
.NnnnnnnnnnnH.
.NnnnnnnnnnnH.
.NnnnnnnnnnHH.
..ggggggggggg.
"""),
}

# ------------------------------------------------------------------ arms: grid, shoulder (x, y), hand (x, y)
ARM = {
    'hang': (G("""
Nn
Nn
Nn
nH
gG
aA
.a
"""), (0, 0), (0, 5)),
    'fwd': (G("""
Nn..
.Nn.
..nH
..gG
...aA
"""), (0, 0), (3, 4)),
    'back': (G("""
..Nn
.Nn.
Nn..
gG..
aA..
"""), (2, 0), (0, 4)),
    'aim': (G("""
NnnnnngGaa
nnnnnHgGaA
"""), (0, 0), (8, 0)),
    'aim_ne': (G("""
....aA
...gG.
..nH..
.Nn...
Nn....
"""), (0, 4), (4, 0)),
    'up': (G("""
.aA
.gG
.nH
Nn.
Nn.
"""), (0, 4), (1, 0)),
    'out': (G("""
.....aA
NnnngG.
nnnH...
"""), (0, 1), (5, 0)),
    'chest': (G("""
Nn...
Nnn..
.NngGa
..gGaA
"""), (0, 0), (4, 2)),
    'reach': (G("""
NnnnnngGaTt
nnnnnHgGaTT
"""), (0, 0), (9, 0)),
    'punch': (G("""
NnnnnnnggaaA
nnnnnnHgGaAA
.........aA.
"""), (0, 0), (10, 0)),
    'flail': (G("""
..aA
..gG
.Nn.
Nn..
"""), (0, 3), (2, 0)),
}

# ------------------------------------------------------------------ sneakers (stamped per frame, top row = ankle)
SHOE = {
    'plant': G("""
pP..
WWVW
RRRR
"""),
    'heel': G("""
pP.
WWV
.RR
"""),
    'toe': G("""
pP..
.WVW
..RR
"""),
    'lift': G("""
pP..
WWVW
.RRR
"""),
    'back': G("""
pP..
VWWW
RRRR
"""),
    'back_heel': G("""
pP.
VWW
RRR
"""),
}
