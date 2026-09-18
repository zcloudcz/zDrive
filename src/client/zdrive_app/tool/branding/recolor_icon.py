#!/usr/bin/env python3
"""Recolor the zDrive icon from the old navy/orange palette to brand petrol/amber.

Source of truth for the mark is `assets/branding/zdrive-icon.png` (1024x1024,
raster only — see docs/superpowers/specs/2026-09-18-ui-refresh-design.md
section 4.3). There is no vector master, so we recolor the raster directly.

The icon is flat line art anti-aliased against white: every pixel is either
solid navy/orange/white or a blend of one solid colour with white. We find,
per pixel, how far it sits along the "solid colour -> white" line (t), then
reconstruct the same blend using the new colour. This keeps anti-aliased
edges smooth instead of leaving a old-colour/new-colour seam a nearest-colour
swap would produce. Alpha is untouched.

Re-run after any change to the source icon:
    python tool/branding/recolor_icon.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]  # src/client/zdrive_app
SRC = ROOT / "assets" / "branding" / "zdrive-icon.png"

# Old palette (measured from the source PNG's pixel histogram).
OLD_NAVY = (23, 33, 44)
OLD_AMBER = (250, 131, 17)
WHITE = (255, 255, 255)

# New palette — owner decision, section 8 of the design spec.
NEW_PETROL = (0x00, 0x38, 0x40)
NEW_AMBER = (0xD5, 0x7E, 0x1C)

# Pixels whose projection onto the old-colour -> white line misses by more
# than this (Euclidean, 0-255 scale) are left untouched (already white, or
# unrelated noise).
TOLERANCE = 40.0


def _project(pixel: tuple[int, int, int], solid: tuple[int, int, int]) -> tuple[float, float]:
    """Return (t, residual) for `pixel` on the line solid -> WHITE.

    t=0 is pure `solid`, t=1 is pure white. `residual` is the distance from
    the pixel to its projection, i.e. how well the line explains the pixel.
    """
    sx, sy, sz = solid
    wx, wy, wz = WHITE
    dx, dy, dz = wx - sx, wy - sy, wz - sz
    denom = dx * dx + dy * dy + dz * dz
    px, py, pz = pixel[0] - sx, pixel[1] - sy, pixel[2] - sz
    t = (px * dx + py * dy + pz * dz) / denom
    t_clamped = max(0.0, min(1.0, t))
    proj = (sx + t_clamped * dx, sy + t_clamped * dy, sz + t_clamped * dz)
    residual = math.dist(pixel, proj)
    return t_clamped, residual


def _blend(new_solid: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(new_solid[i] + t * (WHITE[i] - new_solid[i])) for i in range(3))


def recolor(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            t_navy, err_navy = _project((r, g, b), OLD_NAVY)
            t_amber, err_amber = _project((r, g, b), OLD_AMBER)
            if err_navy <= TOLERANCE and err_navy <= err_amber:
                nr, ng, nb = _blend(NEW_PETROL, t_navy)
                px[x, y] = (nr, ng, nb, a)
            elif err_amber <= TOLERANCE:
                nr, ng, nb = _blend(NEW_AMBER, t_amber)
                px[x, y] = (nr, ng, nb, a)
            # else: leave as-is (white strokes, or noise outside tolerance)
    return im


def main() -> None:
    im = Image.open(SRC)
    out = recolor(im)
    out.save(SRC)
    print(f"Recoloured {SRC.relative_to(ROOT)} in place.")


if __name__ == "__main__":
    main()
