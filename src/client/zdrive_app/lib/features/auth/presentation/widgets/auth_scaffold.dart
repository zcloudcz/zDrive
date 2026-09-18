import 'package:flutter/material.dart';

import '../../../../shared/l10n/app_localizations.dart';
import '../../../../shared/theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= _brandPanelBreakpoint;
            final formColumn = Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                // The brand panel already carries the lockup + tagline in the
                // wide layout — showing them again here duplicated the brand
                // (bug: two lockups on screen at once).
                child: _AuthColumn(l10n: l10n, showBrand: !isWide, child: child),
              ),
            );
            if (isWide) {
              return Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: _BrandPanel(color: AppTheme.brandPetrol, l10n: l10n),
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

/// Lockup + tagline above the form card, shown only in the narrow layout —
/// the wide layout's brand panel already carries them, so repeating them
/// here would show the brand twice on screen.
class _AuthColumn extends StatelessWidget {
  const _AuthColumn({required this.l10n, required this.showBrand, required this.child});

  final AppLocalizations l10n;
  final bool showBrand;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showBrand) ...[
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
          ],
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
