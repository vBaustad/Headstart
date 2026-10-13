"""Draw Headstart's settings window without the game, to look at its layout.

    python tools/render.py [page ...]      writes tools/render/<page>.html  (default: a handful of pages)
    python tools/render.py transfer transfer:export transfer:import      the Move settings window, shut and open

The smoke test's fake game is used as far as the point where it opens the window; from there every frame,
texture and text the addon makes is recorded (parent, size, anchors, colour, words) instead of thrown away.
The anchors are then solved the way the game does and written out as absolutely placed boxes. It is a
sketch, not the game: fonts are the browser's, icons are grey squares, and text widths are estimates - but
what overlaps, what runs out of its box and what doesn't fit is the same arithmetic.
"""
import html
import os
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
SMOKE = os.path.join(TOOLS, "smoke.py")
CUT = "YR.ToggleWindow("
SCREEN_W, SCREEN_H = 1500, 800

RECORD = r'''
RENDER = {}
local Frame = getmetatable(CreateFrame())
-- only a method is made up: a field the addon never set is nil, as in the game ("if row.changed then")
Frame.__index = function(_, k)
    local v = rawget(Frame, k)
    if v ~= nil then return v end
    if type(k) == "string" and k:match("^%u") then return function() return setmetatable({ ev = {} }, Frame) end end
end
local function New(kind, parent)
    local o = setmetatable({ ev = {}, kind = kind, parent = parent, points = {} }, Frame)
    RENDER[#RENDER + 1] = o
    o.rid = #RENDER
    return o
end
local Make = CreateFrame
function CreateFrame(ftype, name, parent)
    local f = Make(ftype, name)
    f.kind, f.parent, f.points, f.ftype = "frame", parent, {}, ftype
    RENDER[#RENDER + 1] = f
    f.rid = #RENDER
    return f
end
UIParent.kind, UIParent.points, UIParent.root = "frame", {}, true
RENDER[#RENDER + 1] = UIParent
UIParent.rid = #RENDER
function Frame:CreateTexture(_, layer, _, sub) local t = New("tex", self) t.layer, t.sub = layer or "ARTWORK", sub or 0 return t end
function Frame:CreateFontString(_, layer) local t = New("fs", self) t.layer, t.sub = layer or "OVERLAY", 0 return t end
function Frame:SetParent(p) self.parent = p end
function Frame:GetParent() return rawget(self, "parent") end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetAllPoints(rel)
    self.points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
end
function Frame:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y
    if type(a) == "number" then x, y = a, b
    else
        rel = a
        if type(b) == "string" then relPoint, x, y = b, c, d else x, y = b, c end
    end
    self.points = rawget(self, "points") or {}
    for i, p in ipairs(self.points) do if p[1] == point then table.remove(self.points, i) break end end
    self.points[#self.points + 1] = { point, rel, relPoint or point, x or 0, y or 0 }
end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return rawget(self, "w") or 20 end
function Frame:GetHeight() return rawget(self, "h") or 20 end
function Frame:GetStringWidth() return #(tostring(rawget(self, "text") or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * (rawget(self, "size") or 13) * 0.43 end
function Frame:SetFont(_, size) self.size = size end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return rawget(self, "text") or "" end
function Frame:SetTextColor(r, g, b, a) self.color = { r, g, b, a or 1 } end
function Frame:SetJustifyH(j) self.jh = j end
function Frame:SetJustifyV(j) self.jv = j end
function Frame:SetWordWrap(on) self.wrap = on end
function Frame:SetColorTexture(r, g, b, a) self.fill = { r, g, b, a or 1 } self.tex = nil end
function Frame:SetTexture(t) self.tex = tostring(t) self.fill = nil end
function Frame:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a or 1 } end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:SetDesaturated(on) self.grey = on end
function Frame:SetScrollChild(child) child.scrollOf = self self.scrollChild = child end
function Frame:SetFrameLevel(n) self.level = n end
function Frame:GetFrameLevel() return rawget(self, "level") or 1 end
function Frame:SetFrameStrata(s) self.strata = s end
function Frame:GetObjectType()
    local kind = rawget(self, "kind")
    return kind == "fs" and "FontString" or kind == "tex" and "Texture" or "Frame"
end
'''

LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 4}
FX = {"LEFT": 0, "CENTER": 0.5, "RIGHT": 1, "TOP": 0.5, "BOTTOM": 0.5}
FY = {"TOP": 1, "CENTER": 0.5, "BOTTOM": 0, "LEFT": 0.5, "RIGHT": 0.5}


def frac(point):
    """Where on a box a point name is: (x from the left, y from the bottom), each 0..1."""
    p = point.upper()
    x = 0 if "LEFT" in p else 1 if "RIGHT" in p else 0.5
    y = 1 if "TOP" in p else 0 if "BOTTOM" in p else 0.5
    return x, y


class Obj:
    pass


def load(lua):
    raw = lua.eval("function(t, k) return rawget(t, k) end")      # (a frame's own fields: anything else is a no-op function)
    objs = {}
    render = lua.globals().RENDER
    for i in range(1, len(render) + 1):
        t = render[i]
        o = Obj()
        o.t, o.rid, o.kind = t, i, raw(t, "kind")
        objs[i] = o

    def ref(x):
        return objs.get(raw(x, "rid")) if x is not None and raw(x, "rid") else None
    for o in objs.values():
        t = o.t
        o.parent = ref(raw(t, "parent"))
        o.root = bool(raw(t, "root"))
        o.w, o.h = raw(t, "w"), raw(t, "h")
        o.hidden = bool(raw(t, "hidden"))
        o.alpha = raw(t, "alpha") if raw(t, "alpha") is not None else 1
        o.text = raw(t, "text")
        o.size = raw(t, "size") or 13
        o.layer, o.sub = raw(t, "layer"), raw(t, "sub") or 0
        o.level = raw(t, "level")
        o.scrollOf = ref(raw(t, "scrollOf"))
        o.points = []
        pts = raw(t, "points")
        if pts is not None:
            for j in range(1, len(pts) + 1):
                p = pts[j]
                o.points.append((p[1], ref(p[2]), p[3], p[4] or 0, p[5] or 0))

        def col(name):
            c = raw(t, name)
            return None if c is None else (c[1], c[2], c[3], c[4] if c[4] is not None else 1)
        o.fill, o.vertex, o.color, o.tex = col("fill"), col("vertex"), col("color"), raw(t, "tex")
        o.jh, o.jv, o.wrap = raw(t, "jh"), raw(t, "jv"), raw(t, "wrap")
        o.rect = None
        o.busy = False
    return objs


def text_plain(s):
    import re
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", str(s or ""))


def solve(o):
    """(left, bottom, right, top) in the game's coordinates (y up)."""
    if o.rect is not None:
        return o.rect
    if o.root:
        o.rect = (0, 0, SCREEN_W, SCREEN_H)
        return o.rect
    if o.busy:
        return (0, 0, 0, 0)
    o.busy = True
    par = solve(o.parent) if o.parent else (0, 0, SCREEN_W, SCREEN_H)
    w, h = o.w, o.h
    if o.kind == "fs":
        if w is None:
            w = len(text_plain(o.text)) * o.size * 0.43
        if h is None:
            h = o.size * 1.25
    xs, ys = {}, {}
    points = o.points
    if not points and o.scrollOf is not None:
        s = solve(o.scrollOf)
        points = []
        xs[0], ys[1] = s[0], s[3]
    for point, rel, relPoint, x, y in points:
        r = solve(rel) if rel is not None else par
        fx, fy = frac(relPoint)
        ax = r[0] + (r[2] - r[0]) * fx + x
        ay = r[1] + (r[3] - r[1]) * fy + y
        px, py = frac(point)
        xs[px], ys[py] = ax, ay
    if 0 in xs and 1 in xs:
        left, right = xs[0], xs[1]
    else:
        w = w if w is not None else 0
        if 0 in xs:
            left = xs[0]
        elif 1 in xs:
            left = xs[1] - w
        elif 0.5 in xs:
            left = xs[0.5] - w / 2
        else:
            left = par[0] if not points else par[0]
        right = left + w
    if 0 in ys and 1 in ys:
        bottom, top = ys[0], ys[1]
    else:
        h = h if h is not None else 0
        if 1 in ys:
            top = ys[1]
        elif 0 in ys:
            top = ys[0] + h
        elif 0.5 in ys:
            top = ys[0.5] + h / 2
        else:
            top = par[3]
        bottom = top - h
    o.rect = (left, bottom, right, top)
    o.busy = False
    return o.rect


def visible(o):
    a = 1.0
    while o is not None:
        if o.hidden:
            return 0
        a *= o.alpha
        o = o.parent
    return a


def clip_of(o):
    while o is not None:
        if o.scrollOf is not None:
            return solve(o.scrollOf)
        o = o.parent
    return None


def depth_order(objs):
    kids = {}
    for o in objs.values():
        kids.setdefault(o.parent.rid if o.parent else 0, []).append(o)
    order, n = {}, [0]

    def walk(o):
        n[0] += 1
        order[o.rid] = n[0]
        for k in sorted(kids.get(o.rid, []), key=lambda k: ((k.level or 0) if k.kind == "frame" else 0, k.rid)):
            if k.kind == "frame":
                walk(k)
    for o in objs.values():
        if o.root:
            walk(o)
    for o in kids.get(0, []):
        if o.kind == "frame" and o.rid not in order:
            walk(o)
    return order


def rgba(c, a=1.0):
    return "rgba(%d,%d,%d,%.3f)" % (round(c[0] * 255), round(c[1] * 255), round(c[2] * 255), max(0, min(1, c[3] * a)))


def draw(objs, title):
    for o in objs.values():
        o.rect, o.busy = None, False
    order = depth_order(objs)
    out = []
    for o in objs.values():
        if o.kind == "frame":
            continue
        alpha = visible(o)
        if not alpha or o.parent is None or o.parent.rid not in order:
            continue
        l, b, r, t = solve(o)
        z = order[o.parent.rid] * 100 + LAYERS.get(str(o.layer).upper(), 2) * 10 + min(9, max(0, int(o.sub or 0)))
        style = ["left:%.1fpx" % l, "top:%.1fpx" % (SCREEN_H - t), "z-index:%d" % z]
        c = clip_of(o)
        if c:
            cl, cb, cr, ct = c
            if r <= cl or l >= cr or t <= cb or b >= ct:
                continue
            style.append("clip-path:inset(%.1fpx %.1fpx %.1fpx %.1fpx)" % (max(0, t - ct), max(0, r - cr), max(0, cb - b), max(0, cl - l)))
        if o.kind == "tex":
            if r - l <= 0 or t - b <= 0:
                continue
            style += ["width:%.1fpx" % (r - l), "height:%.1fpx" % (t - b)]
            v = o.vertex or (1, 1, 1, 1)
            if o.fill:
                style.append("background:" + rgba(o.fill, alpha))
            elif o.tex:
                name = o.tex.replace("\\", "/").split("/")[-1].lower()
                if name.startswith("roundline"):
                    style += ["border:1px solid " + rgba(v, alpha), "border-radius:6px", "box-sizing:border-box"]
                elif name.startswith("round"):
                    style += ["background:" + rgba(v, alpha), "border-radius:6px"]
                elif name.startswith("dot"):
                    style += ["background:" + rgba(v, alpha), "border-radius:50%"]
                elif "art/" in o.tex.replace("\\", "/").lower():
                    style += ["border:1px solid " + rgba(v, alpha), "border-radius:50%", "box-sizing:border-box"]
                else:
                    style += ["background:rgba(120,115,105,%.2f)" % (0.55 * alpha), "outline:1px solid rgba(0,0,0,.5)"]
            else:
                continue
            out.append('<div class="t" style="%s"></div>' % ";".join(style))
        else:
            if not o.text:
                continue
            col = o.color or (1, 1, 1, 1)
            style += ["color:" + rgba(col, alpha), "font-size:%dpx" % o.size, "line-height:%.1fpx" % (o.size * 1.25)]
            jh = (o.jh or "LEFT").lower()
            if o.w is not None or (len({frac(p[0])[0] for p in o.points}) > 1):
                style += ["width:%.1fpx" % (r - l), "text-align:" + jh, "overflow:hidden"]
                style.append("white-space:normal" if o.wrap else "white-space:nowrap;text-overflow:ellipsis")
            else:
                # no width of its own: it grows from the side it is anchored by
                px = [frac(p[0])[0] for p in o.points]
                if px and px[0] == 1:
                    style[0] = "left:%.1fpx;transform:translateX(-100%%)" % r
                elif px and px[0] == 0.5:
                    style[0] = "left:%.1fpx;transform:translateX(-50%%)" % ((l + r) / 2)
                style.append("white-space:pre")
            out.append('<div class="f" style="%s">%s</div>' % (";".join(style), html.escape(text_plain(o.text)).replace("\n", "<br>")))
    # the picture is the window: moved to the corner, the page as large as it
    box = solve(objs[draw.window]) if draw.window in objs else (0, 0, SCREEN_W, SCREEN_H)
    draw.size = (box[2] - box[0], box[3] - box[1])
    return ("<!doctype html><meta charset=utf-8><title>%s</title><style>body{margin:0;background:#2b3a2e;width:%dpx;height:%dpx;"
            "position:relative;overflow:hidden;font-family:'Arial Narrow',Arial,sans-serif;font-stretch:condensed}"
            "#w{position:absolute;left:%.1fpx;top:%.1fpx}.t,.f{position:absolute}</style><div id=w>%s</div>"
            % (html.escape(title), draw.size[0], draw.size[1], -box[0], -(SCREEN_H - box[3]), "\n".join(out)))


draw.window, draw.size = None, (0, 0)


def main(pages):
    src = open(SMOKE, encoding="utf-8").read()
    cut = src.index(CUT)
    env = {"__file__": SMOKE, "__name__": "render_smoke"}
    real_stdout = sys.stdout
    sys.stdout = open(os.devnull, "w")
    try:
        exec(compile(src[:cut], SMOKE, "exec"), env)
    finally:
        sys.stdout = real_stdout
    lua, YR = env["lua"], env["YR"]
    lua.execute(RECORD)
    lua.execute("UIParent.w, UIParent.h = %d, %d" % (SCREEN_W, SCREEN_H))
    out_dir = os.path.join(TOOLS, "render")
    os.makedirs(out_dir, exist_ok=True)
    YR.ToggleWindow(YR, "settings")
    for page in pages:
        root = "HeadstartWindow"
        if page.startswith("find:"):
            YR.ShowSettingsTab(YR, "home")
            YR.SettingsSearch(page[5:])
        elif page.startswith("transfer"):
            YR.TransferShow(page[9:] or None)       # a window of its own: drawn by itself
            root = "HeadstartTransferWindow"
        else:
            YR.ShowSettingsTab(YR, page)
        objs = load(lua)
        draw.window = lua.eval('%s and rawget(%s, "rid")' % (root, root))
        path = os.path.join(out_dir, page.replace(":", "_").replace(" ", "_") + ".html")
        open(path, "w", encoding="utf-8").write(draw(objs, "Headstart: " + page))
        print(path, len(objs), "window %dx%d" % draw.size)


if __name__ == "__main__":
    main(sys.argv[1:] or ["home", "recap", "xpbar", "bags", "reminders", "group", "setup"])
