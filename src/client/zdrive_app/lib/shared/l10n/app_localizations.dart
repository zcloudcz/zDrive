import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_cs.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fi.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_sk.dart';
import 'app_localizations_sv.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('cs'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fi'),
    Locale('fr'),
    Locale('ja'),
    Locale('nl'),
    Locale('sk'),
    Locale('sv'),
    Locale('zh'),
  ];

  /// No description provided for @exportDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Export diagnostic log'**
  String get exportDiagnostics;

  /// No description provided for @diagnosticsPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing diagnostic log…'**
  String get diagnosticsPreparing;

  /// No description provided for @diagnosticsSaved.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic log saved.'**
  String get diagnosticsSaved;

  /// No description provided for @diagnosticsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not export the log. Try again.'**
  String get diagnosticsFailed;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutApp;

  /// No description provided for @exitApp.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exitApp;

  /// No description provided for @exitFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not exit the app. Please try again.'**
  String get exitFailed;

  /// No description provided for @appVersionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the app version.'**
  String get appVersionFailed;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String appVersion(String version);

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'zDrive'**
  String get appTitle;

  /// No description provided for @downloadForWindows.
  ///
  /// In en, this message translates to:
  /// **'Download for Windows'**
  String get downloadForWindows;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginButton;

  /// No description provided for @registerButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerButton;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get invalidEmail;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordTooShort;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match'**
  String get passwordsDontMatch;

  /// No description provided for @displayNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Display name is required'**
  String get displayNameRequired;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Check your credentials.'**
  String get loginFailed;

  /// No description provided for @registerFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed. Try again.'**
  String get registerFailed;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'{feature} coming soon'**
  String comingSoon(String feature);

  /// No description provided for @folders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get folders;

  /// No description provided for @newItem.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newItem;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get newFolder;

  /// No description provided for @uploadFile.
  ///
  /// In en, this message translates to:
  /// **'Upload file'**
  String get uploadFile;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @emptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty trash'**
  String get emptyTrash;

  /// No description provided for @trash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get gridView;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get listView;

  /// No description provided for @noFiles.
  ///
  /// In en, this message translates to:
  /// **'No files'**
  String get noFiles;

  /// No description provided for @noFilesBody.
  ///
  /// In en, this message translates to:
  /// **'Upload a file or create a folder to get started.'**
  String get noFilesBody;

  /// No description provided for @createFolder.
  ///
  /// In en, this message translates to:
  /// **'Create folder'**
  String get createFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// No description provided for @enterFolderName.
  ///
  /// In en, this message translates to:
  /// **'Enter folder name'**
  String get enterFolderName;

  /// No description provided for @fileDeleted.
  ///
  /// In en, this message translates to:
  /// **'File deleted'**
  String get fileDeleted;

  /// No description provided for @fileRestored.
  ///
  /// In en, this message translates to:
  /// **'File restored'**
  String get fileRestored;

  /// No description provided for @shareLink.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get shareLink;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @permission.
  ///
  /// In en, this message translates to:
  /// **'Permission'**
  String get permission;

  /// No description provided for @readOnly.
  ///
  /// In en, this message translates to:
  /// **'Read only'**
  String get readOnly;

  /// No description provided for @readWrite.
  ///
  /// In en, this message translates to:
  /// **'Read & Write'**
  String get readWrite;

  /// No description provided for @allowDelete.
  ///
  /// In en, this message translates to:
  /// **'Allow deleting'**
  String get allowDelete;

  /// No description provided for @allowDeleteHelp.
  ///
  /// In en, this message translates to:
  /// **'Deleted items go to the owner\'s trash.'**
  String get allowDeleteHelp;

  /// No description provided for @expiresAt.
  ///
  /// In en, this message translates to:
  /// **'Expires at'**
  String get expiresAt;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @uploadProgress.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get uploadProgress;

  /// No description provided for @downloadProgress.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get downloadProgress;

  /// No description provided for @uploadComplete.
  ///
  /// In en, this message translates to:
  /// **'Upload complete'**
  String get uploadComplete;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm delete'**
  String get confirmDelete;

  /// No description provided for @confirmEmptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete all items in trash?'**
  String get confirmEmptyTrash;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @noPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos yet'**
  String get noPhotos;

  /// No description provided for @albums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albums;

  /// No description provided for @noAlbums.
  ///
  /// In en, this message translates to:
  /// **'No albums yet'**
  String get noAlbums;

  /// No description provided for @newAlbum.
  ///
  /// In en, this message translates to:
  /// **'New album'**
  String get newAlbum;

  /// No description provided for @albumName.
  ///
  /// In en, this message translates to:
  /// **'Album name'**
  String get albumName;

  /// No description provided for @syncStatus.
  ///
  /// In en, this message translates to:
  /// **'Sync status'**
  String get syncStatus;

  /// No description provided for @syncDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get syncDevices;

  /// No description provided for @syncNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No devices registered'**
  String get syncNoDevices;

  /// No description provided for @syncNeverSynced.
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get syncNeverSynced;

  /// No description provided for @syncChooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose sync folder'**
  String get syncChooseFolder;

  /// No description provided for @syncFolderNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Pick a local folder to start syncing this device.'**
  String get syncFolderNotConfigured;

  /// No description provided for @syncPulling.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncPulling;

  /// No description provided for @syncDeviceUpToDate.
  ///
  /// In en, this message translates to:
  /// **'This device is up to date.'**
  String get syncDeviceUpToDate;

  /// No description provided for @syncItemsSkipped.
  ///
  /// In en, this message translates to:
  /// **'Some items could not be synced'**
  String get syncItemsSkipped;

  /// No description provided for @syncSkippedItems.
  ///
  /// In en, this message translates to:
  /// **'Skipped items'**
  String get syncSkippedItems;

  /// No description provided for @syncFolderNotEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Folder is not empty'**
  String get syncFolderNotEmptyTitle;

  /// No description provided for @syncFolderNotEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'This folder already has files in it. Syncing will not overwrite anything it did not put there itself — files that would collide are left alone and listed as skipped instead.'**
  String get syncFolderNotEmptyMessage;

  /// No description provided for @syncUnsupportedPlatform.
  ///
  /// In en, this message translates to:
  /// **'Sync is available in the Windows and macOS app'**
  String get syncUnsupportedPlatform;

  /// No description provided for @versionHistory.
  ///
  /// In en, this message translates to:
  /// **'Version history'**
  String get versionHistory;

  /// No description provided for @noVersions.
  ///
  /// In en, this message translates to:
  /// **'No versions yet'**
  String get noVersions;

  /// No description provided for @restoreVersion.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreVersion;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {number}'**
  String versionLabel(int number);

  /// No description provided for @confirmRestoreVersion.
  ///
  /// In en, this message translates to:
  /// **'Restore this version?'**
  String get confirmRestoreVersion;

  /// No description provided for @versionRestored.
  ///
  /// In en, this message translates to:
  /// **'Version restored'**
  String get versionRestored;

  /// No description provided for @latestVersion.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get latestVersion;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @errorNoConnection.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check your connection and try again.'**
  String get errorNoConnection;

  /// No description provided for @errorServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This feature is temporarily unavailable. Please try again later.'**
  String get errorServiceUnavailable;

  /// No description provided for @errorRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'The request could not be completed.'**
  String get errorRequestFailed;

  /// No description provided for @syncConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get syncConnecting;

  /// No description provided for @syncDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get syncDownloading;

  /// No description provided for @syncScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning folder'**
  String get syncScanning;

  /// No description provided for @syncHashing.
  ///
  /// In en, this message translates to:
  /// **'Comparing file contents'**
  String get syncHashing;

  /// No description provided for @syncUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading'**
  String get syncUploading;

  /// No description provided for @syncDeleting.
  ///
  /// In en, this message translates to:
  /// **'Applying deletions'**
  String get syncDeleting;

  /// No description provided for @syncDiscovering.
  ///
  /// In en, this message translates to:
  /// **'Discovering items — total is not known yet'**
  String get syncDiscovering;

  /// No description provided for @syncProgressCounts.
  ///
  /// In en, this message translates to:
  /// **'{completed} / {total} items completed · {remaining} remaining'**
  String syncProgressCounts(int completed, int total, int remaining);

  /// No description provided for @syncProgressFailures.
  ///
  /// In en, this message translates to:
  /// **'{count} items failed'**
  String syncProgressFailures(int count);

  /// No description provided for @syncTransferredBytes.
  ///
  /// In en, this message translates to:
  /// **'{transferred} / {total} · {remaining} remaining'**
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  );

  /// No description provided for @syncKnownProgressCounts.
  ///
  /// In en, this message translates to:
  /// **'Known items: {completed} / {total} completed · {remaining} remaining'**
  String syncKnownProgressCounts(int completed, int total, int remaining);

  /// No description provided for @updateRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry update'**
  String get updateRetry;

  /// No description provided for @updateRestarting.
  ///
  /// In en, this message translates to:
  /// **'Finishing synchronization before restarting…'**
  String get updateRestarting;

  /// No description provided for @updateRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart and update'**
  String get updateRestart;

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading update: {percent}%'**
  String updateDownloading(int percent);

  /// No description provided for @updateReady.
  ///
  /// In en, this message translates to:
  /// **'Update {version} is ready. It will install on the next start.'**
  String updateReady(String version);

  /// No description provided for @updateFailed.
  ///
  /// In en, this message translates to:
  /// **'Automatic update failed. You can keep using zDrive and try again.'**
  String get updateFailed;

  /// No description provided for @shareNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Link not found'**
  String get shareNotFoundTitle;

  /// No description provided for @shareNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'This share link is invalid, expired, or was removed.'**
  String get shareNotFoundMessage;

  /// No description provided for @sharePasswordProtectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Password required'**
  String get sharePasswordProtectedTitle;

  /// No description provided for @sharePasswordProtectedMessage.
  ///
  /// In en, this message translates to:
  /// **'This share link is password-protected, which is not supported yet.'**
  String get sharePasswordProtectedMessage;

  /// No description provided for @openZDrive.
  ///
  /// In en, this message translates to:
  /// **'Open zDrive'**
  String get openZDrive;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @shareAvailableUntil.
  ///
  /// In en, this message translates to:
  /// **'Available until {date}'**
  String shareAvailableUntil(Object date);

  /// No description provided for @shareWhatIsZDrive.
  ///
  /// In en, this message translates to:
  /// **'What is zDrive?'**
  String get shareWhatIsZDrive;

  /// No description provided for @shareFooterTagline.
  ///
  /// In en, this message translates to:
  /// **'Secured by zDrive'**
  String get shareFooterTagline;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'cs',
    'de',
    'en',
    'es',
    'fi',
    'fr',
    'ja',
    'nl',
    'sk',
    'sv',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'cs':
      return AppLocalizationsCs();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fi':
      return AppLocalizationsFi();
    case 'fr':
      return AppLocalizationsFr();
    case 'ja':
      return AppLocalizationsJa();
    case 'nl':
      return AppLocalizationsNl();
    case 'sk':
      return AppLocalizationsSk();
    case 'sv':
      return AppLocalizationsSv();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
