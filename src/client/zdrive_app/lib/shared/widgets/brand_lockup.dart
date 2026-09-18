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
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        );
    return Semantics(
      label: 'zDrive',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Image.asset(
              'assets/branding/zdrive-lockup.png',
              height: size,
              width: size,
              // ponytail: monochrome variant reuses the colour mark tinted
              // white; a dedicated mono asset is only worth it if the tint
              // ever looks wrong against a real dark background.
              color: monochrome ? Colors.white : null,
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
