"""Find the marked calendar cells in a native capture, in reading order.

Usage: creative-marks.py capture.png '{"x":53,"width":1214,"strips":[[y0,y1],...]}'
       creative-marks.py capture.png '{"anchor":"green"|"blue","band":[y0,y1]}'
       creative-marks.py report.mov '{"reportHours":true}'

The calendar is seven equal columns between x and x+width. For each strip
(the band under a row of dates where the app draws its marks) a column counts
as marked when it holds coloured pixels: record bars, overtime dots, leave
icons or the run highlight. Grey date numbers and white card stay unmarked.
Prints [[x, y, w, h], ...] so the video can reveal those cells in order.

With "anchor" it prints the first row in the band crossed by the leave run's
green highlight or the record bars' blue: scripts with taller line heights
(Thai, Devanagari, Arabic, Vietnamese) push calendar rows down, and the video
shifts its crop by the difference.

With "reportHours" it reads a cycle-report recording and prints the second at
which the hours chapter starts: the end of the opening chapter's run of orange
day dots. The report opens at a different moment in each recording.
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

spec = json.loads(sys.argv[2])
if spec.get("reportHours"):
    with tempfile.TemporaryDirectory() as frames:
        subprocess.run(["ffmpeg", "-v", "error", "-i", sys.argv[1], "-vf", "fps=10,scale=165:-2",
                        f"{frames}/f%04d.png"], check=True)
        row = ""
        for path in sorted(Path(frames).glob("*.png")):
            frame = Image.open(path).convert("RGB")
            w, h = frame.size
            dots = sum(1 for y in range(int(h * .38), int(h * .58), 2) for x in range(0, w, 2)
                       if (p := frame.getpixel((x, y)))[0] > 200 and p[1] > 120 and p[2] < 120)
            row += "D" if dots > 40 else "."
    run = re.search(r"D{20,}", row)
    if not run:
        sys.exit("The report never reached its opening chapter in this recording")
    print(run.end() / 10)
    sys.exit(0)
image = Image.open(sys.argv[1]).convert("RGB")
if "anchor" in spec:
    tests = {
        "green": lambda p: p[1] > p[0] + 8 and p[1] > p[2] + 3 and p[1] > 200,
        "blue": lambda p: p[2] > 180 and p[0] < 130 and p[1] < 130,
    }
    test = tests[spec["anchor"]]
    y0, y1 = spec["band"]
    for y in range(y0, y1):
        if sum(1 for x in range(60, 1260, 2) if test(image.getpixel((x, y)))) > 40:
            print(y)
            sys.exit(0)
    sys.exit(f"No {spec['anchor']} row between {y0} and {y1}")
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
