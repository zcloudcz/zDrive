// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get exportDiagnostics => 'Export diagnostic log';

  @override
  String get diagnosticsPreparing => 'Preparing diagnostic log…';

  @override
  String get diagnosticsSaved => 'Diagnostic log saved.';

  @override
  String get diagnosticsFailed => 'Could not export the log. Try again.';

  @override
  String get aboutApp => 'About';

  @override
  String get exitApp => 'Exit';

  @override
  String get exitFailed => 'Could not exit the app. Please try again.';

  @override
  String get appVersionFailed => 'Could not load the app version.';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get appTitle => 'zDrive';

  @override
  String get downloadForWindows => 'Download for Windows';

  @override
  String get login => 'Login';

  @override
  String get register => 'Register';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get displayName => 'Display name';

  @override
  String get files => 'Files';

  @override
  String get photos => 'Photos';

  @override
  String get settings => 'Settings';

  @override
  String get logout => 'Logout';

  @override
  String get createAccount => 'Create account';

  @override
  String get loginButton => 'Sign in';

  @override
  String get registerButton => 'Create account';

  @override
  String get emailRequired => 'Email is required';

  @override
  String get invalidEmail => 'Enter a valid email address';

  @override
  String get passwordTooShort => 'Password must be at least 8 characters';

  @override
  String get passwordsDontMatch => 'Passwords don\'t match';

  @override
  String get displayNameRequired => 'Display name is required';

  @override
  String get loginFailed => 'Login failed. Check your credentials.';

  @override
  String get registerFailed => 'Registration failed. Try again.';

  @override
  String comingSoon(String feature) {
    return '$feature coming soon';
  }

  @override
  String get folders => 'Folders';

  @override
  String get newItem => 'New';

  @override
  String get newFolder => 'New folder';

  @override
  String get uploadFile => 'Upload file';

  @override
  String get rename => 'Rename';

  @override
  String get delete => 'Delete';

  @override
  String get share => 'Share';

  @override
  String get restore => 'Restore';

  @override
  String get emptyTrash => 'Empty trash';

  @override
  String get trash => 'Trash';

  @override
  String get search => 'Search';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get refresh => 'Refresh';

  @override
  String get gridView => 'Grid view';

  @override
  String get listView => 'List view';

  @override
  String get noFiles => 'No files';

  @override
  String get noFilesBody => 'Upload a file or create a folder to get started.';

  @override
  String get createFolder => 'Create folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get enterFolderName => 'Enter folder name';

  @override
  String get fileDeleted => 'File deleted';

  @override
  String get fileRestored => 'File restored';

  @override
  String get shareLink => 'Share link';

  @override
  String get copyLink => 'Copy link';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get permission => 'Permission';

  @override
  String get readOnly => 'Read only';

  @override
  String get readWrite => 'Read & Write';

  @override
  String get allowDelete => 'Allow deleting';

  @override
  String get allowDeleteHelp => 'Deleted items go to the owner\'s trash.';

  @override
  String get expiresAt => 'Expires at';

  @override
  String get never => 'Never';

  @override
  String get uploadProgress => 'Uploading...';

  @override
  String get downloadProgress => 'Downloading...';

  @override
  String get uploadComplete => 'Upload complete';

  @override
  String get confirmDelete => 'Confirm delete';

  @override
  String get confirmEmptyTrash => 'Permanently delete all items in trash?';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Retry';

  @override
  String get loadMore => 'Load more';

  @override
  String get noPhotos => 'No photos yet';

  @override
  String get albums => 'Albums';

  @override
  String get noAlbums => 'No albums yet';

  @override
  String get newAlbum => 'New album';

  @override
  String get albumName => 'Album name';

  @override
  String get syncStatus => 'Sync status';

  @override
  String get syncDevices => 'Devices';

  @override
  String get syncNoDevices => 'No devices registered';

  @override
  String get syncNeverSynced => 'Never synced';

  @override
  String get syncChooseFolder => 'Choose sync folder';

  @override
  String get syncFolderNotConfigured =>
      'Pick a local folder to start syncing this device.';

  @override
  String get syncPulling => 'Syncing…';

  @override
  String get syncDeviceUpToDate => 'This device is up to date.';

  @override
  String get syncItemsSkipped => 'Some items could not be synced';

  @override
  String get syncSkippedItems => 'Skipped items';

  @override
  String get syncFolderNotEmptyTitle => 'Folder is not empty';

  @override
  String get syncFolderNotEmptyMessage =>
      'This folder already has files in it. Syncing will not overwrite anything it did not put there itself — files that would collide are left alone and listed as skipped instead.';

  @override
  String get syncUnsupportedPlatform =>
      'Sync is available in the Windows and macOS app';

  @override
  String get versionHistory => 'Version history';

  @override
  String get noVersions => 'No versions yet';

  @override
  String get restoreVersion => 'Restore';

  @override
  String versionLabel(int number) {
    return 'Version $number';
  }

  @override
  String get confirmRestoreVersion => 'Restore this version?';

  @override
  String get versionRestored => 'Version restored';

  @override
  String get latestVersion => 'Latest';

  @override
  String get close => 'Close';

  @override
  String get errorNoConnection =>
      'Could not reach the server. Check your connection and try again.';

  @override
  String get errorServiceUnavailable =>
      'This feature is temporarily unavailable. Please try again later.';

  @override
  String get errorRequestFailed => 'The request could not be completed.';

  @override
  String get syncConnecting => 'Connecting…';

  @override
  String get syncDownloading => 'Downloading';

  @override
  String get syncScanning => 'Scanning folder';

  @override
  String get syncHashing => 'Comparing file contents';

  @override
  String get syncUploading => 'Uploading';

  @override
  String get syncDeleting => 'Applying deletions';

  @override
  String get syncDiscovering => 'Discovering items — total is not known yet';

  @override
  String syncProgressCounts(int completed, int total, int remaining) {
    return '$completed / $total items completed · $remaining remaining';
  }

  @override
  String syncProgressFailures(int count) {
    return '$count items failed';
  }

  @override
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  ) {
    return '$transferred / $total · $remaining remaining';
  }

  @override
  String syncKnownProgressCounts(int completed, int total, int remaining) {
    return 'Known items: $completed / $total completed · $remaining remaining';
  }

  @override
  String get updateRetry => 'Retry update';

  @override
  String get updateRestarting => 'Finishing synchronization before restarting…';

  @override
  String get updateRestart => 'Restart and update';

  @override
  String updateDownloading(int percent) {
    return 'Downloading update: $percent%';
  }

  @override
  String updateReady(String version) {
    return 'Update $version is ready. It will install on the next start.';
  }

  @override
  String get updateFailed =>
      'Automatic update failed. You can keep using zDrive and try again.';

  @override
  String get shareNotFoundTitle => 'Link not found';

  @override
  String get shareNotFoundMessage =>
      'This share link is invalid, expired, or was removed.';

  @override
  String get sharePasswordProtectedTitle => 'Password required';

  @override
  String get sharePasswordProtectedMessage =>
      'This share link is password-protected, which is not supported yet.';

  @override
  String get openZDrive => 'Open zDrive';

  @override
  String get download => 'Download';

  @override
  String shareAvailableUntil(Object date) {
    return 'Available until $date';
  }

  @override
  String get shareWhatIsZDrive => 'What is zDrive?';

  @override
  String get shareFooterTagline => 'Secured by zDrive';

  @override
  String get shareReplaceFile => 'Replace file';

  @override
  String get shareDeleteConfirmMessage =>
      'This item will be moved to the owner\'s trash.';

  @override
  String get shareOverwriteTitle => 'Replace existing file?';

  @override
  String shareOverwriteMessage(Object name) {
    return 'A file named \"$name\" already exists. Uploading will replace it with a new version.';
  }

  @override
  String get shareReplaceConfirm => 'Replace';

  @override
  String get shareErrorNotAllowed => 'This link does not allow that.';

  @override
  String get shareErrorNameExists =>
      'A file or folder with this name already exists.';

  @override
  String get shareErrorQuotaExceeded => 'The owner\'s storage is full.';

  @override
  String get shareErrorTooManyUploads =>
      'Too many uploads are still processing. Try again shortly.';

  @override
  String get tagline => 'Your files, everywhere.';

  @override
  String get authBenefitSync => 'Sync across every device';

  @override
  String get authBenefitShare => 'Share files and folders securely';

  @override
  String get authBenefitSecure => 'Encrypted storage, always';

  @override
  String get offlineCloudOnly => 'Cloud only';

  @override
  String get offlineDownloading => 'Downloading';

  @override
  String get offlineAvailable => 'Available on this device';

  @override
  String get offlineAlwaysKeep => 'Always kept on this device';

  @override
  String get keepOnDevice => 'Always keep on this device';

  @override
  String get freeUpSpace => 'Free up space';

  @override
  String freeUpSkippedUnsynced(int count) {
    return '$count kept on this device: unsynced changes';
  }
}
