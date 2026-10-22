"""Draws the ornate menu button frames and the gear icon (models/ui/*.png) - a clean redraw of the style in the designer's mockup.
Re-run after tweaking: python tools/ui/generate_menu_frames.py. Supersampled 8x and shrunk, so edges are smooth."""
import math, os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "models", "ui")
U = 3          # final pixels per mockup pixel
SS = 8         # supersampling
K = U * SS     # drawing pixels per mockup pixel
CYAN = (62, 170, 232, 255)
NAVY = (8, 13, 85, 235)
FILL = (58, 166, 228, 255)


def px(v):
    return int(round(v * K))


def frame(w, h, name):
    img = Image.new("RGBA", (px(w), px(h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, px(w) - 1, px(h) - 1], fill=NAVY)
    lw = max(1, int(1.1 * K))

    def notched_rect(inset, r, notch_sides):
        x0, y0, x1, y1 = inset, inset, w - inset, h - inset
        pts = []
        def seg(a, b):
            pts.append(a); pts.append(b)
        # build a polyline clockwise with semicircle notches (bulging inwards) at edge centres
        cx, cy = w / 2, h / 2
        path = [(x0, y0)]
        if "t" in notch_sides:
            path += [(cx - r, y0)] + [(cx + r * math.cos(math.pi - t), y0 + r * math.sin(t)) for t in [i * math.pi / 24 for i in range(25)]] + [(cx + r, y0)]
        path += [(x1, y0)]
        if "r" in notch_sides:
            path += [(x1, cy - r)] + [(x1 - r * math.sin(t), cy - r * math.cos(t)) for t in [i * math.pi / 24 for i in range(25)]] + [(x1, cy + r)]
        path += [(x1, y1)]
        if "b" in notch_sides:
            path += [(cx + r, y1)] + [(cx + r * math.cos(t), y1 - r * math.sin(t)) for t in [i * math.pi / 24 for i in range(25)]] + [(cx - r, y1)]
        path += [(x0, y1)]
        if "l" in notch_sides:
            path += [(x0, cy + r)] + [(x0 + r * math.sin(t), cy + r * math.cos(t)) for t in [i * math.pi / 24 for i in range(25)]] + [(x0, cy - r)]
        path += [(x0, y0)]
        d.line([(px(a), px(b)) for a, b in path], fill=CYAN, width=lw, joint="curve")

    notched_rect(1.2, 4.5, "tbrl" if w < 100 else "tb")
    # right/left notch also on the wide button, as in the mockup
    if w >= 100:
        notched_rect(1.2, 4.5, "rl")
    notched_rect(7.5, 0, "")

    # fill with concave corners
    f = 13.5
    d.rectangle([px(f), px(f), px(w - f), px(h - f)], fill=FILL)
    cut = 6.0
    for cx, cy in ((f, f), (w - f, f), (f, h - f), (w - f, h - f)):
        d.ellipse([px(cx - cut), px(cy - cut), px(cx + cut), px(cy + cut)], fill=NAVY)
    # a thin line hugging the fill
    d.rectangle([px(f - 1.8), px(f - 1.8), px(w - f + 1.8), px(h - f + 1.8)], outline=CYAN, width=max(1, int(0.8 * K)))
    for cx, cy in ((f, f), (w - f, f), (f, h - f), (w - f, h - f)):
        d.ellipse([px(cx - cut), px(cy - cut), px(cx + cut), px(cy + cut)], fill=NAVY)

    # corner curls
    def curl(cx, cy, sx, sy):
        pts = []
        for i in range(0, 140):
            t = i / 139 * 3.4 * math.pi
            r = 0.45 + 0.95 * (1 - i / 139) * 2.0 / 2.0 + 0.0
            r = 3.0 * (1 - i / 139) + 0.5
            pts.append((cx + sx * r * math.cos(t), cy + sy * r * math.sin(t)))
        d.line([(px(a), px(b)) for a, b in pts], fill=CYAN, width=max(1, int(0.85 * K)), joint="curve")
        # bracket running along both edges
        d.line([(px(cx - sx * 1.0), px(cy + sy * 7.0)), (px(cx - sx * 1.0), px(cy - sy * 1.0)), (px(cx + sx * 7.0), px(cy - sy * 1.0))], fill=CYAN, width=max(1, int(0.85 * K)), joint="curve")
    m = 5.6
    curl(m + 2.2, m + 2.2, 1, 1)
    curl(w - m - 2.2, m + 2.2, -1, 1)
    curl(m + 2.2, h - m - 2.2, 1, -1)
    curl(w - m - 2.2, h - m - 2.2, -1, -1)

    img = img.resize((w * U, h * U), Image.LANCZOS)
    img.save(os.path.join(OUT, name))


def gear(size, name):
    S = size * 4
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    teeth, r_in, r_out = 8, S * 0.33, S * 0.46
    pts = []
    for i in range(teeth * 4):
        a = i / (teeth * 4) * 2 * math.pi
        k = i % 4
        r = r_out if k in (1, 2) else r_in
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
    d.polygon(pts, fill=(255, 255, 255, 255))
    d.ellipse([c - S * 0.2, c - S * 0.2, c + S * 0.2, c + S * 0.2], fill=FILL)
    d.ellipse([c - S * 0.14, c - S * 0.14, c + S * 0.14, c + S * 0.14], fill=(255, 255, 255, 255))
    d.ellipse([c - S * 0.07, c - S * 0.07, c + S * 0.07, c + S * 0.07], fill=FILL)
    img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, name))


frame(79, 79, "menu_button_square.png")
frame(237, 79, "menu_button_wide.png")
gear(128, "menu_gear.png")
