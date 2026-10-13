"""Score actual widget countdown pixels, excluding permission overlays."""
from pathlib import Path
from PIL import Image, ImageStat, ImageFilter
import json, subprocess, sys

def score(path):
    im=Image.open(path).convert('L');w,h=im.size
    if ImageStat.Stat(im.crop((0,h*.15,w*.02,h*.5))).mean[0]<220:
        return 0
    crop=json.loads(subprocess.check_output([sys.executable,str(Path(__file__).with_name('creative-widget-crop.py')),str(path)]))
    x,y,cw,ch=(crop[k] for k in ['x','y','w','h'])
    digits=im.crop((x+cw*.16,y+ch*.28,x+cw*.86,y+ch*.50))
    return ImageStat.Stat(digits.filter(ImageFilter.FIND_EDGES)).mean[0]

if __name__=='__main__':
    scores=sorted([[score(p),p] for p in sys.argv[1:]],reverse=True)
    print(json.dumps({'scores':scores,'file':scores[0][1]}))
