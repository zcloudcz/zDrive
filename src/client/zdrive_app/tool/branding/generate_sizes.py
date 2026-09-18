#!/usr/bin/env python3
"""Regenerate every derived branding raster from the recoloured 1024x1024 master.

Run `recolor_icon.py` first (or whenever the master's colours change), then
this script to refresh every downstream size. See tool/branding/README.md.

Scope note (owner decision, design spec section 8): the new icon ships on
web and Windows only for this PR — this script does NOT touch anything
under android/ or ios/.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]  # src/client/zdrive_app
MASTER = ROOT / "assets" / "branding" / "zdrive-icon.png"

# (output path relative to ROOT, size, drop alpha)
WEB_TARGETS = [
    ("web/favicon.png", 32, False),
    ("web/icons/Icon-192.png", 192, False),
    ("web/icons/Icon-512.png", 512, False),
    ("web/icons/Icon-maskable-192.png", 192, False),
    ("web/icons/Icon-maskable-512.png", 512, False),
]

# In-app mark, used by BrandLockup. Base size is 128 logical px, not the
# AppBar's ~28-32px display size: BrandLockup downscales at paint time
# (filterQuality: medium), which stays crisp; upscaling a small bitmap on
# HiDPI screens would not.
#
# NOTE: the 1024 master has no alpha/rounded corners (checked pixel (0,0) =
# opaque petrol) — it is a square tile, not a shape cut out of transparency.
# `keep_alpha=True` here only preserves whatever alpha the master has (none
# at the moment); it does not invent rounding.
MARK_TARGETS = [
    ("assets/branding/zdrive-mark.png", 128, True),
    ("assets/branding/zdrive-mark@2x.png", 256, True),
    ("assets/branding/zdrive-mark@3x.png", 384, True),
]

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def _resized(master: Image.Image, size: int, keep_alpha: bool) -> Image.Image:
    im = master.resize((size, size), Image.LANCZOS)
    if keep_alpha:
        return im
    # The old web/icons files were opaque RGB (flat navy field, no
    # transparency) — match that so the manifest icons keep filling the
    # square background instead of showing checkerboard behind them.
    bg = Image.new("RGB", im.size, (0x00, 0x38, 0x40))
    bg.paste(im, mask=im.split()[3])
    return bg


def main() -> None:
    master = Image.open(MASTER).convert("RGBA")

    for rel_path, size, keep_alpha in WEB_TARGETS + MARK_TARGETS:
        out_path = ROOT / rel_path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        _resized(master, size, keep_alpha).save(out_path)
        print(f"wrote {rel_path} ({size}x{size})")

    ico_path = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    frames = [master.resize((s, s), Image.LANCZOS) for s in ICO_SIZES]
    frames[-1].save(
        ico_path,
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
        append_images=frames[:-1],
    )
    print(f"wrote {ico_path.relative_to(ROOT)} ({ICO_SIZES})")


if __name__ == "__main__":
    main()
