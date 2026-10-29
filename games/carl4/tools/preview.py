import sys, importlib; sys.path.insert(0,'.')
from spr import *
mod = importlib.import_module(sys.argv[1]); out = sys.argv[2]; pref = sys.argv[3] if len(sys.argv)>3 else ''
frames, anims = mod.build()
L = mod.LEGEND
sel = [(n, g) for n,(g,h,p) in frames.items() if n.startswith(pref)]
sheet(sel, L, out + '_sheet.png', k=5, cols=12)
for a, d in anims.items():
    if a.startswith(pref) and a.endswith(tuple(sys.argv[4].split(','))) if len(sys.argv)>4 else a.startswith(pref):
        gif([frames[n][0] for n in d['frames']], L, f'{out}_{a}.gif', d['ms'])
