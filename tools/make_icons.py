"""Draw Headstart's small UI icons: white shapes on transparent, 64x64 TGA (WoW reads uncompressed
32-bit TGA with power-of-two sizes). Drawn at 4x and scaled down, so the edges are smooth.

    python tools/make_icons.py     -> art/*.tga

The addon tints them (SetVertexColor), so one white icon serves every colour.
"""
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art")
os.makedirs(OUT, exist_ok=True)
S = 256                     # drawing size; saved at 64
W = 22                      # stroke width at drawing size


def save(img, name):
    img.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, name + ".tga"), orientation=1)


def canvas():
    img = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    return img, ImageDraw.Draw(img)


def line(d, pts):
    d.line(pts, fill=(255, 255, 255, 255), width=W, joint="curve")
    for x, y in (pts[0], pts[-1]):
        r = W / 2
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, 255))


# chevron pointing up (down is the same texture flipped by the addon)
img, d = canvas()
line(d, [(72, 158), (128, 102), (184, 158)])
save(img, "up")

# cross
img, d = canvas()
line(d, [(84, 84), (172, 172)])
line(d, [(172, 84), (84, 172)])
save(img, "close")

# plus
img, d = canvas()
line(d, [(128, 72), (128, 184)])
line(d, [(72, 128), (184, 128)])
save(img, "plus")

# minus
img, d = canvas()
line(d, [(72, 128), (184, 128)])
save(img, "minus")

# drag handle: two columns of three dots
img, d = canvas()
for x in (104, 152):
    for y in (84, 128, 172):
        d.ellipse((x - 13, y - 13, x + 13, y + 13), fill=(255, 255, 255, 255))
save(img, "grip")

# pencil: a slanted bar with a point
img, d = canvas()
d.polygon([(70, 186), (82, 146), (160, 68), (188, 96), (110, 174)], fill=(255, 255, 255, 255))
save(img, "edit")

# copy: two offset squares (outlines)
img, d = canvas()
d.rounded_rectangle((96, 70, 186, 160), radius=14, outline=(255, 255, 255, 255), width=18)
d.rounded_rectangle((70, 96, 160, 186), radius=14, outline=(255, 255, 255, 255), width=18, fill=(255, 255, 255, 0))
save(img, "copy")

# check mark
img, d = canvas()
line(d, [(76, 132), (112, 168), (182, 92)])
save(img, "check")

# small solid circle (a dot for status)
img, d = canvas()
d.ellipse((88, 88, 168, 168), fill=(255, 255, 255, 255))
save(img, "dot")

# info: a ring with an "i" in it
img, d = canvas()
d.ellipse((40, 40, 216, 216), outline=(255, 255, 255, 255), width=18)
d.ellipse((115, 70, 141, 96), fill=(255, 255, 255, 255))
d.rounded_rectangle((116, 112, 140, 186), radius=12, fill=(255, 255, 255, 255))
save(img, "info")

# rounded shapes for 9-slice buttons: 32x32, corner radius 6, drawn at 8x. The addon stretches the
# middle and keeps the corners (Texture:SetTextureSliceMargins), so one image fits any button size.
R = 8


def rounded(name, outline):
    big = Image.new("RGBA", (32 * R, 32 * R), (255, 255, 255, 0))
    dr = ImageDraw.Draw(big)
    if outline:
        dr.rounded_rectangle((R // 2, R // 2, 32 * R - R // 2, 32 * R - R // 2), radius=6 * R,
                             outline=(255, 255, 255, 255), width=R)
    else:
        dr.rounded_rectangle((0, 0, 32 * R - 1, 32 * R - 1), radius=6 * R, fill=(255, 255, 255, 255))
    big.resize((32, 32), Image.LANCZOS).save(os.path.join(OUT, name + ".tga"), orientation=1)


rounded("round", False)
rounded("roundline", True)

print("icons in", OUT, sorted(os.listdir(OUT)))
