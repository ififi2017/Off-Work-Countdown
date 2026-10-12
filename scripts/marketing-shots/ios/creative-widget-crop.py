"""Locate the existing native Home Screen preview; no UI regeneration."""
from PIL import Image,ImageChops
import sys,json
im=Image.open(sys.argv[1]).convert('RGB');r,g,b=im.split()
m=ImageChops.multiply(ImageChops.multiply(ImageChops.subtract(r,g).point(lambda x:255 if x>15 else 0),ImageChops.subtract(b,g).point(lambda x:255 if x>10 else 0)),g.point(lambda x:255 if x<140 else 0))
box=m.getbbox()
if not box or m.histogram()[255]<20000:raise SystemExit('Native widget preview not ready')
x,y,right,bottom=box
print(json.dumps({'x':x,'y':y,'w':right-x,'h':bottom-y}))
