"""Tile screenshots into a contact sheet: grid.py out.png cols img1 img2 ..."""
import sys
from PIL import Image
out, cols, files = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
ims = [Image.open(f).convert("RGB") for f in files]
w, h = ims[0].size
scale = 1.0 if cols == 1 else 0.6
w2, h2 = int(w * scale), int(h * scale)
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (w2 * cols, h2 * rows))
for i, im in enumerate(ims):
    sheet.paste(im.resize((w2, h2)), ((i % cols) * w2, (i // cols) * h2))
sheet.save(out)
