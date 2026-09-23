// Browser sessionStorage wrapper for the PKCE code_verifier/state pair —
// sessionStorage (not localStorage), so the value does not persist across
// tabs or browser restarts, matching the temporary, single-flow nature of
// a PKCE exchange.
export 'entra_session_storage_web.dart'
    if (dart.library.io) 'entra_session_storage_io.dart';
