import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_bloc.dart';
import '../../../shared/widgets/brand_lockup.dart';
import '../../../shared/widgets/windows_download_button.dart';
import '../../../shared/widgets/app_settings_menu.dart';
import '../../photos/photos_support.dart';

/// Below this width the shell uses the bottom [NavigationBar] (as before);
/// at or above it, a side [NavigationRail] takes over so desktop/web don't
/// waste the bottom edge (design spec 4.5, P1 app shell).
const double kNavigationRailBreakpoint = 840;

class HomePage extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const HomePage({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Single source of truth for both nav widgets so their destinations
    // (order, labels, the Photos gate) cannot drift between them.
    final destinations = buildHomeDestinations(l10n);
    final isWide =
        MediaQuery.sizeOf(context).width >= kNavigationRailBreakpoint;

    void onDestinationSelected(int index) {
      navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          WindowsDownloadButton(
            compact: MediaQuery.sizeOf(context).width < 600,
          ),
          const AppSettingsMenu(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.logout,
            onPressed: () {
              context.read<AuthBloc>().add(const LogoutRequested());
            },
          ),
        ],
      ),
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: onDestinationSelected,
                  labelType: NavigationRailLabelType.all,
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: BrandLockup(size: 24),
                  ),
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: navigationShell),
              ],
            )
          : navigationShell,
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: destinations,
            ),
    );
  }
}

/// The bottom-nav entries, one per shell branch — extracted so a test can
/// check the Photos destination is gated by [photosEnabled] without a real
/// [StatefulNavigationShell]. Order matches [buildHomeBranches] in
/// `app_router.dart` (see its doc comment for why the two must stay in sync).
List<NavigationDestination> buildHomeDestinations(
  AppLocalizations l10n, {
  bool photosEnabled = kPhotosEnabled,
}) {
  return [
    NavigationDestination(
      icon: const Icon(Icons.folder_outlined),
      selectedIcon: const Icon(Icons.folder),
      label: l10n.files,
    ),
    if (photosEnabled)
      NavigationDestination(
        icon: const Icon(Icons.photo_outlined),
        selectedIcon: const Icon(Icons.photo),
        label: l10n.photos,
      ),
    NavigationDestination(
      icon: const Icon(Icons.settings_outlined),
      selectedIcon: const Icon(Icons.settings),
      label: l10n.settings,
    ),
  ];
}

class PlaceholderTab extends StatelessWidget {
  final String featureName;

  const PlaceholderTab({super.key, required this.featureName});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.comingSoon(featureName),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
