import sys; sys.path.insert(0,'.')
from spr import *
from carl_parts import *
W,H=32,40
def compose(f, arms=('hang','hang'), near_leg=(12,'plant',38), far_leg=(17,'plant',38), bob=0, eyes=None):
    g=blank(W,H)
    hx,tx,ty=7,9,15
    sh = {'se':((10,17),(20,17)),'ne':((21,17),(11,17))}[f]
    # far arm
    def arm(k,s):
        a,(ax,ay),_=ARM[k]; stamp(g,a,s[0]-ax,s[1]+bob-ay)
    arm(arms[1],sh[1])
    for (x,shoe,y) in (far_leg,near_leg):
        rect(g,x,25,2,y-2-25,'P'); rect(g,x+1,25,1,y-2-25,'p')
        stamp(g,SHOE[shoe],x-1,y-2)
    stamp(g,TORSO[f],tx,ty+bob)
    hd=[r[:] for r in HEAD[f]]
    if eyes and f=='se':
        for j,r in enumerate(EYES_SE[eyes]): hd[8+j]=r[:]
    stamp(g,hd,hx,0+bob)
    arm(arms[0],sh[0])
    return outline(g)
fr=[('se',compose('se')),('se_aim',compose('se',arms=('aim','back'))),('se_blink',compose('se',eyes='blink')),('ne',compose('ne')),('ne_aim',compose('ne',arms=('aim_ne','hang'))),('se_run',compose('se',arms=('fwd','back'),near_leg=(10,'plant',38),far_leg=(19,'heel',37),bob=-1))]
sheet(fr,LEGEND,'/tmp/claude-1000/-home-leafy--config-eww/c11cf423-eac4-4eb2-afa7-0dd9c1776a2e/scratchpad/carl_test.png',k=8)
