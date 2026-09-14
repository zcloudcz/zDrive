import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_bloc.dart';
import '../../photos/photos_support.dart';

class HomePage extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const HomePage({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.logout,
            onPressed: () {
              context.read<AuthBloc>().add(const LogoutRequested());
            },
          ),
        ],
      ),
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: buildHomeDestinations(l10n),
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
