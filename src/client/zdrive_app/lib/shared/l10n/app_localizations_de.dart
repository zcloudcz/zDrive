// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get aboutApp => 'Über die App';

  @override
  String get exitApp => 'Beenden';

  @override
  String get exitFailed =>
      'Die App konnte nicht beendet werden. Versuche es erneut.';

  @override
  String get appVersionFailed => 'Die App-Version konnte nicht geladen werden.';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get appTitle => 'zDrive';

  @override
  String get downloadForWindows => 'Für Windows herunterladen';

  @override
  String get login => 'Anmeldung';

  @override
  String get register => 'Registrierung';

  @override
  String get email => 'E-Mail';

  @override
  String get password => 'Passwort';

  @override
  String get confirmPassword => 'Passwort bestätigen';

  @override
  String get displayName => 'Anzeigename';

  @override
  String get files => 'Dateien';

  @override
  String get photos => 'Fotos';

  @override
  String get settings => 'Einstellungen';

  @override
  String get logout => 'Abmelden';

  @override
  String get createAccount => 'Konto erstellen';

  @override
  String get loginButton => 'Anmelden';

  @override
  String get registerButton => 'Konto erstellen';

  @override
  String get emailRequired => 'E-Mail ist erforderlich';

  @override
  String get invalidEmail => 'Gib eine gültige E-Mail-Adresse ein';

  @override
  String get passwordTooShort =>
      'Das Passwort muss mindestens 8 Zeichen lang sein';

  @override
  String get passwordsDontMatch => 'Die Passwörter stimmen nicht überein';

  @override
  String get displayNameRequired => 'Der Anzeigename ist erforderlich';

  @override
  String get loginFailed =>
      'Anmeldung fehlgeschlagen. Prüfe deine Zugangsdaten.';

  @override
  String get registerFailed =>
      'Registrierung fehlgeschlagen. Versuche es erneut.';

  @override
  String comingSoon(String feature) {
    return '$feature ist bald verfügbar';
  }

  @override
  String get folders => 'Ordner';

  @override
  String get newFolder => 'Neuer Ordner';

  @override
  String get uploadFile => 'Datei hochladen';

  @override
  String get rename => 'Umbenennen';

  @override
  String get delete => 'Löschen';

  @override
  String get share => 'Teilen';

  @override
  String get restore => 'Wiederherstellen';

  @override
  String get emptyTrash => 'Papierkorb leeren';

  @override
  String get trash => 'Papierkorb';

  @override
  String get search => 'Suchen';

  @override
  String get clearSearch => 'Suche löschen';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get noFiles => 'Keine Dateien';

  @override
  String get createFolder => 'Ordner erstellen';

  @override
  String get folderName => 'Ordnername';

  @override
  String get enterFolderName => 'Ordnernamen eingeben';

  @override
  String get fileDeleted => 'Datei gelöscht';

  @override
  String get fileRestored => 'Datei wiederhergestellt';

  @override
  String get shareLink => 'Freigabelink';

  @override
  String get copyLink => 'Link kopieren';

  @override
  String get linkCopied => 'Link kopiert';

  @override
  String get permission => 'Berechtigung';

  @override
  String get readOnly => 'Nur Lesen';

  @override
  String get readWrite => 'Lesen und Schreiben';

  @override
  String get expiresAt => 'Gültig bis';

  @override
  String get never => 'Nie';

  @override
  String get uploadProgress => 'Wird hochgeladen…';

  @override
  String get downloadProgress => 'Wird heruntergeladen…';

  @override
  String get uploadComplete => 'Hochladen abgeschlossen';

  @override
  String get confirmDelete => 'Löschen bestätigen';

  @override
  String get confirmEmptyTrash =>
      'Alle Elemente im Papierkorb endgültig löschen?';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get loadMore => 'Mehr laden';

  @override
  String get noPhotos => 'Noch keine Fotos';

  @override
  String get albums => 'Alben';

  @override
  String get noAlbums => 'Noch keine Alben';

  @override
  String get newAlbum => 'Neues Album';

  @override
  String get albumName => 'Albumname';

  @override
  String get syncStatus => 'Synchronisierungsstatus';

  @override
  String get syncDevices => 'Geräte';

  @override
  String get syncNoDevices => 'Keine registrierten Geräte';

  @override
  String get syncNeverSynced => 'Noch nie synchronisiert';

  @override
  String get syncChooseFolder => 'Synchronisierungsordner auswählen';

  @override
  String get syncFolderNotConfigured =>
      'Wähle einen lokalen Ordner, um dieses Gerät zu synchronisieren.';

  @override
  String get syncPulling => 'Wird synchronisiert…';

  @override
  String get syncDeviceUpToDate => 'Dieses Gerät ist auf dem neuesten Stand.';

  @override
  String get syncItemsSkipped =>
      'Einige Elemente konnten nicht synchronisiert werden';

  @override
  String get syncSkippedItems => 'Übersprungene Elemente';

  @override
  String get syncFolderNotEmptyTitle => 'Der Ordner ist nicht leer';

  @override
  String get syncFolderNotEmptyMessage =>
      'Dieser Ordner enthält bereits Dateien. Die Synchronisierung überschreibt nur Dateien, die sie selbst erstellt hat. Dateien mit Konflikten bleiben unverändert und werden als übersprungen aufgeführt.';

  @override
  String get syncUnsupportedPlatform =>
      'Die Synchronisierung ist in der App für Windows und macOS verfügbar';

  @override
  String get versionHistory => 'Versionsverlauf';

  @override
  String get noVersions => 'Noch keine Versionen';

  @override
  String get restoreVersion => 'Wiederherstellen';

  @override
  String versionLabel(int number) {
    return 'Version $number';
  }

  @override
  String get confirmRestoreVersion => 'Diese Version wiederherstellen?';

  @override
  String get versionRestored => 'Version wiederhergestellt';

  @override
  String get latestVersion => 'Neueste';

  @override
  String get close => 'Schließen';

  @override
  String get errorNoConnection =>
      'Der Server ist nicht erreichbar. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get errorServiceUnavailable =>
      'Diese Funktion ist vorübergehend nicht verfügbar. Versuche es später erneut.';

  @override
  String get errorRequestFailed =>
      'Die Anfrage konnte nicht abgeschlossen werden.';

  @override
  String get syncConnecting => 'Verbindung wird hergestellt…';

  @override
  String get syncDownloading => 'Wird heruntergeladen';

  @override
  String get syncScanning => 'Ordner wird durchsucht';

  @override
  String get syncHashing => 'Dateiinhalte werden verglichen';

  @override
  String get syncUploading => 'Wird hochgeladen';

  @override
  String get syncDeleting => 'Löschungen werden angewendet';

  @override
  String get syncDiscovering =>
      'Elemente werden gesucht — die Gesamtzahl ist noch unbekannt';

  @override
  String syncProgressCounts(int completed, int total, int remaining) {
    return '$completed / $total Elemente abgeschlossen · $remaining verbleibend';
  }

  @override
  String syncProgressFailures(int count) {
    return '$count Elemente fehlgeschlagen';
  }

  @override
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  ) {
    return '$transferred / $total · $remaining verbleibend';
  }

  @override
  String syncKnownProgressCounts(int completed, int total, int remaining) {
    return 'Bekannte Elemente: $completed / $total abgeschlossen · $remaining verbleibend';
  }

  @override
  String get updateRetry => 'Aktualisierung erneut versuchen';

  @override
  String get updateRestarting =>
      'Synchronisierung wird vor dem Neustart abgeschlossen…';

  @override
  String get updateRestart => 'Neu starten und aktualisieren';

  @override
  String updateDownloading(int percent) {
    return 'Aktualisierung wird heruntergeladen: $percent%';
  }

  @override
  String updateReady(String version) {
    return 'Aktualisierung $version ist bereit. Sie wird beim nächsten Start installiert.';
  }

  @override
  String get updateFailed =>
      'Die automatische Aktualisierung ist fehlgeschlagen. Du kannst zDrive weiter nutzen und es erneut versuchen.';
}
