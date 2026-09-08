"""Stacks a tile's two correctly-oriented face crops (a on top, b on
bottom) into the final models/floor/<N>.png texture.

Usage:
    python compose_tile.py <a.png> <a_degrees> <b.png> <b_degrees> <out.png> [target_width]

Both inputs are resized independently to a common width (preserving each
one's own aspect ratio - the two faces' raw crop dimensions rarely match
exactly due to independent cropping/rotation, but should be close; if the
composed result looks obviously mismatched in scale, that's usually a
sign one of the two rotations is wrong, not a resizing bug - the two
faces are mirror images of the same physical outline and should visually
line up). target_width defaults to 1000px. Output is RGBA (alpha always
255 - matches the existing hand-made models/floor/*.png files, which use
RGBA but keep the white background opaque rather than transparent).
"""
import sys
import cv2
import numpy as np
from rotate_piece import rotate


def resize_to_width(img, w):
    h = int(img.shape[0] * (w / img.shape[1]))
    return cv2.resize(img, (w, h), interpolation=cv2.INTER_AREA)


def main():
    if len(sys.argv) < 6:
        print(__doc__)
        sys.exit(1)
    a_path, a_deg, b_path, b_deg, out_path = sys.argv[1:6]
    target_width = int(sys.argv[6]) if len(sys.argv) > 6 else 1000

    a = rotate(cv2.imread(a_path), float(a_deg))
    b = rotate(cv2.imread(b_path), float(b_deg))

    a = resize_to_width(a, target_width)
    b = resize_to_width(b, target_width)

    combined = np.vstack([a, b])
    combined_rgba = cv2.cvtColor(combined, cv2.COLOR_BGR2BGRA)
    combined_rgba[:, :, 3] = 255

    cv2.imwrite(out_path, combined_rgba)
    print(f"wrote {out_path} shape={combined_rgba.shape}")


if __name__ == "__main__":
    main()
