# Branding asset scripts

The zDrive mark exists only as a raster
(`assets/branding/zdrive-icon.png`, 1024x1024) — there is no SVG or other
vector source in the repo. These scripts recolour that raster to the brand
petrol/amber palette and regenerate every derived size from it.

Requires Python 3 with Pillow (`pip install pillow` if `python -c "import PIL"`
fails).

## Scope

Per the design spec's owner decisions (section 8 of
`docs/superpowers/specs/2026-09-18-ui-refresh-design.md`), the new icon
ships on **web and Windows only** in this PR. Neither script touches
`android/` or `ios/`.

## Re-running

1. **`recolor_icon.py`** — recolours `assets/branding/zdrive-icon.png` in
   place: old navy `#17212C` field -> brand petrol `#003840`, old orange
   `#FA8311` accent -> brand amber `#D57E1C`. White line art is left
   untouched. Anti-aliased edges are preserved by projecting each pixel onto
   the old-colour -> white blend line and reconstructing the same blend with
   the new colour, instead of a flat nearest-colour swap.

   ```bash
   python tool/branding/recolor_icon.py
   ```

   Only run this once per palette change — running it twice is a no-op
   (there's nothing left near the old colours to match), but it's not
   designed to be idempotent against a *different* re-recolour.

2. **`generate_sizes.py`** — regenerates every derived raster from the
   (already recoloured) 1024x1024 master:

   ```bash
   python tool/branding/generate_sizes.py
   ```

   Writes:
   - `web/favicon.png`, `web/icons/Icon-{192,512}.png`,
     `web/icons/Icon-maskable-{192,512}.png` (opaque, petrol-filled square —
     matches the pre-existing files' format)
   - `assets/branding/zdrive-mark{,@2x,@3x}.png` (128/256/384px, for the
     `BrandLockup` widget's mark — base size is 128 logical px, well above
     the ~28-32px it's shown at in an AppBar, so downscaling at paint time
     stays sharp on HiDPI screens instead of upscaling a small bitmap)
   - `windows/runner/resources/app_icon.ico` (16/24/32/48/64/128/256)

   Note: the 1024px master has no alpha channel / rounded corners (checked
   pixel (0,0) — fully opaque petrol), so the mark renders as a square tile,
   not a rounded shape. If the master ever gains real alpha, these outputs
   will carry it through unchanged (`keep_alpha=True` doesn't add rounding,
   it only preserves whatever the source has).

## After running

`web/manifest.json` (`theme_color`/`background_color`) and the
`<meta name="theme-color">` tag in `web/index.html` are edited by hand, not
by these scripts — they're a single string each, and
`test/web/branding_colors_test.dart` guards the values.
