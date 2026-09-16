// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

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
  String get noFiles => '没有文件';

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
}
