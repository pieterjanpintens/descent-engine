"""Rotates one extracted piece image, either by a clean 90-degree step or
an arbitrary angle - used to fix orientation issues extract_pieces.py
can't resolve on its own (see README.md).

Usage:
    python rotate_piece.py <in.png> <degrees> <out.png>

<degrees> can be any number. 90/180/270 use cv2.rotate (exact, no
interpolation); anything else does a full affine rotation with the canvas
expanded to avoid clipping (useful for fixing a piece that came out tilted
by some odd angle - fit the correction angle from the piece's own grid
lines, e.g. via Hough line detection, rather than guessing).
"""
import sys
import cv2

def rotate(img, degrees):
    if degrees == 90:
        return cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE)
    if degrees == 180:
        return cv2.rotate(img, cv2.ROTATE_180)
    if degrees == 270:
        return cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)
    if degrees == 0:
        return img

    h, w = img.shape[:2]
    M = cv2.getRotationMatrix2D((w / 2, h / 2), degrees, 1.0)
    cos, sin = abs(M[0, 0]), abs(M[0, 1])
    new_w = int(h * sin + w * cos)
    new_h = int(h * cos + w * sin)
    M[0, 2] += (new_w / 2) - w / 2
    M[1, 2] += (new_h / 2) - h / 2
    return cv2.warpAffine(img, M, (new_w, new_h), borderValue=(255, 255, 255))


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    in_path, degrees, out_path = sys.argv[1], float(sys.argv[2]), sys.argv[3]
    img = cv2.imread(in_path)
    result = rotate(img, degrees)
    cv2.imwrite(out_path, result)
    print(f"wrote {out_path} shape={result.shape}")


if __name__ == "__main__":
    main()
