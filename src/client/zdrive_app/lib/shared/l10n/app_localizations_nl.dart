// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get exportDiagnostics => 'Diagnoselog exporteren';

  @override
  String get diagnosticsPreparing => 'Diagnoselog voorbereiden…';

  @override
  String get diagnosticsSaved => 'Diagnoselog opgeslagen.';

  @override
  String get diagnosticsFailed =>
      'Kan het logbestand niet exporteren. Probeer het opnieuw.';

  @override
  String get aboutApp => 'Over de app';

  @override
  String get exitApp => 'Afsluiten';

  @override
  String get exitFailed =>
      'De app kon niet worden afgesloten. Probeer het opnieuw.';

  @override
  String get appVersionFailed => 'De appversie kon niet worden geladen.';

  @override
  String appVersion(String version) {
    return 'Versie $version';
  }

  @override
  String get appTitle => 'zDrive';

  @override
  String get downloadForWindows => 'Downloaden voor Windows';

  @override
  String get login => 'Aanmelden';

  @override
  String get register => 'Registreren';

  @override
  String get email => 'E-mailadres';

  @override
  String get password => 'Wachtwoord';

  @override
  String get confirmPassword => 'Wachtwoord bevestigen';

  @override
  String get displayName => 'Weergavenaam';

  @override
  String get files => 'Bestanden';

  @override
  String get photos => 'Foto’s';

  @override
  String get settings => 'Instellingen';

  @override
  String get logout => 'Afmelden';

  @override
  String get createAccount => 'Account maken';

  @override
  String get loginButton => 'Aanmelden';

  @override
  String get entraSignInButton => 'Aanmelden met je ZCLOUD-account';

  @override
  String get entraStateMismatch =>
      'Aanmelden kon niet worden geverifieerd. Probeer het opnieuw.';

  @override
  String get entraSignInDenied => 'Aanmelden geannuleerd.';

  @override
  String get registerButton => 'Account maken';

  @override
  String get emailRequired => 'E-mailadres is verplicht';

  @override
  String get invalidEmail => 'Voer een geldig e-mailadres in';

  @override
  String get passwordTooShort =>
      'Het wachtwoord moet minstens 8 tekens bevatten';

  @override
  String get passwordsDontMatch => 'De wachtwoorden komen niet overeen';

  @override
  String get displayNameRequired => 'Weergavenaam is verplicht';

  @override
  String get loginFailed => 'Aanmelden mislukt. Controleer je inloggegevens.';

  @override
  String get registerFailed => 'Registratie mislukt. Probeer het opnieuw.';

  @override
  String comingSoon(String feature) {
    return '$feature is binnenkort beschikbaar';
  }

  @override
  String get folders => 'Mappen';

  @override
  String get newItem => 'Nieuw';

  @override
  String get newFolder => 'Nieuwe map';

  @override
  String get uploadFile => 'Bestand uploaden';

  @override
  String get rename => 'Naam wijzigen';

  @override
  String get delete => 'Verwijderen';

  @override
  String get share => 'Delen';

  @override
  String get restore => 'Herstellen';

  @override
  String get emptyTrash => 'Prullenbak legen';

  @override
  String get trash => 'Prullenbak';

  @override
  String get search => 'Zoeken';

  @override
  String get clearSearch => 'Zoekopdracht wissen';

  @override
  String get refresh => 'Vernieuwen';

  @override
  String get gridView => 'Rasterweergave';

  @override
  String get listView => 'Lijstweergave';

  @override
  String get noFiles => 'Geen bestanden';

  @override
  String get noFilesBody =>
      'Upload een bestand of maak een map aan om te beginnen.';

  @override
  String get createFolder => 'Map maken';

  @override
  String get folderName => 'Mapnaam';

  @override
  String get enterFolderName => 'Voer een mapnaam in';

  @override
  String get fileDeleted => 'Bestand verwijderd';

  @override
  String get fileRestored => 'Bestand hersteld';

  @override
  String get shareLink => 'Deellink';

  @override
  String get copyLink => 'Link kopiëren';

  @override
  String get linkCopied => 'Link gekopieerd';

  @override
  String get permission => 'Machtiging';

  @override
  String get readOnly => 'Alleen lezen';

  @override
  String get readWrite => 'Lezen en schrijven';

  @override
  String get allowDelete => 'Verwijderen toestaan';

  @override
  String get allowDeleteHelp =>
      'Verwijderde items gaan naar de prullenbak van de eigenaar.';

  @override
  String get expiresAt => 'Verloopt op';

  @override
  String get never => 'Nooit';

  @override
  String get uploadProgress => 'Uploaden…';

  @override
  String get downloadProgress => 'Downloaden…';

  @override
  String get uploadComplete => 'Upload voltooid';

  @override
  String get confirmDelete => 'Verwijderen bevestigen';

  @override
  String get confirmEmptyTrash =>
      'Alle items in de prullenbak permanent verwijderen?';

  @override
  String get cancel => 'Annuleren';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Opnieuw proberen';

  @override
  String get loadMore => 'Meer laden';

  @override
  String get noPhotos => 'Nog geen foto’s';

  @override
  String get albums => 'Albums';

  @override
  String get noAlbums => 'Nog geen albums';

  @override
  String get newAlbum => 'Nieuw album';

  @override
  String get albumName => 'Albumnaam';

  @override
  String get syncStatus => 'Synchronisatiestatus';

  @override
  String get syncDevices => 'Apparaten';

  @override
  String get syncNoDevices => 'Geen geregistreerde apparaten';

  @override
  String get syncNeverSynced => 'Nooit gesynchroniseerd';

  @override
  String get syncChooseFolder => 'Synchronisatiemap kiezen';

  @override
  String get syncFolderNotConfigured =>
      'Kies een lokale map om dit apparaat te synchroniseren.';

  @override
  String get syncPulling => 'Synchroniseren…';

  @override
  String get syncDeviceUpToDate => 'Dit apparaat is bijgewerkt.';

  @override
  String get syncItemsSkipped =>
      'Sommige items konden niet worden gesynchroniseerd';

  @override
  String get syncSkippedItems => 'Overgeslagen items';

  @override
  String get syncFolderNotEmptyTitle => 'De map is niet leeg';

  @override
  String get syncFolderNotEmptyMessage =>
      'Deze map bevat al bestanden. De synchronisatie overschrijft alleen bestanden die ze zelf heeft aangemaakt. Bestanden die conflicten zouden veroorzaken blijven ongewijzigd en worden vermeld als overgeslagen.';

  @override
  String get syncUnsupportedPlatform =>
      'Synchronisatie is beschikbaar in de app voor Windows en macOS';

  @override
  String get versionHistory => 'Versiegeschiedenis';

  @override
  String get noVersions => 'Nog geen versies';

  @override
  String get restoreVersion => 'Herstellen';

  @override
  String versionLabel(int number) {
    return 'Versie $number';
  }

  @override
  String get confirmRestoreVersion => 'Deze versie herstellen?';

  @override
  String get versionRestored => 'Versie hersteld';

  @override
  String get latestVersion => 'Nieuwste';

  @override
  String get close => 'Sluiten';

  @override
  String get errorNoConnection =>
      'De server is niet bereikbaar. Controleer je verbinding en probeer het opnieuw.';

  @override
  String get errorServiceUnavailable =>
      'Deze functie is tijdelijk niet beschikbaar. Probeer het later opnieuw.';

  @override
  String get errorRequestFailed => 'Het verzoek kon niet worden voltooid.';

  @override
  String get authInvalidCredentials => 'Ongeldig e-mailadres of wachtwoord.';

  @override
  String get authEmailAlreadyRegistered =>
      'Er bestaat al een account met dit e-mailadres.';

  @override
  String get authEntraAccountExists =>
      'Er bestaat al een account met dit e-mailadres dat op een andere manier is aangemeld. Gebruik je wachtwoord of die aanmeldmethode.';

  @override
  String get authEntraVerificationFailed =>
      'Je ZCLOUD-account kon niet worden geverifieerd. Probeer het opnieuw of neem contact op met support.';

  @override
  String get authEntraUnavailable =>
      'ZCLOUD-aanmelden is momenteel niet beschikbaar.';

  @override
  String get authTooManyAttempts =>
      'Te veel pogingen. Probeer het later opnieuw.';

  @override
  String get syncConnecting => 'Verbinding maken…';

  @override
  String get syncDownloading => 'Downloaden';

  @override
  String get syncScanning => 'Map scannen';

  @override
  String get syncHashing => 'Bestandsinhoud vergelijken';

  @override
  String get syncUploading => 'Uploaden';

  @override
  String get syncDeleting => 'Verwijderingen toepassen';

  @override
  String get syncDiscovering =>
      'Items zoeken — het totale aantal is nog onbekend';

  @override
  String syncProgressCounts(int completed, int total, int remaining) {
    return '$completed / $total items voltooid · $remaining resterend';
  }

  @override
  String syncProgressFailures(int count) {
    return '$count items mislukt';
  }

  @override
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  ) {
    return '$transferred / $total · $remaining resterend';
  }

  @override
  String syncKnownProgressCounts(int completed, int total, int remaining) {
    return 'Bekende items: $completed / $total voltooid · $remaining resterend';
  }

  @override
  String get updateRetry => 'Update opnieuw proberen';

  @override
  String get updateRestarting => 'Synchronisatie afronden vóór het herstarten…';

  @override
  String get updateRestart => 'Herstarten en bijwerken';

  @override
  String updateDownloading(int percent) {
    return 'Update downloaden: $percent%';
  }

  @override
  String updateReady(String version) {
    return 'Update $version is klaar. Deze wordt bij de volgende start geïnstalleerd.';
  }

  @override
  String get updateFailed =>
      'De automatische update is mislukt. Je kunt zDrive blijven gebruiken en het opnieuw proberen.';

  @override
  String get shareNotFoundTitle => 'Link niet gevonden';

  @override
  String get shareNotFoundMessage =>
      'Deze deellink is ongeldig, verlopen of verwijderd.';

  @override
  String get sharePasswordProtectedTitle => 'Wachtwoord vereist';

  @override
  String get sharePasswordProtectedMessage =>
      'Deze deellink is met een wachtwoord beveiligd, wat nog niet wordt ondersteund.';

  @override
  String get openZDrive => 'zDrive openen';

  @override
  String get download => 'Downloaden';

  @override
  String shareAvailableUntil(Object date) {
    return 'Beschikbaar tot $date';
  }

  @override
  String get shareWhatIsZDrive => 'Wat is zDrive?';

  @override
  String get shareFooterTagline => 'Beveiligd door zDrive';

  @override
  String get shareReplaceFile => 'Bestand vervangen';

  @override
  String get shareDeleteConfirmMessage =>
      'Dit item wordt verplaatst naar de prullenbak van de eigenaar.';

  @override
  String get shareOverwriteTitle => 'Bestaand bestand vervangen?';

  @override
  String shareOverwriteMessage(Object name) {
    return 'Er bestaat al een bestand met de naam \"$name\". Uploaden vervangt het door een nieuwe versie.';
  }

  @override
  String get shareReplaceConfirm => 'Vervangen';

  @override
  String get shareErrorNotAllowed => 'Deze link staat dat niet toe.';

  @override
  String get shareErrorNameExists =>
      'Er bestaat al een bestand of map met deze naam.';

  @override
  String get shareErrorQuotaExceeded => 'De opslag van de eigenaar is vol.';

  @override
  String get shareErrorTooManyUploads =>
      'Er worden nog te veel uploads verwerkt. Probeer het straks opnieuw.';

  @override
  String get tagline => 'Je bestanden, overal.';

  @override
  String get authBenefitSync => 'Synchronisatie op alle apparaten';

  @override
  String get authBenefitShare => 'Bestanden en mappen veilig delen';

  @override
  String get authBenefitSecure => 'Altijd versleutelde opslag';

  @override
  String get offlineCloudOnly => 'Alleen in de cloud';

  @override
  String get offlineDownloading => 'Downloaden';

  @override
  String get offlineAvailable => 'Beschikbaar op dit apparaat';

  @override
  String get offlineAlwaysKeep => 'Altijd op dit apparaat bewaard';

  @override
  String get keepOnDevice => 'Altijd op dit apparaat bewaren';

  @override
  String get freeUpSpace => 'Ruimte vrijmaken';

  @override
  String freeUpSkippedUnsynced(int count) {
    return '$count bewaard op dit apparaat: niet-gesynchroniseerde wijzigingen';
  }

  @override
  String get cloudMigrationTitle => 'Ruimte vrijmaken op dit apparaat?';

  @override
  String cloudMigrationBody(int count, String size) {
    return 'Bestanden in je synchronisatiemap worden nu in de cloud bewaard en pas gedownload wanneer je ze nodig hebt. Bestanden die van dit apparaat kunnen worden verwijderd: $count, tot $size.';
  }

  @override
  String get cloudMigrationReassure =>
      'Je bestanden blijven beschikbaar in de cloud en op het web, en je kunt ze op elk moment opnieuw downloaden. Bestanden met wijzigingen die nog niet zijn gesynchroniseerd blijven altijd bewaard.';

  @override
  String get cloudMigrationKeepAll => 'Alles op dit apparaat bewaren';

  @override
  String get cloudMigrationLater => 'Later beslissen';

  @override
  String get cloudMigrationWorking => 'Ruimte vrijmaken…';

  @override
  String cloudMigrationFreed(int count, String size) {
    return '$count bestanden vrijgemaakt, $size';
  }

  @override
  String freeUpKeptPinned(int count) {
    return '$count bewaard op dit apparaat: altijd bewaren';
  }

  @override
  String get cloudMigrationKeeping => 'Alles op dit apparaat bewaren…';

  @override
  String get twoFactorTitle => 'Verificatie in twee stappen';

  @override
  String get twoFactorPrompt =>
      'Voer de 6-cijferige code uit je authenticator-app in.';

  @override
  String get twoFactorRecoveryPrompt => 'Voer een van je herstelcodes in.';

  @override
  String get twoFactorCodeLabel => '6-cijferige code';

  @override
  String get twoFactorRecoveryCodeLabel => 'Herstelcode';

  @override
  String get twoFactorVerifyButton => 'Verifiëren';

  @override
  String get twoFactorUseRecoveryCode => 'Een herstelcode gebruiken';

  @override
  String get twoFactorUseAuthenticator =>
      'Een code uit de authenticator-app gebruiken';

  @override
  String get twoFactorBackToSignIn => 'Terug naar inloggen';

  @override
  String get authTwoFactorInvalidCode =>
      'Die code is niet geldig. Probeer het opnieuw.';

  @override
  String get authTwoFactorChallengeExpired =>
      'Deze inlogpoging is verlopen. Ga terug en log opnieuw in.';

  @override
  String get twoFactorStatusOff =>
      'Verificatie in twee stappen staat uit. Zet het aan om bij het inloggen een code uit je authenticator-app te vragen.';

  @override
  String get twoFactorStatusOn => 'Verificatie in twee stappen staat aan.';

  @override
  String get twoFactorUnavailable =>
      'Verificatie in twee stappen is niet beschikbaar voor dit account. De inlogbeveiliging wordt beheerd via je ZCLOUD-account.';

  @override
  String get twoFactorEnable => 'Aanzetten';

  @override
  String get twoFactorSetupInstructions =>
      'Scan deze QR-code met je authenticator-app of voer de installatiesleutel handmatig in. Typ daarna de 6-cijferige code die de app toont.';

  @override
  String get twoFactorSetupKey => 'Installatiesleutel';

  @override
  String get twoFactorCopy => 'Kopiëren';

  @override
  String get twoFactorCopied => 'Gekopieerd';

  @override
  String get twoFactorConfirmButton => 'Bevestigen en aanzetten';

  @override
  String get twoFactorRecoveryCodesTitle => 'Bewaar je herstelcodes';

  @override
  String get twoFactorRecoveryCodesInfo =>
      'Elke code werkt één keer als je geen toegang meer hebt tot je authenticator-app. Ze worden alleen nu getoond.';

  @override
  String get twoFactorCopyCodes => 'Alle codes kopiëren';

  @override
  String get twoFactorDone => 'Klaar';

  @override
  String get twoFactorDisable => 'Uitzetten';

  @override
  String get twoFactorDisableInfo =>
      'Voer je wachtwoord en een actuele code (of een herstelcode) in om verificatie in twee stappen uit te zetten.';

  @override
  String get twoFactorDisableConfirm => 'Verificatie in twee stappen uitzetten';

  @override
  String get twoFactorPasswordInvalid => 'Het wachtwoord is onjuist.';
}
