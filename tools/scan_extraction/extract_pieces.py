"""Extracts individual physical tile pieces from a scan image.

A scan (models/scans/*.png) is one photo of several tile faces laid on a
white background, each at an arbitrary rotation, each printed with an
identifying label sticker (e.g. "7a"). This finds each separate piece,
rotates it upright, and crops it tightly.

Usage:
    python extract_pieces.py <scan.png> <output_dir>

Writes one PNG per detected piece to <output_dir>, named
"<scan_basename>_piece<N>.png". You still need to look at each output by
eye (see README.md in this folder) - background-color detection alone
cannot tell WHICH tile number a piece is, nor whether it came out
right-side-up or upside-down (a rotated rectangle's minimum-area bounding
box is ambiguous up to 180 degrees).
"""
import sys
import os
import cv2
import numpy as np


def find_pieces(img, min_area=50000):
    """Finds each separate physical piece on a white-background scan.
    Returns a list of (rotated_rect, area), sorted top-to-bottom then
    left-to-right.

    Deliberately does NOT dilate/bridge gaps before finding connected
    components. Bridging was tried (to guard against thin grid-line
    artifacts fragmenting a single piece) and made things worse: it merges
    genuinely separate pieces that happen to sit close together on the
    scan bed. In practice the raw (undilated) mask already separates
    pieces cleanly in the large majority of scans - grid lines and notch
    gaps don't fade close enough to background-white to fragment a piece,
    while the gap between two different pieces is bigger than that. The
    remaining case (pieces scanned touching with literally zero gap, no
    threshold value can fix this) isn't handled here - see README.md.
    """
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    _, mask = cv2.threshold(gray, 235, 255, cv2.THRESH_BINARY_INV)

    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(mask)
    pieces = []
    for label in range(1, num_labels):
        area = stats[label, cv2.CC_STAT_AREA]
        if area < min_area:
            continue
        ys, xs = np.nonzero(labels == label)
        points = np.column_stack([xs, ys]).astype(np.float32)
        rect = cv2.minAreaRect(points)
        pieces.append((rect, int(area)))

    pieces.sort(key=lambda p: (round(p[0][0][1] / 200), p[0][0][0]))
    return pieces


def crop_upright(img, rect, pad=6):
    """Rotates the image so `rect` becomes axis-aligned, then tightly crops it.

    minAreaRect's angle is only reliable for genuinely rectangular pieces.
    For an irregular outline (a zigzag/staircase shape, or a near-circular
    octagon-ish shape), the minimum-AREA bounding rect can legitimately
    sit at a diagonal that doesn't match the piece's own printed grid
    lines - in that case this crop will look tilted, and needs a manual
    angle correction (see README.md's Hough-line fitting approach) rather
    than trusting this function's output blindly.
    """
    (cx, cy), (w, h), angle = rect
    if w < h:
        w, h = h, w
        angle += 90

    M = cv2.getRotationMatrix2D((cx, cy), angle, 1.0)
    (img_h, img_w) = img.shape[:2]
    cos = abs(M[0, 0])
    sin = abs(M[0, 1])
    new_w = int(img_h * sin + img_w * cos)
    new_h = int(img_h * cos + img_w * sin)
    M[0, 2] += (new_w / 2) - cx
    M[1, 2] += (new_h / 2) - cy
    rotated = cv2.warpAffine(img, M, (new_w, new_h), borderValue=(255, 255, 255))

    rcx, rcy = new_w / 2, new_h / 2
    x0 = int(rcx - w / 2 - pad)
    y0 = int(rcy - h / 2 - pad)
    x1 = int(rcx + w / 2 + pad)
    y1 = int(rcy + h / 2 + pad)
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(new_w, x1), min(new_h, y1)
    return rotated[y0:y1, x0:x1]


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    scan_path, out_dir = sys.argv[1], sys.argv[2]
    img = cv2.imread(scan_path)
    if img is None:
        print(f"Failed to load {scan_path}")
        sys.exit(1)

    pieces = find_pieces(img)
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(scan_path))[0]
    print(f"{base}: found {len(pieces)} piece(s)")
    for i, (rect, area) in enumerate(pieces):
        crop = crop_upright(img, rect)
        out_path = os.path.join(out_dir, f"{base}_piece{i}.png")
        cv2.imwrite(out_path, crop)
        (cx, cy), (w, h), angle = rect
        print(f"  piece{i}: center=({cx:.0f},{cy:.0f}) size=({w:.0f}x{h:.0f}) "
              f"angle={angle:.1f} area={area:.0f} -> {out_path}")


if __name__ == "__main__":
    main()
