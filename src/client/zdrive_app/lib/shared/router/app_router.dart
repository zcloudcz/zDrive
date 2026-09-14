import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_bloc.dart';
import '../../core/di/injection.dart';
import '../../core/events/remote_file_change_notifier.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/files/presentation/pages/file_browser_page.dart';
import '../../features/files/presentation/pages/search_page.dart';
import '../../features/files/presentation/pages/trash_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/photos/photos_support.dart';
import '../../features/photos/presentation/pages/albums_page.dart';
import '../../features/photos/presentation/pages/photos_tab.dart';
import '../../features/sync/data/pull_sync_service.dart';
import '../../features/sync/data/sync_coordinator.dart';
import '../../features/sync/data/sync_remote_data_source.dart';
import '../../core/storage/app_preferences.dart';
import '../../features/sync/presentation/sync_bloc.dart';
import '../../features/sync/presentation/sync_page.dart';
import '../../features/sync/sync_support.dart';

GoRouter createRouter(AuthBloc authBloc) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _AuthRefreshListenable(authBloc),
    redirect: (context, state) {
      final authState = authBloc.state;
      final isAuthenticated = authState is Authenticated;
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!isAuthenticated && !isAuthRoute) return '/login';
      if (isAuthenticated && isAuthRoute) return '/home/files';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      StatefulShellRoute.indexedStack(
        // SyncBloc lives here, not inside SyncPage: sync then runs for the
        // whole authenticated session (from login, via LoadSyncStatus)
        // rather than only while the sync page happens to be open, and
        // logout disposes this shell — stopping the poll timer and folder
        // watch along with it — instead of leaving them running headless.
        builder: (_, _, navigationShell) {
          // The redirect above already sends an unauthenticated visitor to
          // /login before this shell is ever built, so authBloc.state here
          // is always Authenticated — casting instead of silently falling
          // back keeps that invariant loud if it is ever violated.
          final userId = (authBloc.state as Authenticated).user.id;
          return buildSyncShellProvider(
            syncSupported: isDesktopSyncSupported,
            createBloc: () => SyncBloc(
              dataSource: getIt<SyncRemoteDataSource>(),
              syncCoordinator: getIt<SyncCoordinator>(),
              pullService: getIt<PullSyncService>(),
              preferences: getIt<AppPreferences>(),
              remoteChangeNotifier: getIt<RemoteFileChangeNotifier>(),
              userId: userId,
            ),
            child: HomePage(navigationShell: navigationShell),
          );
        },
        branches: buildHomeBranches(),
      ),
    ],
  );
}

/// Builds the sync feature's ancestor [BlocProvider] for the authenticated
/// shell — factored out of the route builder above so a widget test can
/// pump it directly, with mocked dependencies, without needing a real
/// [GoRouter]. Eager (`lazy: false`): the default `lazy: true` only calls
/// [createBloc] once something reads the bloc from context, which used to
/// mean sync did not start until the user opened the Sync page — `lazy:
/// false` makes flutter_bloc call it as soon as this provider is built
/// instead, i.e. at login (PR #16 review round 1, F1).
///
/// [syncSupported] is threaded in rather than read from [Platform] here so
/// a test can drive both branches without depending on the host OS: when
/// false, [createBloc] is never called at all, so [SyncCoordinator] (and
/// the Platform.isWindows-reading dependencies constructing it would pull
/// in) is never resolved — desktop sync must not be built for web or
/// mobile (PR #16 review round 2, blocking finding 1).
Widget buildSyncShellProvider({
  required bool syncSupported,
  required SyncBloc Function() createBloc,
  required Widget child,
}) {
  if (!syncSupported) return child;
  return BlocProvider<SyncBloc>(
    lazy: false,
    create: (_) => createBloc()..add(const LoadSyncStatus()),
    child: child,
  );
}

/// The shell's branches, one per bottom-nav tab — factored out so a test can
/// check the Photos branch (and its `/home/photos` route) is gated by
/// [photosEnabled] without building a real [GoRouter]. Order matches
/// [buildHomeDestinations] in `home_page.dart`: [StatefulNavigationShell]
/// indexes branches positionally, so the two lists must stay in lockstep.
List<StatefulShellBranch> buildHomeBranches({bool photosEnabled = kPhotosEnabled}) {
  return [
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: '/home/files',
          builder: (_, _) => const FileBrowserPage(),
          routes: [
            GoRoute(
              path: 'folder/:folderId',
              builder: (_, state) => FileBrowserPage(
                folderId: state.pathParameters['folderId'],
              ),
            ),
            GoRoute(
              path: 'trash',
              builder: (_, _) => const TrashPage(),
            ),
            GoRoute(
              path: 'search',
              builder: (_, _) => const SearchPage(),
            ),
          ],
        ),
      ],
    ),
    if (photosEnabled)
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/home/photos',
            builder: (_, _) => const PhotosTab(),
            routes: [
              GoRoute(
                path: 'albums',
                builder: (_, _) => const AlbumsPage(),
              ),
            ],
          ),
        ],
      ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: '/home/settings',
          builder: (_, _) => const SyncPage(),
        ),
      ],
    ),
  ];
}

class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(AuthBloc authBloc) {
    authBloc.stream.listen((_) => notifyListeners());
  }
}
