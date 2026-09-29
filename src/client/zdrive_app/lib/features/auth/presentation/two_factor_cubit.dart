import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/diagnostics/diagnostics.dart';
import '../domain/auth_repository.dart';

sealed class TwoFactorState extends Equatable {
  const TwoFactorState();

  @override
  List<Object?> get props => [];
}

final class TwoFactorLoading extends TwoFactorState {
  const TwoFactorLoading();
}

final class TwoFactorLoadFailed extends TwoFactorState {
  final Object error;

  const TwoFactorLoadFailed(this.error);

  @override
  List<Object?> get props => [error];
}

/// Entra-only account: no local password, so nothing to set up here.
final class TwoFactorUnavailable extends TwoFactorState {
  const TwoFactorUnavailable();
}

final class TwoFactorOff extends TwoFactorState {
  final bool busy;
  final Object? error;

  const TwoFactorOff({this.busy = false, this.error});

  @override
  List<Object?> get props => [busy, error];
}

/// Secret issued, waiting for the first code from the authenticator app.
final class TwoFactorEnrolling extends TwoFactorState {
  final TwoFactorSetup setup;
  final bool busy;
  final Object? error;

  const TwoFactorEnrolling(this.setup, {this.busy = false, this.error});

  @override
  List<Object?> get props => [setup.secret, setup.otpAuthUri, busy, error];
}

/// Shown once, right after enabling — the server never returns them again.
final class TwoFactorRecoveryCodes extends TwoFactorState {
  final List<String> codes;

  const TwoFactorRecoveryCodes(this.codes);

  @override
  List<Object?> get props => [codes];
}

final class TwoFactorOn extends TwoFactorState {
  final bool busy;
  final Object? error;

  const TwoFactorOn({this.busy = false, this.error});

  @override
  List<Object?> get props => [busy, error];
}

class TwoFactorCubit extends Cubit<TwoFactorState> {
  final AuthRepository _repository;

  TwoFactorCubit(this._repository) : super(const TwoFactorLoading());

  Future<void> load() async {
    emit(const TwoFactorLoading());
    try {
      final user = await _repository.getCurrentUser();
      if (!user.hasPassword) {
        emit(const TwoFactorUnavailable());
      } else if (user.twoFactorEnabled) {
        emit(const TwoFactorOn());
      } else {
        emit(const TwoFactorOff());
      }
    } catch (e, st) {
      Diagnostics.error('auth.two_factor_load_failed', e, st);
      emit(TwoFactorLoadFailed(e));
    }
  }

  Future<void> beginSetup() async {
    emit(const TwoFactorOff(busy: true));
    try {
      emit(TwoFactorEnrolling(await _repository.setupTwoFactor()));
    } catch (e, st) {
      Diagnostics.error('auth.two_factor_setup_failed', e, st);
      emit(TwoFactorOff(error: e));
    }
  }

  Future<void> confirm(String code) async {
    final current = state;
    if (current is! TwoFactorEnrolling || current.busy) return;
    emit(TwoFactorEnrolling(current.setup, busy: true));
    try {
      emit(TwoFactorRecoveryCodes(await _repository.confirmTwoFactor(code)));
    } catch (e, st) {
      Diagnostics.error('auth.two_factor_confirm_failed', e, st);
      emit(TwoFactorEnrolling(current.setup, error: e));
    }
  }

  void finishEnrollment() => emit(const TwoFactorOn());

  Future<void> disable({required String password, required String code}) async {
    final current = state;
    if (current is! TwoFactorOn || current.busy) return;
    emit(const TwoFactorOn(busy: true));
    try {
      await _repository.disableTwoFactor(password: password, code: code);
      emit(const TwoFactorOff());
    } catch (e, st) {
      Diagnostics.error('auth.two_factor_disable_failed', e, st);
      emit(TwoFactorOn(error: e));
    }
  }
}
