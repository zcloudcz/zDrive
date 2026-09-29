import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zdrive_app/features/auth/domain/auth_repository.dart';
import 'package:zdrive_app/features/auth/presentation/two_factor_cubit.dart';
import 'package:zdrive_app/features/auth/presentation/two_factor_settings_page.dart';
import 'package:zdrive_app/shared/l10n/app_localizations.dart';

class MockTwoFactorCubit extends MockCubit<TwoFactorState>
    implements TwoFactorCubit {}

void main() {
  late MockTwoFactorCubit cubit;

  const setup = TwoFactorSetup(
    secret: 'ABCDEFGHIJKLMNOP',
    otpAuthUri: 'otpauth://totp/zDrive:a%40b.com?secret=ABCDEFGHIJKLMNOP',
  );

  setUp(() => cubit = MockTwoFactorCubit());

  Future<AppLocalizations> pump(WidgetTester tester, TwoFactorState state) async {
    whenListen(
      cubit,
      const Stream<TwoFactorState>.empty(),
      initialState: state,
    );
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<TwoFactorCubit>.value(
        value: cubit,
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: TwoFactorSettingsPage(),
        ),
      ),
    );
    await tester.pump();
    return AppLocalizations.of(tester.element(find.byType(TwoFactorSettingsPage)))!;
  }

  testWidgets('off: asks for the password first, then starts setup with it', (
    tester,
  ) async {
    final l10n = await pump(tester, const TwoFactorOff());
    when(() => cubit.beginSetup(any())).thenAnswer((_) async {});

    // No password typed: nothing is sent.
    await tester.tap(find.text(l10n.twoFactorEnable));
    verifyNever(() => cubit.beginSetup(any()));

    await tester.enterText(find.byType(TextField), 'Password1');
    await tester.tap(find.text(l10n.twoFactorEnable));

    verify(() => cubit.beginSetup('Password1')).called(1);
  });

  testWidgets('Entra-only account: no setup is offered', (tester) async {
    final l10n = await pump(tester, const TwoFactorUnavailable());

    expect(find.text(l10n.twoFactorUnavailable), findsOneWidget);
    expect(find.text(l10n.twoFactorEnable), findsNothing);
  });

  testWidgets('enrolling: shows the QR code and the manual key, and '
      'confirms with the typed code', (tester) async {
    final l10n = await pump(tester, const TwoFactorEnrolling(setup));
    when(() => cubit.confirm(any())).thenAnswer((_) async {});

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text(setup.secret), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text(l10n.twoFactorConfirmButton));

    verify(() => cubit.confirm('123456')).called(1);
  });

  testWidgets('enrolling: an incomplete code is not submitted', (tester) async {
    final l10n = await pump(tester, const TwoFactorEnrolling(setup));

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text(l10n.twoFactorConfirmButton));

    verifyNever(() => cubit.confirm(any()));
  });

  testWidgets('recovery codes are listed and can be copied', (tester) async {
    final l10n = await pump(
      tester,
      const TwoFactorRecoveryCodes(['AAAAA-BBBBB', 'CCCCC-DDDDD']),
    );
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    expect(find.text('AAAAA-BBBBB'), findsOneWidget);
    expect(find.text('CCCCC-DDDDD'), findsOneWidget);

    await tester.tap(find.text(l10n.twoFactorCopyCodes));
    await tester.pump();

    expect(clipboard, 'AAAAA-BBBBB\nCCCCC-DDDDD');
  });

  testWidgets('on: disabling needs the password and a code', (tester) async {
    final l10n = await pump(tester, const TwoFactorOn());
    when(
      () => cubit.disable(
        password: any(named: 'password'),
        code: any(named: 'code'),
      ),
    ).thenAnswer((_) async {});

    expect(find.text(l10n.twoFactorStatusOn), findsOneWidget);
    await tester.tap(find.text(l10n.twoFactorDisable));
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'Password1');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.tap(find.text(l10n.twoFactorDisableConfirm));

    verify(() => cubit.disable(password: 'Password1', code: '123456')).called(1);
  });
}
