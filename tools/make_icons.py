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


def line(d, pts, w=W):
    d.line(pts, fill=(255, 255, 255, 255), width=w, joint="curve")
    for x, y in (pts[0], pts[-1]):
        r = w / 2
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

# a small window's cross (S.CloseX): larger and bolder in its square than the title bar's - "close" filled a third of
# it, and at a small window's size it was a speck (the owner, 2026-10-21: "make the X better")
img, d = canvas()
line(d, [(62, 62), (194, 194)], 30)
line(d, [(194, 62), (62, 194)], 30)
save(img, "x")

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


# A full-size circle (edge to edge, unlike "dot"), drawn at 4x: the flight timer's nodes and round ends.
img, d = canvas()
d.ellipse((2, 2, S - 3, S - 3), fill=(255, 255, 255, 255))
save(img, "circle")


# A map pin: RestedXP's "go to" icon in our routes (a crop of the minimap sheet that shows as a smudge
# on Forever; Guides.lua swaps it in, tinted grey like RestedXP's own talk bubble). A round head with a
# hole and a point, filling the height so it reads at line size.
img, d = canvas()
d.ellipse((58, 14, 198, 154), fill=(255, 255, 255, 255))
d.polygon([(66, 116), (190, 116), (128, 246)], fill=(255, 255, 255, 255))
d.ellipse((100, 56, 156, 112), fill=(255, 255, 255, 0))
save(img, "pin")


# --- the damage meter skin's top bar (DamageSkin.lua): one stroke weight, like the icons above ---
import math

# gear: a ring with eight teeth (the meter's settings)
img, d = canvas()
for i in range(8):
    a = math.radians(i * 45)
    x0, y0 = 128 + math.cos(a) * 66, 128 + math.sin(a) * 66
    x1, y1 = 128 + math.cos(a) * 96, 128 + math.sin(a) * 96
    d.line([(x0, y0), (x1, y1)], fill=(255, 255, 255, 255), width=30)
d.ellipse((58, 58, 198, 198), fill=(255, 255, 255, 255))
d.ellipse((98, 98, 158, 158), fill=(255, 255, 255, 0))
save(img, "gear")

# bars: three bars of falling length (what the meter shows: damage, healing, ...)
img, d = canvas()
for y, x1 in ((80, 190), (128, 150), (176, 110)):
    line(d, [(66, y), (x1, y)])
save(img, "bars")

# clock: a ring with two hands (which fight: this one, or all of them)
img, d = canvas()
d.ellipse((44, 44, 212, 212), outline=(255, 255, 255, 255), width=20)
line(d, [(128, 128), (128, 82)])
line(d, [(128, 128), (162, 146)])
save(img, "clock")

# reset: three quarters of a ring with an arrow head (clear the meter)
img, d = canvas()
d.arc((52, 52, 204, 204), start=-60, end=210, fill=(255, 255, 255, 255), width=22)
ax, ay = 128 + math.cos(math.radians(-60)) * 76, 128 + math.sin(math.radians(-60)) * 76
d.polygon([(ax - 34, ay - 30), (ax + 30, ay - 22), (ax + 4, ay + 34)], fill=(255, 255, 255, 255))
save(img, "reset")

# sound: a speaker with two waves (listen to this one)
img, d = canvas()
d.polygon([(50, 104), (88, 104), (132, 62), (132, 194), (88, 152), (50, 152)], fill=(255, 255, 255, 255))
d.arc((104, 88, 184, 168), start=-55, end=55, fill=(255, 255, 255, 255), width=18)
d.arc((84, 48, 224, 208), start=-50, end=50, fill=(255, 255, 255, 255), width=18)
save(img, "sound")

# bubble: a speech bubble (the chat menu)
img, d = canvas()
d.rounded_rectangle((46, 56, 210, 168), radius=30, outline=(255, 255, 255, 255), width=20)
d.polygon([(84, 160), (84, 214), (134, 164)], fill=(255, 255, 255, 255))
save(img, "bubble")

# people: two heads and shoulders (channels, the social window)
img, d = canvas()
d.ellipse((66, 60, 122, 116), fill=(255, 255, 255, 255))
d.pieslice((40, 126, 148, 234), start=180, end=360, fill=(255, 255, 255, 255))
d.ellipse((140, 76, 188, 124), fill=(255, 255, 255, 255))
d.pieslice((120, 136, 212, 228), start=180, end=360, fill=(255, 255, 255, 255))
save(img, "people")


# logo: Headstart's own mark, in colour (the minimap button, the addon list). An H leaning forward in
# the ember accent, on a dark disc with an ember rim. Not tinted by the addon: it is drawn as it is.
def logo():
    n = 512
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((6, 6, n - 6, n - 6), fill=(255, 143, 51, 255))                 # the rim
    d.ellipse((30, 30, n - 30, n - 30), fill=(26, 22, 19, 255))               # the disc
    # the H, as a mask, filled with the ember going lighter towards the top
    mask = Image.new("L", (n, n), 0)
    m = ImageDraw.Draw(mask)
    lean, top, bottom, stem = 44, 124, 388, 74
    for x in (150, 318):
        m.polygon([(x + lean, top), (x + lean + stem, top), (x + stem - lean, bottom), (x - lean, bottom)], fill=255)
    m.polygon([(170, 222), (372, 222), (352, 290), (150, 290)], fill=255)
    fill = Image.new("RGBA", (n, n))
    f = ImageDraw.Draw(fill)
    for y in range(n):
        t = min(1, max(0, (y - top) / (bottom - top)))
        f.line([(0, y), (n, y)], fill=(255, int(204 - 82 * t), int(112 - 86 * t), 255))
    img.paste(fill, (0, 0), mask)
    img.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, "logo.tga"), orientation=1)
    # The mark alone, for the minimap button: the H with nothing round it. The button has its own dark
    # disc and gold ring; a second rim inside that one showed every pixel the two were apart.
    mark = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    mark.paste(fill, (0, 0), mask)
    box = mask.getbbox()
    side = max(box[2] - box[0], box[3] - box[1])
    pad = int(side * 0.12)
    square = Image.new("RGBA", (side + 2 * pad, side + 2 * pad), (0, 0, 0, 0))
    cut = mark.crop(box)
    square.paste(cut, (pad + (side - cut.width) // 2, pad + (side - cut.height) // 2), cut)
    square.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, "logomark.tga"), orientation=1)
    return img


logo()

