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
  String get entraSignInButton => 'ZCLOUDアカウントでサインイン';

  @override
  String get entraStateMismatch => 'サインインを確認できませんでした。もう一度お試しください。';

  @override
  String get entraSignInDenied => 'サインインがキャンセルされました。';

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
  String get noFilesBody => 'ファイルをアップロードするか、フォルダを作成して始めましょう。';

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
  String get allowDelete => '削除を許可';

  @override
  String get allowDeleteHelp => '削除された項目は所有者のごみ箱に移動します。';

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
  String get authInvalidCredentials => 'メールアドレスまたはパスワードが正しくありません。';

  @override
  String get authEmailAlreadyRegistered => 'このメールアドレスのアカウントは既に存在します。';

  @override
  String get authEntraAccountExists =>
      'このメールアドレスのアカウントは既に別の方法で登録されています。パスワードまたはその方法でサインインしてください。';

  @override
  String get authEntraVerificationFailed =>
      'ZCLOUDアカウントを確認できませんでした。もう一度お試しいただくか、サポートにお問い合わせください。';

  @override
  String get authEntraUnavailable => 'ZCLOUDサインインは現在利用できません。';

  @override
  String get authTooManyAttempts => '試行回数が多すぎます。しばらくしてからもう一度お試しください。';

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

  @override
  String get shareNotFoundTitle => 'リンクが見つかりません';

  @override
  String get shareNotFoundMessage => 'この共有リンクは無効か、期限切れか、削除されています。';

  @override
  String get sharePasswordProtectedTitle => 'パスワードが必要です';

  @override
  String get sharePasswordProtectedMessage =>
      'この共有リンクはパスワードで保護されていますが、まだサポートされていません。';

  @override
  String get openZDrive => 'zDriveを開く';

  @override
  String get download => 'ダウンロード';

  @override
  String shareAvailableUntil(Object date) {
    return '$dateまで利用可能';
  }

  @override
  String get shareWhatIsZDrive => 'zDriveとは?';

  @override
  String get shareFooterTagline => 'zDriveによって保護されています';

  @override
  String get shareReplaceFile => 'ファイルを置き換える';

  @override
  String get shareDeleteConfirmMessage => 'このアイテムは所有者のゴミ箱に移動されます。';

  @override
  String get shareOverwriteTitle => '既存のファイルを置き換えますか?';

  @override
  String shareOverwriteMessage(Object name) {
    return '「$name」という名前のファイルは既に存在します。アップロードすると新しいバージョンに置き換わります。';
  }

  @override
  String get shareReplaceConfirm => '置き換える';

  @override
  String get shareErrorNotAllowed => 'このリンクではその操作は許可されていません。';

  @override
  String get shareErrorNameExists => '同じ名前のファイルまたはフォルダーが既に存在します。';

  @override
  String get shareErrorQuotaExceeded => '所有者のストレージが満杯です。';

  @override
  String get shareErrorTooManyUploads =>
      '処理中のアップロードが多すぎます。しばらくしてからもう一度お試しください。';

  @override
  String get tagline => 'あなたのファイルを、どこでも。';

  @override
  String get authBenefitSync => 'すべてのデバイスで同期';

  @override
  String get authBenefitShare => 'ファイルとフォルダを安全に共有';

  @override
  String get authBenefitSecure => '常に暗号化されたストレージ';

  @override
  String get offlineCloudOnly => 'クラウドのみ';

  @override
  String get offlineDownloading => 'ダウンロード中';

  @override
  String get offlineAvailable => 'このデバイスで利用可能';

  @override
  String get offlineAlwaysKeep => '常にこのデバイスに保持';

  @override
  String get keepOnDevice => '常にこのデバイスに保持する';

  @override
  String get freeUpSpace => '空き容量を増やす';

  @override
  String freeUpSkippedUnsynced(int count) {
    return '$count 件をこのデバイスに保持しました: 未同期の変更があります';
  }

  @override
  String get cloudMigrationTitle => 'このデバイスの空き容量を増やしますか?';

  @override
  String cloudMigrationBody(int count, String size) {
    return '同期フォルダ内のファイルはクラウドに保管され、必要なときにだけダウンロードされるようになりました。このデバイスから削除できるファイル: $count 件、最大 $size。';
  }

  @override
  String get cloudMigrationReassure =>
      'ファイルはクラウドとWebで引き続き利用でき、いつでも再ダウンロードできます。まだ同期されていない変更があるファイルは常に保持されます。';

  @override
  String get cloudMigrationKeepAll => 'すべてこのデバイスに保持する';

  @override
  String get cloudMigrationLater => '後で決める';

  @override
  String get cloudMigrationWorking => '空き容量を確保しています…';

  @override
  String cloudMigrationFreed(int count, String size) {
    return '$count 件を解放しました ($size)';
  }

  @override
  String freeUpKeptPinned(int count) {
    return '$count 件をこのデバイスに保持しました: 常に保持';
  }

  @override
  String get cloudMigrationKeeping => 'すべてをこのデバイスに保持しています…';

  @override
  String get twoFactorTitle => '2段階認証';

  @override
  String get twoFactorPrompt => '認証アプリに表示される6桁のコードを入力してください。';

  @override
  String get twoFactorRecoveryPrompt => 'リカバリーコードのいずれかを入力してください。';

  @override
  String get twoFactorCodeLabel => '6桁のコード';

  @override
  String get twoFactorRecoveryCodeLabel => 'リカバリーコード';

  @override
  String get twoFactorVerifyButton => '確認';

  @override
  String get twoFactorUseRecoveryCode => 'リカバリーコードを使用';

  @override
  String get twoFactorUseAuthenticator => '認証アプリのコードを使用';

  @override
  String get twoFactorBackToSignIn => 'サインインに戻る';

  @override
  String get authTwoFactorInvalidCode => 'コードが正しくありません。もう一度お試しください。';

  @override
  String get authTwoFactorChallengeExpired =>
      'このサインインの有効期限が切れました。戻ってもう一度サインインしてください。';

  @override
  String get twoFactorStatusOff =>
      '2段階認証はオフです。オンにすると、サインイン時に認証アプリのコードが必要になります。';

  @override
  String get twoFactorStatusOn => '2段階認証はオンです。';

  @override
  String get twoFactorUnavailable =>
      'このアカウントでは2段階認証を利用できません。サインインのセキュリティは ZCLOUD アカウントで管理されています。';

  @override
  String get twoFactorEnable => 'オンにする';

  @override
  String get twoFactorSetupInstructions =>
      'このQRコードを認証アプリでスキャンするか、セットアップキーを手動で入力してください。その後、アプリに表示される6桁のコードを入力します。';

  @override
  String get twoFactorSetupKey => 'セットアップキー';

  @override
  String get twoFactorCopy => 'コピー';

  @override
  String get twoFactorCopied => 'コピーしました';

  @override
  String get twoFactorConfirmButton => '確認してオンにする';

  @override
  String get twoFactorRecoveryCodesTitle => 'リカバリーコードを保存してください';

  @override
  String get twoFactorRecoveryCodesInfo =>
      '認証アプリにアクセスできなくなった場合、各コードは1回だけ使用できます。今回のみ表示されます。';

  @override
  String get twoFactorCopyCodes => 'すべてのコードをコピー';

  @override
  String get twoFactorDone => '完了';

  @override
  String get twoFactorDisable => 'オフにする';

  @override
  String get twoFactorDisableInfo =>
      '2段階認証をオフにするには、パスワードと現在のコード(またはリカバリーコード)を入力してください。';

  @override
  String get twoFactorDisableConfirm => '2段階認証をオフにする';

  @override
  String get twoFactorPasswordInvalid => 'パスワードが正しくありません。';

  @override
  String get twoFactorInvalidPasswordOrCode => 'パスワードまたはコードが正しくありません。';

  @override
  String get twoFactorEnablePasswordInfo => '2段階認証の設定を始めるには、パスワードを入力してください。';
}
