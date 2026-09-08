# Scan extraction pipeline

Turns a raw scan (`models/scans/<numbers><a|b>.png` - one photo of several
tile faces on a white background) into the finished textures used by
`models/floor/<N>.png` (one file per tile number, face `a` stacked on top
of face `b`).

Requires `opencv-python-headless` and `numpy` (`pip install
opencv-python-headless numpy`).

## Why this isn't fully automatic

Background-color segmentation reliably finds and crops each piece, but two
things need a human eye every time:

1. **Which tile number is which blob.** There's no OCR step - you look at
   each cropped piece and read its printed label sticker.
2. **Orientation.** A rectangle's minimum-area bounding box is ambiguous
   up to 180 degrees, so roughly half the pieces come out upside-down.
   There's no way to detect this from pixel data alone (a "detect the
   black label sticker's corner" heuristic was tried and abandoned - stone
   textures have plenty of other near-black shadow regions that trigger
   false positives).

So the actual workflow is: extract, look, correct, compose - not a single
batch command.

## Workflow

1. **Extract every piece from both scans of a group:**
   ```
   python extract_pieces.py models/scans/1-2-5-7a.png /tmp/out
   python extract_pieces.py models/scans/1-2-5-7b.png /tmp/out
   ```
   Prints how many pieces it found. If the count doesn't match the number
   of tile numbers in the filename, two pieces were scanned touching each
   other with zero gap (see Known limitations below).

2. **Look at each `_pieceN.png` output** to identify which tile number it
   is and whether it needs rotating. Use `rotate_piece.py` to fix it:
   ```
   python rotate_piece.py /tmp/out/1-2-5-7a_piece1.png 180 /tmp/out/7a_fixed.png
   ```
   Most pieces only need 0 or 180. If a piece's grid lines come out
   visibly tilted at some other angle (not a clean 90-degree step), that's
   `minAreaRect` picking a diagonal minimum-area fit for an irregular
   outline (a zigzag/staircase-shaped tile, or a near-circular
   octagon-ish one) - fit the real angle from the piece's own printed grid
   lines instead of guessing:
   ```python
   import cv2, numpy as np
   img = cv2.imread("piece.png")
   edges = cv2.Canny(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), 50, 150)
   lines = cv2.HoughLines(edges, 1, np.pi/720, threshold=250)
   # histogram the theta values, the dominant non-45-degree cluster
   # (45-degree corner-cut edges on octagon-ish tiles pollute the vote)
   # is your correction angle
   ```
   Sanity-check the result against the piece's `a`/`b` pair once both are
   done (step 4) - they must be mirror-image outlines of the same
   physical piece. If they visually mismatch (one landscape, one
   portrait, or noticeably different proportions), one of your rotations
   is wrong - trust the shape match over a rotation guess.

3. **Compose the two corrected faces into the final texture:**
   ```
   python compose_tile.py /tmp/out/7a_fixed.png 0 /tmp/out/7b_fixed.png 0 models/floor/7.png
   ```
   (First two rotation args can also be applied inline here instead of
   pre-rotating with `rotate_piece.py` - `compose_tile.py` rotates before
   composing either way.)

4. **View the composed result** one more time before treating it as done
   - this is the cheapest point to catch a wrong rotation, since both
   faces are visible stacked together and any outline mismatch jumps out.

## Known limitations

- **Touching pieces**: if two pieces were scanned with literally zero gap
  between them, `extract_pieces.py` reports fewer pieces than expected and
  merges them into one blob - no threshold value can separate touching
  regions by background color alone. Fix: crop the merged
  `_piece0.png` down to just the piece you need with a plain numpy slice
  (`img[:, x_start:x_end]`), picking bounds by eye. Only worth solving
  automatically if this turns out to be common - so far it's been 2 out
  of 20 scans (`1-2-5-7b.png`, `4-12b.png`).
- **Small overlap bleed**: pieces scanned close together (but not
  touching) sometimes leave a thin sliver of the neighboring piece at a
  crop's edge. Cosmetic only, not worth chasing given the padding is only
  a few pixels.
- Godot doesn't need a `.import` sidecar file created manually - it
  auto-generates one the next time the editor scans the project for new
  files. Just drop the composed PNG into `models/floor/` and open the
  editor once.
