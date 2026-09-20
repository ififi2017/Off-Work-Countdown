#!/usr/bin/env python3
"""Measure actual native demo card bounds; never alter screenshot pixels."""
import json
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parent
result={}
for p in sorted((ROOT/'raw').glob('*-2.png')):
 if '-ipad-' in p.name: continue
 im=Image.open(p).convert('RGB');w,h=im.size
 if (w,h)!=(1320,2868):continue
 px=im.load()
 def groups(test,minimum,lo,hi):
  rows=[]
  for y in range(lo,hi):
   xs=[x for x in range(140,w-140) if test(px[x,y])]
   if len(xs)>minimum:rows.append((y,min(xs),max(xs)))
  spans=[]
  for row in rows:
   if not spans or row[0]-spans[-1][-1][0]>30:spans.append([])
   spans[-1].append(row)
  return [(min(r[1] for r in s),s[0][0],max(r[2] for r in s)-min(r[1] for r in s)+1,s[-1][0]-s[0][0]+1) for s in spans]
 cards=[r for r in groups(lambda c:min(c)>252,400,800,2400) if r[3]>100]
 islands=[r for r in groups(lambda c:max(c)<18,250,700,1400) if 75<r[3]<150 and 400<r[2]<650]
 if len(cards)!=2 or len(islands)!=1:
  print('REVIEW',p.name,cards,islands);continue
 # Full white cards include all edges except the first antialiased rounded rows.
 # Expand only vertically, with native rounded clipping at composition time.
 result[p.stem[:-2]]={'island':[islands[0][0],islands[0][1]-2,islands[0][2],islands[0][3]+4], 'live':[cards[0][0],cards[0][1]-4,cards[0][2],cards[0][3]+8], 'widget':[cards[1][0],cards[1][1]-4,cards[1][2],cards[1][3]+8]}
(ROOT/'widget-crops.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print('Measured',len(result),'languages')
