import 'package:flutter/material.dart';

/// Brand mark + wordmark, per design spec section 4.3.
///
/// Not wired into any screen yet — that is PRs 3-5. This PR only ships the
/// widget and its asset so those PRs can consume it.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.size = 28,
    this.monochrome = false,
  });

  /// Height of the mark, in logical pixels. The wordmark scales with it via
  /// [Theme]'s `titleLarge` style rather than a derived font size.
  final double size;

  /// On-dark placement (e.g. the petrol header/panel): the wordmark is drawn
  /// white. The mark image is never tinted — it is an opaque tile (petrol
  /// field + white line art + amber arc), and tinting it paints every pixel
  /// solid white. Left untinted, its own petrol field merges into a
  /// `#003840` background and the line art/arc stay visible.
  final bool monochrome;

  @override
  Widget build(BuildContext context) {
    // titleLarge carries Typography.material2021's own explicit text colour
    // (Colors.black87 by default), which wins over any inherited
    // DefaultTextStyle/AppBar foreground colour — so the wordmark must be
    // coloured explicitly here rather than relying on what wraps this
    // widget. monochrome (on-dark placements, e.g. the petrol header) is
    // always white; the default (on-light) variant follows onSurface so it
    // still adapts to light/dark ColorSchemes.
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: monochrome ? Colors.white : Theme.of(context).colorScheme.onSurface,
        );
    return Semantics(
      label: 'zDrive',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            // The source PNG is an opaque square tile, not a rounded icon —
            // clip it so it reads as an app icon on light surfaces (share
            // page header etc) instead of a flat square.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.22),
              child: Image.asset(
                'assets/branding/zdrive-mark.png',
                height: size,
                width: size,
                // The source asset is 128px logical (384px @3x) so it stays
                // sharp when downscaled to the AppBar's ~28-32px; medium
                // filtering keeps that downscale crisp instead of blurring it.
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          SizedBox(width: size * 0.4),
          // The outer Semantics already declares the 'zDrive' label; exclude
          // the Text's own implicit label so it isn't merged in twice.
          // Flexible lets the wordmark shrink/ellipsize instead of
          // overflowing the Row when the mark is large and the available
          // width is narrow (e.g. 320px at 200% text scaling).
          Flexible(
            child: ExcludeSemantics(
              child: Text(
                'zDrive',
                style: titleStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
