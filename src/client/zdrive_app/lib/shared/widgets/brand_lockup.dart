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

  /// Use the monochrome (all-white) mark, for placement on a dark/petrol
  /// background where the full-colour mark's petrol field would disappear.
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
                // ponytail: monochrome variant reuses the colour mark tinted
                // white; a dedicated mono asset is only worth it if the tint
                // ever looks wrong against a real dark background.
                color: monochrome ? Colors.white : null,
              ),
            ),
          ),
          SizedBox(width: size * 0.4),
          // The outer Semantics already declares the 'zDrive' label; exclude
          // the Text's own implicit label so it isn't merged in twice.
          ExcludeSemantics(child: Text('zDrive', style: titleStyle)),
        ],
      ),
    );
  }
}
