import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/auth/auth_bloc.dart';
import 'core/auth/token_storage.dart';
import 'core/di/injection.dart';
import 'features/auth/domain/auth_repository.dart';
import 'shared/router/app_router.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/theme_cubit.dart';
import 'core/storage/app_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  configureDependencies();
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
