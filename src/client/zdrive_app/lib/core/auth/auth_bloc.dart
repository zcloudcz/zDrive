import 'dart:developer';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/auth/domain/auth_repository.dart';
import '../../features/auth/domain/user.dart';
import 'token_storage.dart';

// --- Events ---

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

final class CheckAuthStatus extends AuthEvent {
  const CheckAuthStatus();
}

final class LoginRequested extends AuthEvent {
  final String email;
  final String password;

  const LoginRequested({required this.email, required this.password});

  @override
  List<Object?> get props => [email, password];
}

final class RegisterRequested extends AuthEvent {
  final String email;
  final String password;
  final String displayName;

  const RegisterRequested({
    required this.email,
    required this.password,
    required this.displayName,
  });

  @override
  List<Object?> get props => [email, password, displayName];
}

final class LogoutRequested extends AuthEvent {
  const LogoutRequested();
}

/// Dispatched once the web client already holds an Entra access token (after
/// the browser-side PKCE code exchange — see EntraCallbackPage). Mirrors
/// [LoginRequested]: exchanges it with our own backend and reuses the same
/// post-login states.
final class EntraLoginRequested extends AuthEvent {
  final String accessToken;

  const EntraLoginRequested({required this.accessToken});

  @override
  List<Object?> get props => [accessToken];
}

// --- States ---

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

final class AuthInitial extends AuthState {
  const AuthInitial();
}

final class AuthLoading extends AuthState {
  const AuthLoading();
}

final class Authenticated extends AuthState {
  final User user;

  const Authenticated(this.user);

  @override
  List<Object?> get props => [user];
}

final class Unauthenticated extends AuthState {
  const Unauthenticated();
}

final class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

// --- Bloc ---

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final TokenStorage _tokenStorage;
  // Called before the repository logout, so the sync feature's own state
  // (mirror, device id, chosen folder) is cleared before the account is
  // actually logged out — wired in main.dart to
  // getIt<SyncCoordinator>().endSession so core/auth does not depend on the
  // sync feature directly. Optional: nothing in this class requires it.
  final Future<void> Function()? _beforeLogout;

  AuthBloc({
    required AuthRepository authRepository,
    required TokenStorage tokenStorage,
    Future<void> Function()? beforeLogout,
  }) : _authRepository = authRepository,
       _tokenStorage = tokenStorage,
       _beforeLogout = beforeLogout,
       super(const AuthInitial()) {
    on<CheckAuthStatus>(_onCheckAuthStatus);
    on<LoginRequested>(_onLoginRequested);
    on<EntraLoginRequested>(_onEntraLoginRequested);
    on<RegisterRequested>(_onRegisterRequested);
    on<LogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onCheckAuthStatus(
    CheckAuthStatus event,
    Emitter<AuthState> emit,
  ) async {
    final hasTokens = await _tokenStorage.hasTokens;
    if (!hasTokens) {
      emit(const Unauthenticated());
      return;
    }
    try {
      final user = await _authRepository.getCurrentUser();
      emit(Authenticated(user));
    } catch (_) {
      await _tokenStorage.clear();
      // A failed session check is a logout too — the stored tokens turned
      // out to be no good — so sync must stop here as well, not only from
      // the logout button (PR #16 review round 1, F3).
      await _runBeforeLogout();
      emit(const Unauthenticated());
    }
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      final user = await _authRepository.login(
        email: event.email,
        password: event.password,
      );
      emit(Authenticated(user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onEntraLoginRequested(
    EntraLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      final user = await _authRepository.loginWithEntra(event.accessToken);
      emit(Authenticated(user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onRegisterRequested(
    RegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      final user = await _authRepository.register(
        email: event.email,
        password: event.password,
        displayName: event.displayName,
      );
      emit(Authenticated(user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _runBeforeLogout();
    await _authRepository.logout();
    emit(const Unauthenticated());
  }

  /// Runs [_beforeLogout], if one was given, swallowing any failure — a
  /// storage or sqlite error there (PR #16 review round 1, non-blocking
  /// note) must not stop the user from actually logging out. Shared by
  /// every path that moves this bloc from an authenticated session to
  /// [Unauthenticated], not just the logout button.
  Future<void> _runBeforeLogout() async {
    try {
      await _beforeLogout?.call();
    } catch (e, st) {
      log(
        'beforeLogout failed; logging out anyway',
        error: e,
        stackTrace: st,
        name: 'AuthBloc',
      );
    }
  }
}
