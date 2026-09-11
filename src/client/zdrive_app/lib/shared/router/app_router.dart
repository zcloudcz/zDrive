import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_bloc.dart';
import '../../core/di/injection.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/files/presentation/pages/file_browser_page.dart';
import '../../features/files/presentation/pages/search_page.dart';
import '../../features/files/presentation/pages/trash_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/photos/presentation/pages/albums_page.dart';
import '../../features/photos/presentation/pages/photos_tab.dart';
import '../../features/sync/data/pull_sync_service.dart';
import '../../features/sync/data/sync_coordinator.dart';
import '../../features/sync/data/sync_remote_data_source.dart';
import '../../core/storage/app_preferences.dart';
import '../../features/sync/presentation/sync_bloc.dart';
import '../../features/sync/presentation/sync_page.dart';

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
        builder: (_, _, navigationShell) => BlocProvider<SyncBloc>(
          create: (_) => SyncBloc(
            dataSource: getIt<SyncRemoteDataSource>(),
            syncCoordinator: getIt<SyncCoordinator>(),
            pullService: getIt<PullSyncService>(),
            preferences: getIt<AppPreferences>(),
          )..add(const LoadSyncStatus()),
          child: HomePage(navigationShell: navigationShell),
        ),
        branches: [
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
        ],
      ),
    ],
  );
}

class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(AuthBloc authBloc) {
    authBloc.stream.listen((_) => notifyListeners());
  }
}
