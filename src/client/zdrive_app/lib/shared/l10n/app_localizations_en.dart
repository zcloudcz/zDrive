// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'zDrive';

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
  String get noFiles => 'No files';

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
  String get expiresAt => 'Expires at';

  @override
  String get never => 'Never';

  @override
  String get uploadProgress => 'Uploading...';

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
  String get allSynced => 'Everything is synced';

  @override
  String get syncDescription => 'Your files are up to date across all devices.';
}
