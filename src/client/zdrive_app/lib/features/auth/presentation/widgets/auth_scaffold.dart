import 'package:flutter/material.dart';

import '../../../../shared/l10n/app_localizations.dart';
import '../../../../shared/widgets/brand_lockup.dart';

/// Shared shell for the login and register pages (design spec 4.5, section
/// "Login / register"). Below [_brandPanelBreakpoint] it stacks the lockup
/// above a single form card; at or above it, a petrol brand panel sits next
/// to the form instead of leaving the wide viewport empty.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.appBar});

  /// The page's form content, placed inside the themed card.
  final Widget child;

  /// Optional app bar — the register page keeps its back-to-login arrow.
  final PreferredSizeWidget? appBar;

  static const _brandPanelBreakpoint = 1000.0;

  // Brand surfaces use the literal zcloud.cz petrol, not the raised
  // `primary` tone used for interactive elements (spec section 8, owner
  // decision 1).
  static const _brandPetrol = Color(0xFF003840);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final formColumn = Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _AuthColumn(l10n: l10n, child: child),
              ),
            );
            if (constraints.maxWidth >= _brandPanelBreakpoint) {
              return Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: _BrandPanel(color: _brandPetrol, l10n: l10n),
                  ),
                  Expanded(flex: 6, child: formColumn),
                ],
              );
            }
            return formColumn;
          },
        ),
      ),
    );
  }
}

/// Lockup + tagline above the form card — shown on every screen size (the
/// wireframe in spec 4.5 keeps it in the form column even on wide layouts).
class _AuthColumn extends StatelessWidget {
  const _AuthColumn({required this.l10n, required this.child});

  final AppLocalizations l10n;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrandLockup(size: 48),
          const SizedBox(height: 8),
          Text(
            l10n.tagline,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 0,
            color: colors.surfaceContainerLow,
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ],
      ),
    );
  }
}

/// Wide-screen-only petrol panel (spec 4.5's "brand panel"): mono lockup,
/// tagline, and a short list of value bullets.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.color, required this.l10n});

  final Color color;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final bullets = [
      l10n.authBenefitSync,
      l10n.authBenefitShare,
      l10n.authBenefitSecure,
    ];
    return Container(
      color: color,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandLockup(size: 40, monochrome: true),
              const SizedBox(height: 24),
              Text(
                l10n.tagline,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              for (final bullet in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          bullet,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
