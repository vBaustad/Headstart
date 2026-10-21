"""Draw the settings window's controls and its shadow: white shapes on transparent, uncompressed 32-bit TGA with
power-of-two sizes, drawn large and scaled down so every edge is smooth. The addon tints them (SetVertexColor).

    python tools/make_controls.py     -> art/pill.tga, knob.tga, iconmask.tga, box_line.tga, box_fill.tga, tick.tga, shadow.tga,
                                         art/px_pill.tga, px_knob, px_box_line, px_box_fill, px_tick (pixel-exact strips)

The sizes they are drawn for (Style.lua): a switch 40 x 20 with a knob of 16, a checkbox 18 x 18 (the owner,
2026-10-21: "A, refined" - a pill switch and quiet checkboxes, "maybe some shadows to make the styling better").
"""
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art")
WHITE, BLACK = (255, 255, 255, 255), (0, 0, 0, 255)


def save(img, name):
    img.save(os.path.join(OUT, name + ".tga"), orientation=1)


def pill():
    """The switch's track: 40 x 20, the whole of a 128 x 64 texture (the same shape: nothing cropped, nothing squeezed)."""
    k = 8
    big = Image.new("RGBA", (128 * k, 64 * k), (255, 255, 255, 0))
    ImageDraw.Draw(big).rounded_rectangle((k, k, 127 * k, 63 * k), radius=31 * k, fill=WHITE)
    save(big.resize((128, 64), Image.LANCZOS), "pill")


def knob():
    """The switch's knob: a crisp circle the texture's size (a shadow drawn into it read as a blur at 16 points)."""
    k = 8
    big = Image.new("RGBA", (64 * k, 64 * k), (255, 255, 255, 0))
    ImageDraw.Draw(big).ellipse((k, k, 63 * k, 63 * k), fill=WHITE)
    save(big.resize((64, 64), Image.LANCZOS), "knob")


def iconmask():
    """An icon's corners rounded: a mask (white where the icon shows), corners of a fifth of its side."""
    k = 8
    big = Image.new("RGBA", (64 * k, 64 * k), (255, 255, 255, 0))
    ImageDraw.Draw(big).rounded_rectangle((0, 0, 64 * k - 1, 64 * k - 1), radius=13 * k, fill=WHITE)
    save(big.resize((64, 64), Image.LANCZOS), "iconmask")


def box(filled):
    """The checkbox: 18 x 18, corners of 4, an edge of 1.5 (or the whole of it filled)."""
    k = 4
    size = 64 * k
    u = size / 18                       # one point of the checkbox, in drawing pixels
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    if filled:
        d.rounded_rectangle((0, 0, size - 1, size - 1), radius=4 * u, fill=WHITE)
    else:
        # (PIL draws an edge inside the box it is given: the box itself, so the edge lies on the filled one's edge)
        d.rounded_rectangle((0, 0, size - 1, size - 1), radius=4 * u, outline=WHITE, width=round(1.5 * u))
    save(img.resize((64, 64), Image.LANCZOS), "box_fill" if filled else "box_line")


def tick():
    """The tick in the checkbox: drawn over it at the same size, round ends."""
    k = 4
    size = 64 * k
    u = size / 18
    pts = [(5.5 * u, 9.3 * u), (8.0 * u, 11.7 * u), (12.6 * u, 6.7 * u)]
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    w = 2.1 * u
    d.line(pts, fill=WHITE, width=round(w), joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=WHITE)
    save(img.resize((64, 64), Image.LANCZOS), "tick")


def shadow():
    """A soft shadow to lay under a panel, sliced in nine (Style.lua, S.Shadow: margins of 24, the panel 16 in)."""
    k = 4
    size = 64 * k
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((16 * k, 16 * k, size - 16 * k, size - 16 * k), radius=8 * k, fill=(0, 0, 0, 255))
    img = img.filter(ImageFilter.GaussianBlur(7 * k))
    save(img.resize((64, 64), Image.LANCZOS), "shadow")


# ---------------------------------------------------------------------------------------------------------------
# Pixel-exact controls. A small round shape scaled down from a larger texture lands between screen pixels and reads soft
# (the owner, 2026-10-21, at 2560 wide and a UI scale of 0.64: 1.2 screen pixels to a point - the switch 48 x 24
# pixels drawn from 128 x 64, its knob 19.2). So each control is drawn again at every size in pixels it is likely to
# be shown at, one texel to one pixel (Style.lua picks the size from the screen and the UI scale). Each strip: the
# sizes from FROM up, one under another from the top, GAP pixels between; Style.lua finds a size where this puts it.
GAP = 2
PX = {  # name: (canvas width, canvas height, smallest, largest, width per pixel of height)
    "px_pill": (128, 1024, 16, 40, 2),      # (up to 1.8 pixels to a point: 4K at the game's own UI scale, 0.64)
    "px_knob": (64, 1024, 10, 36, 1),
    "px_box_line": (64, 1024, 14, 36, 1),
    "px_box_fill": (64, 1024, 14, 36, 1),
    "px_tick": (64, 1024, 14, 36, 1),
}


def strip(name, draw):
    cw, ch, lo, hi, wide = PX[name]
    out = Image.new("RGBA", (cw, ch), (255, 255, 255, 0))
    y = 0
    for size in range(lo, hi + 1):
        k = 8
        big = Image.new("RGBA", (size * wide * k, size * k), (255, 255, 255, 0))
        draw(ImageDraw.Draw(big), size, k)
        out.paste(big.resize((size * wide, size), Image.LANCZOS), (0, y))
        y += size + GAP
    assert y <= ch, (name, y)
    save(out, name)


def px_pill(d, h, k):
    d.rounded_rectangle((0, 0, 2 * h * k - 1, h * k - 1), radius=h * k / 2, fill=WHITE)


def px_knob(d, s, k):
    d.ellipse((0, 0, s * k - 1, s * k - 1), fill=WHITE)


def px_box(filled):
    def draw(d, s, k):
        u = s * k / 18
        if filled:
            d.rounded_rectangle((0, 0, s * k - 1, s * k - 1), radius=4 * u, fill=WHITE)
        else:
            d.rounded_rectangle((0, 0, s * k - 1, s * k - 1), radius=4 * u, outline=WHITE,
                                width=round(max(1.5 * u, 1.25 * k)))
    return draw


def px_tick(d, s, k):
    u = s * k / 18
    pts = [(5.5 * u, 9.3 * u), (8.0 * u, 11.7 * u), (12.6 * u, 6.7 * u)]
    w = 2.1 * u
    d.line(pts, fill=WHITE, width=round(w), joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=WHITE)


pill()
knob()
iconmask()
strip("px_pill", px_pill)
strip("px_knob", px_knob)
strip("px_box_line", px_box(False))
strip("px_box_fill", px_box(True))
strip("px_tick", px_tick)
box(False)
box(True)
tick()
shadow()
print("art/pill.tga, knob.tga, iconmask.tga, box_line.tga, box_fill.tga, tick.tga, shadow.tga, px_*.tga")
