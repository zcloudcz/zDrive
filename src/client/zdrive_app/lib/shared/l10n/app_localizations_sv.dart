// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Swedish (`sv`).
class AppLocalizationsSv extends AppLocalizations {
  AppLocalizationsSv([String locale = 'sv']) : super(locale);

  @override
  String get aboutApp => 'Om appen';

  @override
  String get exitApp => 'Avsluta';

  @override
  String get exitFailed => 'Det gick inte att avsluta appen. Försök igen.';

  @override
  String get appVersionFailed => 'Det gick inte att läsa in appversionen.';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get appTitle => 'zDrive';

  @override
  String get downloadForWindows => 'Ladda ned för Windows';

  @override
  String get login => 'Inloggning';

  @override
  String get register => 'Registrering';

  @override
  String get email => 'E-post';

  @override
  String get password => 'Lösenord';

  @override
  String get confirmPassword => 'Bekräfta lösenord';

  @override
  String get displayName => 'Visningsnamn';

  @override
  String get files => 'Filer';

  @override
  String get photos => 'Foton';

  @override
  String get settings => 'Inställningar';

  @override
  String get logout => 'Logga ut';

  @override
  String get createAccount => 'Skapa konto';

  @override
  String get loginButton => 'Logga in';

  @override
  String get registerButton => 'Skapa konto';

  @override
  String get emailRequired => 'E-postadress krävs';

  @override
  String get invalidEmail => 'Ange en giltig e-postadress';

  @override
  String get passwordTooShort => 'Lösenordet måste innehålla minst 8 tecken';

  @override
  String get passwordsDontMatch => 'Lösenorden stämmer inte överens';

  @override
  String get displayNameRequired => 'Visningsnamn krävs';

  @override
  String get loginFailed =>
      'Inloggningen misslyckades. Kontrollera dina inloggningsuppgifter.';

  @override
  String get registerFailed => 'Registreringen misslyckades. Försök igen.';

  @override
  String comingSoon(String feature) {
    return '$feature kommer snart';
  }

  @override
  String get folders => 'Mappar';

  @override
  String get newFolder => 'Ny mapp';

  @override
  String get uploadFile => 'Ladda upp fil';

  @override
  String get rename => 'Byt namn';

  @override
  String get delete => 'Ta bort';

  @override
  String get share => 'Dela';

  @override
  String get restore => 'Återställ';

  @override
  String get emptyTrash => 'Töm papperskorgen';

  @override
  String get trash => 'Papperskorg';

  @override
  String get search => 'Sök';

  @override
  String get clearSearch => 'Rensa sökning';

  @override
  String get refresh => 'Uppdatera';

  @override
  String get noFiles => 'Inga filer';

  @override
  String get createFolder => 'Skapa mapp';

  @override
  String get folderName => 'Mappnamn';

  @override
  String get enterFolderName => 'Ange mappnamn';

  @override
  String get fileDeleted => 'Filen har tagits bort';

  @override
  String get fileRestored => 'Filen har återställts';

  @override
  String get shareLink => 'Delningslänk';

  @override
  String get copyLink => 'Kopiera länk';

  @override
  String get linkCopied => 'Länken har kopierats';

  @override
  String get permission => 'Behörighet';

  @override
  String get readOnly => 'Endast läsning';

  @override
  String get readWrite => 'Läsning och skrivning';

  @override
  String get expiresAt => 'Gäller till';

  @override
  String get never => 'Aldrig';

  @override
  String get uploadProgress => 'Laddar upp…';

  @override
  String get downloadProgress => 'Laddar ned…';

  @override
  String get uploadComplete => 'Uppladdningen är klar';

  @override
  String get confirmDelete => 'Bekräfta borttagning';

  @override
  String get confirmEmptyTrash =>
      'Ta bort alla objekt i papperskorgen permanent?';

  @override
  String get cancel => 'Avbryt';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Försök igen';

  @override
  String get loadMore => 'Läs in fler';

  @override
  String get noPhotos => 'Inga foton ännu';

  @override
  String get albums => 'Album';

  @override
  String get noAlbums => 'Inga album ännu';

  @override
  String get newAlbum => 'Nytt album';

  @override
  String get albumName => 'Albumnamn';

  @override
  String get syncStatus => 'Synkroniseringsstatus';

  @override
  String get syncDevices => 'Enheter';

  @override
  String get syncNoDevices => 'Inga registrerade enheter';

  @override
  String get syncNeverSynced => 'Aldrig synkroniserad';

  @override
  String get syncChooseFolder => 'Välj synkroniseringsmapp';

  @override
  String get syncFolderNotConfigured =>
      'Välj en lokal mapp för att börja synkronisera den här enheten.';

  @override
  String get syncPulling => 'Synkroniserar…';

  @override
  String get syncDeviceUpToDate => 'Den här enheten är uppdaterad.';

  @override
  String get syncItemsSkipped => 'Vissa objekt kunde inte synkroniseras';

  @override
  String get syncSkippedItems => 'Överhoppade objekt';

  @override
  String get syncFolderNotEmptyTitle => 'Mappen är inte tom';

  @override
  String get syncFolderNotEmptyMessage =>
      'Den här mappen innehåller redan filer. Synkroniseringen skriver inte över något som den inte själv har skapat. Filer som skulle orsaka konflikter lämnas orörda och visas som överhoppade.';

  @override
  String get syncUnsupportedPlatform =>
      'Synkronisering är tillgänglig i appen för Windows och macOS';

  @override
  String get versionHistory => 'Versionshistorik';

  @override
  String get noVersions => 'Inga versioner ännu';

  @override
  String get restoreVersion => 'Återställ';

  @override
  String versionLabel(int number) {
    return 'Version $number';
  }

  @override
  String get confirmRestoreVersion => 'Återställ den här versionen?';

  @override
  String get versionRestored => 'Versionen har återställts';

  @override
  String get latestVersion => 'Senaste';

  @override
  String get close => 'Stäng';

  @override
  String get errorNoConnection =>
      'Kunde inte ansluta till servern. Kontrollera anslutningen och försök igen.';

  @override
  String get errorServiceUnavailable =>
      'Den här funktionen är tillfälligt otillgänglig. Försök igen senare.';

  @override
  String get errorRequestFailed => 'Begäran kunde inte slutföras.';

  @override
  String get syncConnecting => 'Ansluter…';

  @override
  String get syncDownloading => 'Laddar ned';

  @override
  String get syncScanning => 'Skannar mapp';

  @override
  String get syncHashing => 'Jämför filinnehåll';

  @override
  String get syncUploading => 'Laddar upp';

  @override
  String get syncDeleting => 'Verkställer borttagningar';

  @override
  String get syncDiscovering =>
      'Söker efter objekt — det totala antalet är ännu okänt';

  @override
  String syncProgressCounts(int completed, int total, int remaining) {
    return '$completed / $total objekt klara · $remaining återstår';
  }

  @override
  String syncProgressFailures(int count) {
    return '$count objekt misslyckades';
  }

  @override
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  ) {
    return '$transferred / $total · $remaining återstår';
  }

  @override
  String syncKnownProgressCounts(int completed, int total, int remaining) {
    return 'Kända objekt: $completed / $total klara · $remaining återstår';
  }

  @override
  String get updateRetry => 'Försök uppdatera igen';

  @override
  String get updateRestarting => 'Slutför synkroniseringen före omstart…';

  @override
  String get updateRestart => 'Starta om och uppdatera';

  @override
  String updateDownloading(int percent) {
    return 'Laddar ned uppdatering: $percent%';
  }

  @override
  String updateReady(String version) {
    return 'Uppdatering $version är klar. Den installeras vid nästa start.';
  }

  @override
  String get updateFailed =>
      'Den automatiska uppdateringen misslyckades. Du kan fortsätta använda zDrive och försöka igen.';
}
