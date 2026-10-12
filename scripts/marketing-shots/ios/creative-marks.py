"""Find the marked calendar cells in a native capture, in reading order.

Usage: creative-marks.py capture.png '{"x":53,"width":1214,"strips":[[y0,y1],...]}'

The calendar is seven equal columns between x and x+width. For each strip
(the band under a row of dates where the app draws its marks) a column counts
as marked when it holds coloured pixels: record bars, overtime dots, leave
icons or the run highlight. Grey date numbers and white card stay unmarked.
Prints [[x, y, w, h], ...] so the video can reveal those cells in order.
"""
import json
import sys

from PIL import Image

image = Image.open(sys.argv[1]).convert("RGB")
spec = json.loads(sys.argv[2])
column = spec["width"] / 7
cells = []
for y0, y1 in spec["strips"]:
    for index in range(7):
        x0 = round(spec["x"] + index * column)
        x1 = round(spec["x"] + (index + 1) * column)
        coloured = [
            (x, y)
            for y in range(y0, y1)
            for x in range(x0, x1)
            if max(pixel := image.getpixel((x, y))) - min(pixel) >= 15
        ]
        if len(coloured) >= 20:
            cells.append([x0, y0, x1 - x0, y1 - y0])
print(json.dumps(cells))
