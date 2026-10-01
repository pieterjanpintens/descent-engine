"""Generator for the two placeholder shield icons used as weakness/
resistance backgrounds in CombatView.gd - same "generated placeholder,
not a real asset" convention as every other piece of art in this project
(hero portraits, HUD icons, damage-type diamonds), but kept as a real,
re-runnable tool here rather than the usual one-off throwaway script
("keep the script around, might want to tweak further") since this one
went through enough rounds of live tuning to be worth revisiting later.

Run with `python generate_shield_icons.py` from anywhere - output paths
are resolved relative to this file's own location, not the current
working directory.

Revision history, oldest first:

Revised 2026-09-29 (eighth time), on top of the anti-aliased heater-shield
pass:
1. "maybe a bit more gradient" - the flat light-strip/dark-fill two-tone
   split is now a real smooth left-to-right gradient instead of a hard
   edge at the midline.
2. "the broken shield should be broken trough[,] the white lines you draw
   over are not long enough" -> follow-up clarification: "they dont go
   over the edges of the actual shield so it looks a bit weird" - the
   crack erasure line stopped just SHORT of the shield's own outer
   border stroke at each tip, so the border looked visually intact/
   unbroken right where the crack should have cut through it. Fixed by
   overshooting the crack's start/end points past the shield's own top/
   bottom points entirely (into the transparent margin beyond the
   silhouette) - erasing a bit of already-empty canvas is harmless, and
   guarantees the erasure fully crosses the border stroke at both ends
   instead of stopping just inside it.
3. "also were the cracks are, darken the edge a bit" then "the shadow
   effect must stop at the edges of the shield" - the darkened rim along
   the crack is now CLIPPED to the shield's own silhouette (multiplied
   against the shape mask before pasting), unlike the transparent
   erasure above it deliberately isn't - so the shadow never bleeds out
   past the border the way an early version of it did at the overshooting
   tips.
4. "15% wider" - W bumped from 96 to 110 (96 * 1.15, rounded).
5. "make the darker edge a bit wider, widen the shield another 10% in
   general" - W bumped again, 110 * 1.10 = 121.
6. "revert the crack rim widening, i meant the darker border of the
   shield itself" - #5's "darker edge" was misread as the crack's own
   dark shadow rim; that's reverted back to its original width, and the
   shield's own OUTER BORDER stroke is widened instead (5 -> 8)."""
import os

from PIL import Image, ImageDraw, ImageChops

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ICONS_DIR = os.path.join(SCRIPT_DIR, "..", "..", "models", "icons")

W, H = 121, 168          # final output size - width is 96 * 1.15 * 1.10 ("15% wider" then "another 10%"), rounded each step
SCALE = 4                # supersample factor - draw at (W*SCALE, H*SCALE), then downsample
SW, SH = W * SCALE, H * SCALE

TOP_CENTER = (0.5, 0.06)
SHOULDER = (0.04, 0.14)
BOTTOM = (0.5, 0.97)
SEG1_CTRL = ((0.30, 0.02), (0.10, 0.04))   # top-centre -> shoulder
SEG2_CTRL = ((0.02, 0.35), (0.10, 0.75))   # shoulder -> bottom point


def _cubic_bezier(p0, p1, p2, p3, steps):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        x = mt ** 3 * p0[0] + 3 * mt ** 2 * t * p1[0] + 3 * mt * t ** 2 * p2[0] + t ** 3 * p3[0]
        y = mt ** 3 * p0[1] + 3 * mt ** 2 * t * p1[1] + 3 * mt * t ** 2 * p2[1] + t ** 3 * p3[1]
        pts.append((x, y))
    return pts


def _shield_points_frac(steps=24):
    seg1 = _cubic_bezier(TOP_CENTER, SEG1_CTRL[0], SEG1_CTRL[1], SHOULDER, steps)
    seg2 = _cubic_bezier(SHOULDER, SEG2_CTRL[0], SEG2_CTRL[1], BOTTOM, steps)
    left = seg1 + seg2[1:]  # TOP_CENTER -> SHOULDER -> BOTTOM, no duplicate at the join
    right = [(1 - x, y) for x, y in reversed(left[1:-1])]  # mirrored, excludes the shared axis points
    return left + right


def shield_points(w=SW, h=SH):
    return [(x * w, y * h) for x, y in _shield_points_frac()]


def _scaled_points(pts, scale, w=SW, h=SH):
    cx, cy = w / 2.0, h / 2.0
    return [(cx + (x - cx) * scale, cy + (y - cy) * scale) for x, y in pts]


def _horizontal_gradient_mask(w, h, reverse=False):
    """A grayscale mask fading 255 -> 0 left to right (or the reverse)."""
    row = [int(255 * (1 - x / (w - 1))) for x in range(w)]
    if reverse:
        row = list(reversed(row))
    grad = Image.new("L", (w, 1))
    grad.putdata(row)
    return grad.resize((w, h))


def _draw_shield_body(im, pts, light_color, dark_color, outline_color, edge_color):
    d = ImageDraw.Draw(im)
    d.polygon(pts, fill=dark_color)

    # A real smooth gradient across the shield now ("maybe a bit more
    # gradient") instead of a hard-edged two-tone split - light on the
    # left fading into the dark base fill toward the right.
    shape_mask = Image.new("L", (SW, SH), 0)
    ImageDraw.Draw(shape_mask).polygon(pts, fill=255)
    grad_mask = _horizontal_gradient_mask(SW, SH)
    light_mask = ImageChops.multiply(shape_mask, grad_mask)
    light_layer = Image.new("RGBA", (SW, SH), light_color)
    im.paste(light_layer, (0, 0), light_mask)

    # Outer dark border (widened 5 -> 8, 2026-09-30 - "i meant the darker
    # border of the shield itself" - a previous request to widen "the
    # darker edge" had been misread as the crack's own shadow rim, not
    # this), then a thin inset light stroke just inside it - the "double
    # edged" look from the reference image. Widths scaled up by SCALE to
    # match the supersampled canvas.
    d.polygon(pts, outline=outline_color, width=8 * SCALE)
    inset_pts = _scaled_points(pts, 0.90)
    d.polygon(inset_pts, outline=edge_color, width=2 * SCALE)


def _finish(im, path):
    im.resize((W, H), Image.LANCZOS).save(path)


def make_resistance():
    """Intact shield - silver/grey, used as the resistance background AND
    the neutral Damage Type background."""
    im = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    pts = shield_points()
    _draw_shield_body(
        im, pts,
        light_color=(212, 214, 218, 255),
        dark_color=(140, 143, 148, 255),
        outline_color=(70, 72, 76, 255),
        edge_color=(238, 239, 241, 190),
    )
    _finish(im, os.path.join(ICONS_DIR, "shield.png"))


def make_weakness():
    """Broken shield - duller reddish, split by a jagged crack running
    from the top point all the way to the bottom point, used as the
    weakness background."""
    im = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    pts = shield_points()
    _draw_shield_body(
        im, pts,
        light_color=(206, 124, 108, 255),
        dark_color=(132, 70, 64, 255),
        outline_color=(80, 42, 38, 255),
        edge_color=(232, 184, 174, 190),
    )

    # Overshoots PAST the shield's own top (0.06) and bottom (0.97) points
    # into the transparent margin beyond the silhouette - erasing a bit of
    # already-empty canvas is harmless, and guarantees the cut fully
    # crosses the outer border stroke at both ends instead of stopping
    # just inside it ("they dont go over the edges of the actual shield").
    crack = [
        (SW * 0.50, SH * 0.02), (SW * 0.40, SH * 0.22), (SW * 0.58, SH * 0.38),
        (SW * 0.38, SH * 0.54), (SW * 0.56, SH * 0.70), (SW * 0.42, SH * 0.86),
        (SW * 0.50, SH * 0.99),
    ]

    # Darken the crack's edges (2026-09-29, "where the cracks are, darken
    # the edge a bit") - a wider dark stroke drawn FIRST along the same
    # path, then a narrower transparent gap erased on top of it, leaving a
    # thin dark rim/shadow visible on both sides of the actual break.
    #
    # CLIPPED to the shield's own silhouette ("the shadow effect must stop
    # at the edges of the shield") - unlike the crack path itself, which
    # deliberately overshoots past the tips so the erasure below fully
    # crosses the border, the dark rim must NOT bleed into that overshoot
    # margin, or it shows up as a dark smudge poking out past the border.
    # Built as a mask (crack-stroke shape AND the shield's own silhouette)
    # rather than drawn directly onto `im`, then pasted through that mask.
    dark_edge_color = (58, 28, 24, 255)
    shape_mask = Image.new("L", (SW, SH), 0)
    ImageDraw.Draw(shape_mask).polygon(pts, fill=255)
    dark_line_mask = Image.new("L", (SW, SH), 0)
    ImageDraw.Draw(dark_line_mask).line(crack, fill=255, width=16 * SCALE, joint="curve")
    clipped_dark_mask = ImageChops.multiply(dark_line_mask, shape_mask)
    im.paste(Image.new("RGBA", (SW, SH), dark_edge_color), (0, 0), clipped_dark_mask)

    mask = Image.new("L", (SW, SH), 0)
    md = ImageDraw.Draw(mask)
    md.line(crack, fill=255, width=10 * SCALE, joint="curve")
    im.paste((0, 0, 0, 0), (0, 0), mask)

    _finish(im, os.path.join(ICONS_DIR, "shield_broken.png"))


if __name__ == "__main__":
    make_resistance()
    make_weakness()
    print("wrote %s and %s" % (
        os.path.join(ICONS_DIR, "shield.png"),
        os.path.join(ICONS_DIR, "shield_broken.png"),
    ))
