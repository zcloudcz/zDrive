import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class AppPreferences {
  static const _boxName = 'preferences';
  static const _themeModeKey = 'theme_mode';
  static const _localeKey = 'locale';
  static const _syncFolderPathKey = 'sync_folder_path';
  static const _syncOwnerUserIdKey = 'sync_owner_user_id';
  static const _cloudOnlyMigrationDecidedKey = 'cloud_only_migration_decided';

  late Box<dynamic> _box;

  @PostConstruct(preResolve: true)
  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  ThemeMode get themeMode {
    final value = _box.get(_themeModeKey, defaultValue: 'system') as String;
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _box.put(_themeModeKey, mode.name);
  }

  String get locale => _box.get(_localeKey, defaultValue: 'en') as String;

  Future<void> setLocale(String locale) async {
    await _box.put(_localeKey, locale);
  }

  /// The local folder pull mirrors files into. Null until the user picks one
  /// — there is no default, per the "one designated folder" design: syncing
  /// must not start writing into a folder the user never chose.
  String? get syncFolderPath => _box.get(_syncFolderPathKey) as String?;

  Future<void> setSyncFolderPath(String path) async {
    await _box.put(_syncFolderPathKey, path);
  }

  /// Forgets the chosen sync folder — called by
  /// [SyncCoordinator.startSession] when a different account is signing in
  /// than the one this machine's sync state currently belongs to.
  Future<void> clearSyncFolderPath() async {
    await _box.delete(_syncFolderPathKey);
  }

  /// The user id this machine's sync state (mirror, device id, chosen
  /// folder) currently belongs to. Null until the first sync session this
  /// machine has ever had. Checked by [SyncCoordinator.startSession] so a
  /// different account logging in on the same machine does not inherit the
  /// previous one's sync state — see that method's doc comment.
  String? get syncOwnerUserId => _box.get(_syncOwnerUserIdKey) as String?;

  Future<void> setSyncOwnerUserId(String userId) async {
    await _box.put(_syncOwnerUserIdKey, userId);
  }

  Future<void> clearSyncOwnerUserId() async {
    await _box.delete(_syncOwnerUserIdKey);
  }

  /// Whether this device already went through the one-time "free up the
  /// space the old mirror-everything sync used" decision (see
  /// [SyncCoordinator.pendingCloudOnlyMigration]). Per device, not per
  /// account: it describes this machine's sync folder, and a new account gets
  /// a cleared mirror anyway. Only ever set after an explicit choice (or when
  /// there is nothing to decide), never merely because the dialog was shown.
  bool get cloudOnlyMigrationDecided =>
      _box.get(_cloudOnlyMigrationDecidedKey, defaultValue: false) as bool;

  Future<void> setCloudOnlyMigrationDecided() async {
    await _box.put(_cloudOnlyMigrationDecidedKey, true);
  }
}
