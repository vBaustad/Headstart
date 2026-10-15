"""Draw the boat timer's map icons: a boat and a zeppelin seen from above, bow up, in their own colours with a
dark edge so they read on any map. 64x64 TGA, drawn at 4x and scaled down. Headstart's own art.

    python tools/make_boat_icons.py     -> art/map_boat.tga, art/map_zeppelin.tga

The addon turns them to the way the boat is heading (SetRotation): north is up in the file.
"""
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art")
S = 256
EDGE = (24, 18, 14, 255)


def save(img, name):
    img.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, name + ".tga"), orientation=1)


def outlined(draw_shape, fill, width=14):
    """A shape drawn twice: grown in the dark edge colour, then itself in its colour."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    draw_shape(d, EDGE, width)
    draw_shape(d, fill, 0)
    return img, d


# the boat: a hull with a pointed bow and a round stern, its deck, a mast and a sail across it
def hull(d, colour, grow):
    g = grow
    pts = [(128, 22 - g), (176 + g, 96), (178 + g, 186), (160 + g, 226 + g), (96 - g, 226 + g), (78 - g, 186), (80 - g, 96)]
    d.polygon(pts, fill=colour)


img, d = outlined(hull, (140, 92, 52, 255))
d.polygon([(128, 48), (160, 104), (162, 182), (148, 210), (108, 210), (94, 182), (96, 104)], fill=(178, 128, 78, 255))  # deck
for y in (120, 150, 180):
    d.line([(100, y), (156, y)], fill=(150, 102, 60, 255), width=4)                                   # planks
d.rounded_rectangle((60, 112, 196, 136), radius=10, fill=EDGE)                                         # the sail's edge
d.rounded_rectangle((66, 116, 190, 132), radius=8, fill=(242, 232, 206, 255))                          # the sail across
d.ellipse((116, 112, 140, 136), fill=(96, 62, 34, 255))                                                 # the mast
save(img, "map_boat")


# the zeppelin: a long balloon, its fins at the back, a band round it, the gondola's shadow under the middle
def balloon(d, colour, grow):
    g = grow
    d.ellipse((76 - g, 18 - g, 180 + g, 214 + g), fill=colour)
    d.polygon([(100, 186), (62 - g, 238 + g), (110, 206)], fill=colour)
    d.polygon([(156, 186), (194 + g, 238 + g), (146, 206)], fill=colour)


img, d = outlined(balloon, (196, 176, 140, 255))
d.polygon([(100, 186), (68, 232), (110, 206)], fill=(150, 40, 34, 255))                                # fins
d.polygon([(156, 186), (188, 232), (146, 206)], fill=(150, 40, 34, 255))
d.ellipse((92, 36, 164, 196), fill=(214, 196, 160, 255))                                               # the light top
for y in (78, 118, 158):
    d.line([(84, y), (172, y)], fill=(150, 40, 34, 255), width=8)                                      # bands
d.ellipse((118, 20, 138, 40), fill=(150, 40, 34, 255))                                                 # the nose
save(img, "map_zeppelin")
print("art/map_boat.tga, art/map_zeppelin.tga")
