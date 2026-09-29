import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zdrive_app/features/auth/domain/auth_repository.dart';
import 'package:zdrive_app/features/auth/domain/user.dart';
import 'package:zdrive_app/features/auth/presentation/two_factor_cubit.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repository;

  const setup = TwoFactorSetup(secret: 'SECRET', otpAuthUri: 'otpauth://x');

  setUp(() => repository = MockAuthRepository());

  User user({bool enabled = false, bool hasPassword = true}) => User(
    id: '1',
    email: 'a@b.com',
    displayName: 'A',
    twoFactorEnabled: enabled,
    hasPassword: hasPassword,
  );

  group('load', () {
    blocTest<TwoFactorCubit, TwoFactorState>(
      'password account without 2FA -> off',
      build: () {
        when(() => repository.getCurrentUser()).thenAnswer((_) async => user());
        return TwoFactorCubit(repository);
      },
      act: (c) => c.load(),
      expect: () => [const TwoFactorLoading(), const TwoFactorOff()],
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'password account with 2FA -> on',
      build: () {
        when(
          () => repository.getCurrentUser(),
        ).thenAnswer((_) async => user(enabled: true));
        return TwoFactorCubit(repository);
      },
      act: (c) => c.load(),
      expect: () => [const TwoFactorLoading(), const TwoFactorOn()],
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'Entra-only account (no password) -> unavailable, no setup offered',
      build: () {
        when(
          () => repository.getCurrentUser(),
        ).thenAnswer((_) async => user(hasPassword: false));
        return TwoFactorCubit(repository);
      },
      act: (c) => c.load(),
      expect: () => [const TwoFactorLoading(), const TwoFactorUnavailable()],
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'a failed load -> load failed',
      build: () {
        when(() => repository.getCurrentUser()).thenThrow(Exception('boom'));
        return TwoFactorCubit(repository);
      },
      act: (c) => c.load(),
      expect: () => [const TwoFactorLoading(), isA<TwoFactorLoadFailed>()],
    );
  });

  group('enrollment', () {
    blocTest<TwoFactorCubit, TwoFactorState>(
      'beginSetup -> enrolling with the issued secret',
      build: () {
        when(
          () => repository.setupTwoFactor(password: 'pw'),
        ).thenAnswer((_) async => setup);
        return TwoFactorCubit(repository);
      },
      act: (c) => c.beginSetup('pw'),
      expect: () => [
        const TwoFactorOff(busy: true),
        const TwoFactorEnrolling(setup),
      ],
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'beginSetup failure -> off with the error',
      build: () {
        when(
          () => repository.setupTwoFactor(password: any(named: 'password')),
        ).thenThrow(Exception('boom'));
        return TwoFactorCubit(repository);
      },
      act: (c) => c.beginSetup('pw'),
      expect: () => [
        const TwoFactorOff(busy: true),
        isA<TwoFactorOff>().having((s) => s.error, 'error', isNotNull),
      ],
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'confirm with a valid code -> recovery codes, then on after finish',
      build: () {
        when(
          () => repository.confirmTwoFactor('123456'),
        ).thenAnswer((_) async => ['AAAAA-BBBBB', 'CCCCC-DDDDD']);
        return TwoFactorCubit(repository);
      },
      seed: () => const TwoFactorEnrolling(setup),
      act: (c) async {
        await c.confirm('123456');
        c.finishEnrollment();
      },
      expect: () => [
        const TwoFactorEnrolling(setup, busy: true),
        const TwoFactorRecoveryCodes(['AAAAA-BBBBB', 'CCCCC-DDDDD']),
        const TwoFactorOn(),
      ],
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'confirm with a wrong code stays on the enrollment step with the error',
      build: () {
        when(
          () => repository.confirmTwoFactor(any()),
        ).thenThrow(Exception('invalid'));
        return TwoFactorCubit(repository);
      },
      seed: () => const TwoFactorEnrolling(setup),
      act: (c) => c.confirm('000000'),
      expect: () => [
        const TwoFactorEnrolling(setup, busy: true),
        isA<TwoFactorEnrolling>().having((s) => s.error, 'error', isNotNull),
      ],
    );
  });

  group('disable', () {
    blocTest<TwoFactorCubit, TwoFactorState>(
      'valid password and code -> off',
      build: () {
        when(
          () => repository.disableTwoFactor(
            password: any(named: 'password'),
            code: any(named: 'code'),
          ),
        ).thenAnswer((_) async {});
        return TwoFactorCubit(repository);
      },
      seed: () => const TwoFactorOn(),
      act: (c) => c.disable(password: 'pw', code: '123456'),
      expect: () => [const TwoFactorOn(busy: true), const TwoFactorOff()],
    );

    blocTest<TwoFactorCubit, TwoFactorState>(
      'rejected -> stays on with the error',
      build: () {
        when(
          () => repository.disableTwoFactor(
            password: any(named: 'password'),
            code: any(named: 'code'),
          ),
        ).thenThrow(Exception('invalid'));
        return TwoFactorCubit(repository);
      },
      seed: () => const TwoFactorOn(),
      act: (c) => c.disable(password: 'pw', code: '000000'),
      expect: () => [
        const TwoFactorOn(busy: true),
        isA<TwoFactorOn>().having((s) => s.error, 'error', isNotNull),
      ],
    );
  });
}
