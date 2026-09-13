import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/auth/auth_bloc.dart';
import 'core/auth/token_storage.dart';
import 'core/di/injection.dart';
import 'features/auth/domain/auth_repository.dart';
import 'features/sync/data/sync_coordinator.dart';
import 'features/sync/sync_support.dart';
import 'shared/router/app_router.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/theme_cubit.dart';
import 'core/storage/app_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await configureDependencies();
  await getIt.allReady();
  runApp(const ZDriveApp());
}

class ZDriveApp extends StatelessWidget {
  const ZDriveApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authBloc = AuthBloc(
      authRepository: getIt<AuthRepository>(),
      tokenStorage: getIt<TokenStorage>(),
      // core/auth must not depend on the sync feature directly — passed in
      // as a plain callback instead (see AuthBloc's own doc comment). Only
      // wired on platforms that run desktop sync at all, and resolved
      // lazily inside the closure rather than here in build(): getIt<
      // SyncCoordinator>() would construct PullSyncService/
      // LocalChangeScanner, whose constructors read Platform.isWindows,
      // which throws on web (PR #16 review round 2, blocking finding 1).
      beforeLogout: isDesktopSyncSupported ? () => getIt<SyncCoordinator>().endSession() : null,
    )..add(const CheckAuthStatus());

    final router = createRouter(authBloc);

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: authBloc),
        BlocProvider(
          create: (_) => ThemeCubit(getIt<AppPreferences>()),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp.router(
            title: 'zDrive',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeMode,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          );
        },
      ),
    );
  }
}
