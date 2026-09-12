import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether this platform runs the desktop sync engine (folder pull/push
/// loop) at all — the one place this is decided, so every call site that
/// would otherwise construct [SyncCoordinator] or its dependencies (which
/// read `Platform.isWindows`/`Platform.isMacOS` in their constructors, or
/// throw via [CurrentDevicePlatform] for any other OS) can check this
/// first instead. `kIsWeb` is checked before touching [Platform] at all:
/// `dart:io`'s `Platform` throws `UnsupportedError` when actually called on
/// web, so the short-circuit must come first (PR #16 review round 2,
/// blocking finding 1).
bool get isDesktopSyncSupported => !kIsWeb && (Platform.isWindows || Platform.isMacOS);
