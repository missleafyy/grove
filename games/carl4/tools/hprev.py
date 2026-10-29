import sys; sys.path.insert(0,'.')
from spr import *; import humans
out=sys.argv[1]
for v,b in humans.VARIANTS.items():
    fr,an=humans.build_variant(v,b)
    sel=[(n,g) for n,(g,h,p) in fr.items()]
    sheet(sel,humans.PAL[v],f'{out}_{v}.png',k=4,cols=14)
