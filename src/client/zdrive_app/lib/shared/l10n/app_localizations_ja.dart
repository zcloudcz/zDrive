// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get exportDiagnostics => '診断ログをエクスポート';

  @override
  String get diagnosticsPreparing => '診断ログを準備しています…';

  @override
  String get diagnosticsSaved => '診断ログを保存しました。';

  @override
  String get diagnosticsFailed => 'ログをエクスポートできませんでした。もう一度お試しください。';

  @override
  String get aboutApp => 'このアプリについて';

  @override
  String get exitApp => '終了';

  @override
  String get exitFailed => 'アプリを終了できませんでした。もう一度お試しください。';

  @override
  String get appVersionFailed => 'アプリのバージョンを読み込めませんでした。';

  @override
  String appVersion(String version) {
    return 'バージョン $version';
  }

  @override
  String get appTitle => 'zDrive';

  @override
  String get downloadForWindows => 'Windows版をダウンロード';

  @override
  String get login => 'ログイン';

  @override
  String get register => '登録';

  @override
  String get email => 'メールアドレス';

  @override
  String get password => 'パスワード';

  @override
  String get confirmPassword => 'パスワードの確認';

  @override
  String get displayName => '表示名';

  @override
  String get files => 'ファイル';

  @override
  String get photos => '写真';

  @override
  String get settings => '設定';

  @override
  String get logout => 'ログアウト';

  @override
  String get createAccount => 'アカウントを作成';

  @override
  String get loginButton => 'ログイン';

  @override
  String get registerButton => 'アカウントを作成';

  @override
  String get emailRequired => 'メールアドレスを入力してください';

  @override
  String get invalidEmail => '有効なメールアドレスを入力してください';

  @override
  String get passwordTooShort => 'パスワードは8文字以上で入力してください';

  @override
  String get passwordsDontMatch => 'パスワードが一致しません';

  @override
  String get displayNameRequired => '表示名を入力してください';

  @override
  String get loginFailed => 'ログインに失敗しました。入力内容を確認してください。';

  @override
  String get registerFailed => '登録に失敗しました。もう一度お試しください。';

  @override
  String comingSoon(String feature) {
    return '$featureは近日公開予定です';
  }

  @override
  String get folders => 'フォルダー';

  @override
  String get newItem => '新規';

  @override
  String get newFolder => '新しいフォルダー';

  @override
  String get uploadFile => 'ファイルをアップロード';

  @override
  String get rename => '名前を変更';

  @override
  String get delete => '削除';

  @override
  String get share => '共有';

  @override
  String get restore => '復元';

  @override
  String get emptyTrash => 'ごみ箱を空にする';

  @override
  String get trash => 'ごみ箱';

  @override
  String get search => '検索';

  @override
  String get clearSearch => '検索をクリア';

  @override
  String get refresh => '更新';

  @override
  String get gridView => 'グリッド表示';

  @override
  String get listView => 'リスト表示';

  @override
  String get noFiles => 'ファイルがありません';

  @override
  String get createFolder => 'フォルダーを作成';

  @override
  String get folderName => 'フォルダー名';

  @override
  String get enterFolderName => 'フォルダー名を入力';

  @override
  String get fileDeleted => 'ファイルを削除しました';

  @override
  String get fileRestored => 'ファイルを復元しました';

  @override
  String get shareLink => '共有リンク';

  @override
  String get copyLink => 'リンクをコピー';

  @override
  String get linkCopied => 'リンクをコピーしました';

  @override
  String get permission => 'アクセス権';

  @override
  String get readOnly => '読み取り専用';

  @override
  String get readWrite => '読み取りと書き込み';

  @override
  String get expiresAt => '有効期限';

  @override
  String get never => '無期限';

  @override
  String get uploadProgress => 'アップロード中…';

  @override
  String get downloadProgress => 'ダウンロード中…';

  @override
  String get uploadComplete => 'アップロードが完了しました';

  @override
  String get confirmDelete => '削除の確認';

  @override
  String get confirmEmptyTrash => 'ごみ箱内のすべての項目を完全に削除しますか？';

  @override
  String get cancel => 'キャンセル';

  @override
  String get ok => 'OK';

  @override
  String get retry => '再試行';

  @override
  String get loadMore => 'さらに読み込む';

  @override
  String get noPhotos => '写真はまだありません';

  @override
  String get albums => 'アルバム';

  @override
  String get noAlbums => 'アルバムはまだありません';

  @override
  String get newAlbum => '新しいアルバム';

  @override
  String get albumName => 'アルバム名';

  @override
  String get syncStatus => '同期の状態';

  @override
  String get syncDevices => 'デバイス';

  @override
  String get syncNoDevices => '登録済みのデバイスはありません';

  @override
  String get syncNeverSynced => 'まだ同期していません';

  @override
  String get syncChooseFolder => '同期フォルダーを選択';

  @override
  String get syncFolderNotConfigured => 'このデバイスの同期を開始するには、ローカルフォルダーを選択してください。';

  @override
  String get syncPulling => '同期中…';

  @override
  String get syncDeviceUpToDate => 'このデバイスは最新の状態です。';

  @override
  String get syncItemsSkipped => '一部の項目を同期できませんでした';

  @override
  String get syncSkippedItems => 'スキップされた項目';

  @override
  String get syncFolderNotEmptyTitle => 'フォルダーが空ではありません';

  @override
  String get syncFolderNotEmptyMessage =>
      'このフォルダーにはすでにファイルがあります。同期機能が作成したファイル以外は上書きされません。競合するファイルはそのまま残り、スキップされた項目として表示されます。';

  @override
  String get syncUnsupportedPlatform => '同期はWindows版とmacOS版のアプリで利用できます';

  @override
  String get versionHistory => 'バージョン履歴';

  @override
  String get noVersions => 'バージョンはまだありません';

  @override
  String get restoreVersion => '復元';

  @override
  String versionLabel(int number) {
    return 'バージョン $number';
  }

  @override
  String get confirmRestoreVersion => 'このバージョンを復元しますか？';

  @override
  String get versionRestored => 'バージョンを復元しました';

  @override
  String get latestVersion => '最新';

  @override
  String get close => '閉じる';

  @override
  String get errorNoConnection => 'サーバーに接続できませんでした。接続を確認して、もう一度お試しください。';

  @override
  String get errorServiceUnavailable => 'この機能は一時的に利用できません。後でもう一度お試しください。';

  @override
  String get errorRequestFailed => 'リクエストを完了できませんでした。';

  @override
  String get syncConnecting => '接続中…';

  @override
  String get syncDownloading => 'ダウンロード中';

  @override
  String get syncScanning => 'フォルダーをスキャン中';

  @override
  String get syncHashing => 'ファイルの内容を比較中';

  @override
  String get syncUploading => 'アップロード中';

  @override
  String get syncDeleting => '削除を適用中';

  @override
  String get syncDiscovering => '項目を検索中 — 総数はまだ不明です';

  @override
  String syncProgressCounts(int completed, int total, int remaining) {
    return '$total件中$completed件完了 · 残り$remaining件';
  }

  @override
  String syncProgressFailures(int count) {
    return '$count件の項目が失敗しました';
  }

  @override
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  ) {
    return '$transferred / $total · 残り$remaining';
  }

  @override
  String syncKnownProgressCounts(int completed, int total, int remaining) {
    return '検出済みの項目：$total件中$completed件完了 · 残り$remaining件';
  }

  @override
  String get updateRetry => '更新を再試行';

  @override
  String get updateRestarting => '再起動前に同期を完了しています…';

  @override
  String get updateRestart => '再起動して更新';

  @override
  String updateDownloading(int percent) {
    return '更新をダウンロード中：$percent%';
  }

  @override
  String updateReady(String version) {
    return '更新 $version の準備ができました。次回起動時にインストールされます。';
  }

  @override
  String get updateFailed => '自動更新に失敗しました。zDriveを引き続き使用し、後で再試行できます。';
}
