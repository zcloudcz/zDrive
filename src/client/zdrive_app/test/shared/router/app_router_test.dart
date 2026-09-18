import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/core/auth/auth_bloc.dart';
import 'package:zdrive_app/core/di/injection.dart';
import 'package:zdrive_app/core/events/remote_file_change_notifier.dart';
import 'package:zdrive_app/core/storage/app_preferences.dart';
import 'package:zdrive_app/features/auth/domain/user.dart';
import 'package:zdrive_app/features/auth/presentation/login_page.dart';
import 'package:zdrive_app/features/files/data/file_dtos.dart';
import 'package:zdrive_app/features/share_link/data/share_link_data_source.dart';
import 'package:zdrive_app/features/share_link/presentation/pages/share_link_page.dart';
import 'package:zdrive_app/features/sync/data/pull_sync_service.dart';
import 'package:zdrive_app/features/sync/data/sync_coordinator.dart';
import 'package:zdrive_app/features/sync/data/sync_remote_data_source.dart';
import 'package:zdrive_app/features/sync/presentation/sync_bloc.dart';
import 'package:zdrive_app/features/home/presentation/home_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:zdrive_app/shared/l10n/app_localizations_en.dart';
import 'package:zdrive_app/shared/router/app_router.dart';

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class MockShareLinkDataSource extends Mock implements ShareLinkDataSource {}

class MockSyncRemoteDataSource extends Mock implements SyncRemoteDataSource {}

class MockSyncCoordinator extends Mock implements SyncCoordinator {}

class MockPullSyncService extends Mock implements PullSyncService {}

class MockAppPreferences extends Mock implements AppPreferences {}

class MockRemoteFileChangeNotifier extends Mock implements RemoteFileChangeNotifier {}

void main() {
  // Router-level regression test for PR #16 review round 1, F1: the shell's
  // BlocProvider<SyncBloc> used the default `lazy: true`, so nothing created
  // the bloc — and nothing ran LoadSyncStatus — until the Sync page happened
  // to be visited. Building the real GoRouter here would need a full
  // authenticated AuthBloc/GoRouter setup just to reach the shell; instead
  // this drives [buildSyncShellProvider] directly, the function the router
  // itself calls to build that provider (app_router.dart), with mocked
  // SyncBloc dependencies standing in for getIt.
  late MockSyncRemoteDataSource mockDataSource;
  late MockSyncCoordinator mockSyncCoordinator;
  late MockPullSyncService mockPullService;
  late MockAppPreferences mockPreferences;
  late MockRemoteFileChangeNotifier mockRemoteChangeNotifier;

  setUp(() {
    mockDataSource = MockSyncRemoteDataSource();
    mockSyncCoordinator = MockSyncCoordinator();
    mockPullService = MockPullSyncService();
    mockPreferences = MockAppPreferences();
    mockRemoteChangeNotifier = MockRemoteFileChangeNotifier();
    when(() => mockSyncCoordinator.startSession(any())).thenAnswer((_) async {});
    when(() => mockDataSource.getDevices()).thenAnswer((_) async => []);
  });

  testWidgets(
      'syncSupported: true builds the sync provider eagerly: LoadSyncStatus '
      'is handled without any descendant ever reading the bloc (F1) — '
      'proves lazy: false, not the default lazy: true a widget-triggered '
      'read would also satisfy',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildSyncShellProvider(
        syncSupported: true,
        createBloc: () => SyncBloc(
          dataSource: mockDataSource,
          syncCoordinator: mockSyncCoordinator,
          pullService: mockPullService,
          preferences: mockPreferences,
          remoteChangeNotifier: mockRemoteChangeNotifier,
          userId: 'user-1',
        ),
        // Deliberately a plain widget that never reads SyncBloc from
        // context — if create() only ran because something asked for the
        // bloc (the old lazy: true default), this test would see neither
        // call below.
        child: const SizedBox(),
      ),
    ));
    await tester.pump();

    verify(() => mockSyncCoordinator.startSession('user-1')).called(1);
    verify(() => mockDataSource.getDevices()).called(1);
  });

  testWidgets(
      'syncSupported: false never calls createBloc at all — desktop sync '
      '(and, through it, SyncCoordinator/PullSyncService/'
      'LocalChangeScanner, whose constructors read Platform.isWindows) '
      'must never be built for web or mobile (PR #16 review round 2, '
      'blocking finding 1)',
      (tester) async {
    var createBlocCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: buildSyncShellProvider(
        syncSupported: false,
        createBloc: () {
          createBlocCalled = true;
          return SyncBloc(
            dataSource: mockDataSource,
            syncCoordinator: mockSyncCoordinator,
            pullService: mockPullService,
            preferences: mockPreferences,
            remoteChangeNotifier: mockRemoteChangeNotifier,
            userId: 'user-1',
          );
        },
        child: const SizedBox(),
      ),
    ));
    await tester.pump();

    expect(createBlocCalled, isFalse);
    verifyZeroInteractions(mockSyncCoordinator);
    verifyZeroInteractions(mockDataSource);
  });

  group('buildHomeBranches', () {
    // photosEnabled is threaded in as a parameter (default: kPhotosEnabled,
    // a compile-time bool.fromEnvironment) rather than read directly, so this
    // can drive both branches without a `--dart-define` per test run.
    test('photosEnabled: false omits the Photos branch and its route entirely', () {
      final branches = buildHomeBranches(photosEnabled: false);

      expect(branches, hasLength(2));
      final paths = branches
          .expand((b) => b.routes)
          .whereType<GoRoute>()
          .map((r) => r.path);
      expect(paths, isNot(contains('/home/photos')));
    });

    test('photosEnabled: true includes the Photos branch and its route', () {
      final branches = buildHomeBranches(photosEnabled: true);

      expect(branches, hasLength(3));
      final paths = branches
          .expand((b) => b.routes)
          .whereType<GoRoute>()
          .map((r) => r.path);
      expect(paths, contains('/home/photos'));
    });

    // StatefulNavigationShell matches branches to destinations POSITIONALLY:
    // it calls goBranch(index) with the index of the tapped destination. The
    // two lists are built in separate files under the same flag, so if one
    // ever gains or drops an entry without the other, tapping a tab silently
    // opens the wrong page — or throws on an index that has no branch. The
    // doc comments on both builders say so; this asserts it, for both values
    // of the flag, which the separate tests above cannot (each only checks
    // its own list).
    test('branches and destinations stay the same length under both flag '
        'values — the shell maps them by position', () {
      final l10n = AppLocalizationsEn();

      for (final photosEnabled in [false, true]) {
        expect(
          buildHomeBranches(photosEnabled: photosEnabled).length,
          buildHomeDestinations(l10n, photosEnabled: photosEnabled).length,
          reason: 'photosEnabled: $photosEnabled',
        );
      }
    });
  });

  group('/s/:token public route', () {
    // The full createRouter(authBloc) redirect logic, exercised end to end —
    // unlike the tests above, which drive buildSyncShellProvider/
    // buildHomeBranches directly. ShareLinkPage resolves ShareLinkDataSource
    // from getIt, so it is registered with a never-resolving stub: these
    // tests only assert on which page the router lands on, not on the
    // share's own loaded content (covered by share_link_page_test.dart).
    late MockAuthBloc authBloc;

    setUp(() {
      authBloc = MockAuthBloc();
      getIt.registerSingleton<ShareLinkDataSource>(MockShareLinkDataSource());
      when(() => getIt<ShareLinkDataSource>().getShareLink(any()))
          .thenAnswer((_) => Completer<({ShareDto share, FileDto file})>().future);
    });

    tearDown(() async {
      await getIt.reset();
    });

    // /home/files (redirected-to /login when unauthenticated) needs
    // AuthBloc reachable via context — LoginPage reads it directly, the
    // same way main.dart provides it above the router rather than inside it.
    Widget buildApp(GoRouter router) {
      return BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );
    }

    testWidgets('unauthenticated /s/abc renders ShareLinkPage, not /login',
        (tester) async {
      whenListen(authBloc, const Stream<AuthState>.empty(),
          initialState: const Unauthenticated());
      // go() before the first pump: createRouter's initialLocation is
      // '/login', and letting that first frame actually build before
      // navigating away — for the authenticated variant below — would
      // transiently build the authenticated /home/files shell, which needs
      // SyncBloc dependencies this test never registers.
      final router = createRouter(authBloc)..go('/s/abc');

      await tester.pumpWidget(buildApp(router));

      expect(find.byType(ShareLinkPage), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets('authenticated /s/abc also renders ShareLinkPage, unchanged',
        (tester) async {
      whenListen(authBloc, const Stream<AuthState>.empty(),
          initialState: const Authenticated(
              User(id: 'u1', email: 'a@b.com', displayName: 'A')));
      final router = createRouter(authBloc)..go('/s/abc');

      await tester.pumpWidget(buildApp(router));

      expect(find.byType(ShareLinkPage), findsOneWidget);
    });

    testWidgets('unauthenticated /home/files is still redirected to /login '
        '— the guard is exempted only for /s/, not loosened generally',
        (tester) async {
      whenListen(authBloc, const Stream<AuthState>.empty(),
          initialState: const Unauthenticated());
      final router = createRouter(authBloc)..go('/home/files');

      await tester.pumpWidget(buildApp(router));

      expect(find.byType(LoginPage), findsOneWidget);
    });
  });
}
