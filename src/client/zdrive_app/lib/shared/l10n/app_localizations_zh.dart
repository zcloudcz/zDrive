// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get exportDiagnostics => '导出诊断日志';

  @override
  String get diagnosticsPreparing => '正在准备诊断日志…';

  @override
  String get diagnosticsSaved => '诊断日志已保存。';

  @override
  String get diagnosticsFailed => '无法导出日志，请重试。';

  @override
  String get aboutApp => '关于';

  @override
  String get exitApp => '退出';

  @override
  String get exitFailed => '无法退出应用。请重试。';

  @override
  String get appVersionFailed => '无法加载应用版本。';

  @override
  String appVersion(String version) {
    return '版本 $version';
  }

  @override
  String get appTitle => 'zDrive';

  @override
  String get downloadForWindows => '下载 Windows 版';

  @override
  String get login => '登录';

  @override
  String get register => '注册';

  @override
  String get email => '电子邮箱';

  @override
  String get password => '密码';

  @override
  String get confirmPassword => '确认密码';

  @override
  String get displayName => '显示名称';

  @override
  String get files => '文件';

  @override
  String get photos => '照片';

  @override
  String get settings => '设置';

  @override
  String get logout => '退出登录';

  @override
  String get createAccount => '创建账号';

  @override
  String get loginButton => '登录';

  @override
  String get entraSignInButton => '使用您的 ZCLOUD 账户登录';

  @override
  String get entraStateMismatch => '无法验证登录。请重试。';

  @override
  String get entraSignInDenied => '登录已取消。';

  @override
  String get registerButton => '创建账号';

  @override
  String get emailRequired => '请输入电子邮箱';

  @override
  String get invalidEmail => '请输入有效的电子邮箱地址';

  @override
  String get passwordTooShort => '密码必须至少包含 8 个字符';

  @override
  String get passwordsDontMatch => '两次输入的密码不一致';

  @override
  String get displayNameRequired => '请输入显示名称';

  @override
  String get loginFailed => '登录失败。请检查登录信息。';

  @override
  String get registerFailed => '注册失败。请重试。';

  @override
  String comingSoon(String feature) {
    return '$feature 即将推出';
  }

  @override
  String get folders => '文件夹';

  @override
  String get newItem => '新建';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get uploadFile => '上传文件';

  @override
  String get rename => '重命名';

  @override
  String get delete => '删除';

  @override
  String get share => '分享';

  @override
  String get restore => '恢复';

  @override
  String get emptyTrash => '清空回收站';

  @override
  String get trash => '回收站';

  @override
  String get search => '搜索';

  @override
  String get clearSearch => '清除搜索';

  @override
  String get refresh => '刷新';

  @override
  String get gridView => '网格视图';

  @override
  String get listView => '列表视图';

  @override
  String get noFiles => '没有文件';

  @override
  String get noFilesBody => '上传文件或新建文件夹即可开始。';

  @override
  String get createFolder => '创建文件夹';

  @override
  String get folderName => '文件夹名称';

  @override
  String get enterFolderName => '输入文件夹名称';

  @override
  String get fileDeleted => '文件已删除';

  @override
  String get fileRestored => '文件已恢复';

  @override
  String get shareLink => '分享链接';

  @override
  String get copyLink => '复制链接';

  @override
  String get linkCopied => '链接已复制';

  @override
  String get permission => '权限';

  @override
  String get readOnly => '只读';

  @override
  String get readWrite => '读写';

  @override
  String get allowDelete => '允许删除';

  @override
  String get allowDeleteHelp => '已删除的项目将移至所有者的回收站。';

  @override
  String get expiresAt => '到期时间';

  @override
  String get never => '永不过期';

  @override
  String get uploadProgress => '正在上传…';

  @override
  String get downloadProgress => '正在下载…';

  @override
  String get uploadComplete => '上传完成';

  @override
  String get confirmDelete => '确认删除';

  @override
  String get confirmEmptyTrash => '要永久删除回收站中的所有项目吗？';

  @override
  String get cancel => '取消';

  @override
  String get ok => '确定';

  @override
  String get retry => '重试';

  @override
  String get loadMore => '加载更多';

  @override
  String get noPhotos => '暂无照片';

  @override
  String get albums => '相册';

  @override
  String get noAlbums => '暂无相册';

  @override
  String get newAlbum => '新建相册';

  @override
  String get albumName => '相册名称';

  @override
  String get syncStatus => '同步状态';

  @override
  String get syncDevices => '设备';

  @override
  String get syncNoDevices => '没有已注册的设备';

  @override
  String get syncNeverSynced => '从未同步';

  @override
  String get syncChooseFolder => '选择同步文件夹';

  @override
  String get syncFolderNotConfigured => '选择本地文件夹以开始同步此设备。';

  @override
  String get syncPulling => '正在同步…';

  @override
  String get syncDeviceUpToDate => '此设备已是最新状态。';

  @override
  String get syncItemsSkipped => '部分项目无法同步';

  @override
  String get syncSkippedItems => '已跳过的项目';

  @override
  String get syncFolderNotEmptyTitle => '文件夹不为空';

  @override
  String get syncFolderNotEmptyMessage =>
      '此文件夹中已有文件。同步不会覆盖并非由它创建的文件。存在冲突的文件将保持原样，并列为已跳过的项目。';

  @override
  String get syncUnsupportedPlatform => '同步功能可在 Windows 和 macOS 版应用中使用';

  @override
  String get versionHistory => '版本历史';

  @override
  String get noVersions => '暂无版本';

  @override
  String get restoreVersion => '恢复';

  @override
  String versionLabel(int number) {
    return '版本 $number';
  }

  @override
  String get confirmRestoreVersion => '要恢复此版本吗？';

  @override
  String get versionRestored => '版本已恢复';

  @override
  String get latestVersion => '最新';

  @override
  String get close => '关闭';

  @override
  String get errorNoConnection => '无法连接到服务器。请检查网络连接并重试。';

  @override
  String get errorServiceUnavailable => '此功能暂时不可用。请稍后重试。';

  @override
  String get errorRequestFailed => '无法完成请求。';

  @override
  String get authInvalidCredentials => '邮箱或密码无效。';

  @override
  String get authEmailAlreadyRegistered => '该邮箱已存在账户。';

  @override
  String get authEntraAccountExists => '该邮箱已使用其他方式注册账户，请使用密码或该登录方式。';

  @override
  String get authEntraVerificationFailed => '无法验证您的 ZCLOUD 账户，请重试或联系支持。';

  @override
  String get authEntraUnavailable => 'ZCLOUD 登录目前不可用。';

  @override
  String get authTooManyAttempts => '尝试次数过多，请稍后重试。';

  @override
  String get syncConnecting => '正在连接…';

  @override
  String get syncDownloading => '正在下载';

  @override
  String get syncScanning => '正在扫描文件夹';

  @override
  String get syncHashing => '正在比较文件内容';

  @override
  String get syncUploading => '正在上传';

  @override
  String get syncDeleting => '正在应用删除操作';

  @override
  String get syncDiscovering => '正在查找项目 — 总数尚不确定';

  @override
  String syncProgressCounts(int completed, int total, int remaining) {
    return '已完成 $completed / $total 项 · 剩余 $remaining 项';
  }

  @override
  String syncProgressFailures(int count) {
    return '$count 项失败';
  }

  @override
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  ) {
    return '$transferred / $total · 剩余 $remaining';
  }

  @override
  String syncKnownProgressCounts(int completed, int total, int remaining) {
    return '已知项目：已完成 $completed / $total 项 · 剩余 $remaining 项';
  }

  @override
  String get updateRetry => '重试更新';

  @override
  String get updateRestarting => '正在完成同步以准备重启…';

  @override
  String get updateRestart => '重启并更新';

  @override
  String updateDownloading(int percent) {
    return '正在下载更新：$percent%';
  }

  @override
  String updateReady(String version) {
    return '更新 $version 已就绪，将在下次启动时安装。';
  }

  @override
  String get updateFailed => '自动更新失败。你可以继续使用 zDrive 并重试。';

  @override
  String get shareNotFoundTitle => '链接未找到';

  @override
  String get shareNotFoundMessage => '此共享链接无效、已过期或已被删除。';

  @override
  String get sharePasswordProtectedTitle => '需要密码';

  @override
  String get sharePasswordProtectedMessage => '此共享链接受密码保护，目前尚不支持。';

  @override
  String get openZDrive => '打开 zDrive';

  @override
  String get download => '下载';

  @override
  String shareAvailableUntil(Object date) {
    return '有效期至 $date';
  }

  @override
  String get shareWhatIsZDrive => '什么是 zDrive?';

  @override
  String get shareFooterTagline => '由 zDrive 提供安全保障';

  @override
  String get shareReplaceFile => '替换文件';

  @override
  String get shareDeleteConfirmMessage => '此项目将移动到所有者的回收站。';

  @override
  String get shareOverwriteTitle => '替换现有文件？';

  @override
  String shareOverwriteMessage(Object name) {
    return '名为“$name”的文件已存在。上传将以新版本替换它。';
  }

  @override
  String get shareReplaceConfirm => '替换';

  @override
  String get shareErrorNotAllowed => '此链接不允许该操作。';

  @override
  String get shareErrorNameExists => '已存在同名的文件或文件夹。';

  @override
  String get shareErrorQuotaExceeded => '所有者的存储空间已满。';

  @override
  String get shareErrorTooManyUploads => '仍有太多上传正在处理。请稍后重试。';

  @override
  String get tagline => '您的文件，随时随地。';

  @override
  String get authBenefitSync => '跨所有设备同步';

  @override
  String get authBenefitShare => '安全共享文件和文件夹';

  @override
  String get authBenefitSecure => '始终加密存储';

  @override
  String get offlineCloudOnly => '仅云端';

  @override
  String get offlineDownloading => '正在下载';

  @override
  String get offlineAvailable => '此设备上可用';

  @override
  String get offlineAlwaysKeep => '始终保留在此设备上';

  @override
  String get keepOnDevice => '始终保留在此设备上';

  @override
  String get freeUpSpace => '释放空间';

  @override
  String freeUpSkippedUnsynced(int count) {
    return '$count 项已保留在此设备上：有未同步的更改';
  }

  @override
  String get cloudMigrationTitle => '要释放此设备上的空间吗?';

  @override
  String cloudMigrationBody(int count, String size) {
    return '同步文件夹中的文件现在保存在云端，只有在需要时才会下载。可从此设备移除的文件: $count 个，最多 $size。';
  }

  @override
  String get cloudMigrationReassure =>
      '您的文件仍可在云端和网页上访问，随时可以重新下载。含有尚未同步更改的文件始终会被保留。';

  @override
  String get cloudMigrationKeepAll => '将所有内容保留在此设备上';

  @override
  String get cloudMigrationLater => '稍后决定';

  @override
  String get cloudMigrationWorking => '正在释放空间…';

  @override
  String cloudMigrationFreed(int count, String size) {
    return '已释放 $count 个文件，$size';
  }

  @override
  String freeUpKeptPinned(int count) {
    return '$count 项已保留在此设备上: 始终保留';
  }

  @override
  String get cloudMigrationKeeping => '正在将所有内容保留在此设备上…';

  @override
  String get twoFactorTitle => '两步验证';

  @override
  String get twoFactorPrompt => '请输入验证器应用中显示的6位验证码。';

  @override
  String get twoFactorRecoveryPrompt => '请输入其中一个恢复码。';

  @override
  String get twoFactorCodeLabel => '6位验证码';

  @override
  String get twoFactorRecoveryCodeLabel => '恢复码';

  @override
  String get twoFactorVerifyButton => '验证';

  @override
  String get twoFactorUseRecoveryCode => '使用恢复码';

  @override
  String get twoFactorUseAuthenticator => '使用验证器验证码';

  @override
  String get twoFactorBackToSignIn => '返回登录';

  @override
  String get authTwoFactorInvalidCode => '验证码无效,请重试。';

  @override
  String get authTwoFactorChallengeExpired => '此次登录已过期。请返回并重新登录。';

  @override
  String get twoFactorStatusOff => '两步验证已关闭。开启后,登录时需要输入验证器应用中的验证码。';

  @override
  String get twoFactorStatusOn => '两步验证已开启。';

  @override
  String get twoFactorUnavailable => '此账户无法使用两步验证。登录安全由您的 ZCLOUD 账户管理。';

  @override
  String get twoFactorEnable => '开启';

  @override
  String get twoFactorSetupInstructions =>
      '使用验证器应用扫描此二维码,或手动输入设置密钥,然后输入应用显示的6位验证码。';

  @override
  String get twoFactorSetupKey => '设置密钥';

  @override
  String get twoFactorCopy => '复制';

  @override
  String get twoFactorCopied => '已复制';

  @override
  String get twoFactorConfirmButton => '确认并开启';

  @override
  String get twoFactorRecoveryCodesTitle => '请保存您的恢复码';

  @override
  String get twoFactorRecoveryCodesInfo => '如果您无法访问验证器应用,每个恢复码可使用一次。恢复码仅在此时显示。';

  @override
  String get twoFactorCopyCodes => '复制所有恢复码';

  @override
  String get twoFactorDone => '完成';

  @override
  String get twoFactorDisable => '关闭';

  @override
  String get twoFactorDisableInfo => '请输入密码和当前验证码(或恢复码)以关闭两步验证。';

  @override
  String get twoFactorDisableConfirm => '关闭两步验证';

  @override
  String get twoFactorPasswordInvalid => '密码不正确。';
}
