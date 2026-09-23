// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Slovak (`sk`).
class AppLocalizationsSk extends AppLocalizations {
  AppLocalizationsSk([String locale = 'sk']) : super(locale);

  @override
  String get exportDiagnostics => 'Exportovať diagnostický log';

  @override
  String get diagnosticsPreparing => 'Pripravujem diagnostický log…';

  @override
  String get diagnosticsSaved => 'Diagnostický log bol uložený.';

  @override
  String get diagnosticsFailed =>
      'Log sa nepodarilo exportovať. Skúste to znova.';

  @override
  String get aboutApp => 'O aplikácii';

  @override
  String get exitApp => 'Ukončiť';

  @override
  String get exitFailed => 'Aplikáciu sa nepodarilo ukončiť. Skúste to znova.';

  @override
  String get appVersionFailed => 'Verziu aplikácie sa nepodarilo načítať.';

  @override
  String appVersion(String version) {
    return 'Verzia $version';
  }

  @override
  String get appTitle => 'zDrive';

  @override
  String get downloadForWindows => 'Stiahnuť pre Windows';

  @override
  String get login => 'Prihlásenie';

  @override
  String get register => 'Registrácia';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Heslo';

  @override
  String get confirmPassword => 'Potvrdiť heslo';

  @override
  String get displayName => 'Zobrazované meno';

  @override
  String get files => 'Súbory';

  @override
  String get photos => 'Fotografie';

  @override
  String get settings => 'Nastavenia';

  @override
  String get logout => 'Odhlásiť sa';

  @override
  String get createAccount => 'Vytvoriť účet';

  @override
  String get loginButton => 'Prihlásiť sa';

  @override
  String get entraSignInButton => 'Prihlásiť sa účtom ZCLOUD';

  @override
  String get entraStateMismatch =>
      'Prihlásenie sa nepodarilo overiť. Skúste to znova.';

  @override
  String get entraSignInDenied => 'Prihlásenie bolo zrušené.';

  @override
  String get registerButton => 'Vytvoriť účet';

  @override
  String get emailRequired => 'E-mail je povinný';

  @override
  String get invalidEmail => 'Zadajte platnú e-mailovú adresu';

  @override
  String get passwordTooShort => 'Heslo musí mať aspoň 8 znakov';

  @override
  String get passwordsDontMatch => 'Heslá sa nezhodujú';

  @override
  String get displayNameRequired => 'Zobrazované meno je povinné';

  @override
  String get loginFailed =>
      'Prihlásenie zlyhalo. Skontrolujte prihlasovacie údaje.';

  @override
  String get registerFailed => 'Registrácia zlyhala. Skúste to znova.';

  @override
  String comingSoon(String feature) {
    return '$feature už čoskoro';
  }

  @override
  String get folders => 'Priečinky';

  @override
  String get newItem => 'Nové';

  @override
  String get newFolder => 'Nový priečinok';

  @override
  String get uploadFile => 'Nahrať súbor';

  @override
  String get rename => 'Premenovať';

  @override
  String get delete => 'Odstrániť';

  @override
  String get share => 'Zdieľať';

  @override
  String get restore => 'Obnoviť';

  @override
  String get emptyTrash => 'Vyprázdniť kôš';

  @override
  String get trash => 'Kôš';

  @override
  String get search => 'Hľadať';

  @override
  String get clearSearch => 'Vymazať vyhľadávanie';

  @override
  String get refresh => 'Obnoviť';

  @override
  String get gridView => 'Zobraziť mriežku';

  @override
  String get listView => 'Zobraziť zoznam';

  @override
  String get noFiles => 'Žiadne súbory';

  @override
  String get noFilesBody =>
      'Nahrajte súbor alebo vytvorte priečinok a začnite.';

  @override
  String get createFolder => 'Vytvoriť priečinok';

  @override
  String get folderName => 'Názov priečinka';

  @override
  String get enterFolderName => 'Zadajte názov priečinka';

  @override
  String get fileDeleted => 'Súbor bol odstránený';

  @override
  String get fileRestored => 'Súbor bol obnovený';

  @override
  String get shareLink => 'Odkaz na zdieľanie';

  @override
  String get copyLink => 'Kopírovať odkaz';

  @override
  String get linkCopied => 'Odkaz bol skopírovaný';

  @override
  String get permission => 'Oprávnenie';

  @override
  String get readOnly => 'Iba čítanie';

  @override
  String get readWrite => 'Čítanie a zápis';

  @override
  String get allowDelete => 'Povoliť mazanie';

  @override
  String get allowDeleteHelp => 'Vymazané položky skončia v koši vlastníka.';

  @override
  String get expiresAt => 'Platnosť do';

  @override
  String get never => 'Nikdy';

  @override
  String get uploadProgress => 'Nahráva sa…';

  @override
  String get downloadProgress => 'Sťahuje sa…';

  @override
  String get uploadComplete => 'Nahrávanie dokončené';

  @override
  String get confirmDelete => 'Potvrdiť odstránenie';

  @override
  String get confirmEmptyTrash => 'Natrvalo odstrániť všetky položky v koši?';

  @override
  String get cancel => 'Zrušiť';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Skúsiť znova';

  @override
  String get loadMore => 'Načítať ďalšie';

  @override
  String get noPhotos => 'Zatiaľ žiadne fotografie';

  @override
  String get albums => 'Albumy';

  @override
  String get noAlbums => 'Zatiaľ žiadne albumy';

  @override
  String get newAlbum => 'Nový album';

  @override
  String get albumName => 'Názov albumu';

  @override
  String get syncStatus => 'Stav synchronizácie';

  @override
  String get syncDevices => 'Zariadenia';

  @override
  String get syncNoDevices => 'Žiadne registrované zariadenia';

  @override
  String get syncNeverSynced => 'Zatiaľ nesynchronizované';

  @override
  String get syncChooseFolder => 'Vybrať priečinok na synchronizáciu';

  @override
  String get syncFolderNotConfigured =>
      'Vyberte miestny priečinok a začnite synchronizovať toto zariadenie.';

  @override
  String get syncPulling => 'Synchronizuje sa…';

  @override
  String get syncDeviceUpToDate => 'Toto zariadenie je aktuálne.';

  @override
  String get syncItemsSkipped =>
      'Niektoré položky sa nepodarilo synchronizovať';

  @override
  String get syncSkippedItems => 'Preskočené položky';

  @override
  String get syncFolderNotEmptyTitle => 'Priečinok nie je prázdny';

  @override
  String get syncFolderNotEmptyMessage =>
      'Tento priečinok už obsahuje súbory. Synchronizácia neprepíše nič, čo sama nevytvorila — súbory, ktoré by boli v konflikte, ponechá nedotknuté a uvedie medzi preskočenými.';

  @override
  String get syncUnsupportedPlatform =>
      'Synchronizácia je dostupná v aplikácii pre Windows a macOS';

  @override
  String get versionHistory => 'História verzií';

  @override
  String get noVersions => 'Zatiaľ žiadne verzie';

  @override
  String get restoreVersion => 'Obnoviť';

  @override
  String versionLabel(int number) {
    return 'Verzia $number';
  }

  @override
  String get confirmRestoreVersion => 'Obnoviť túto verziu?';

  @override
  String get versionRestored => 'Verzia bola obnovená';

  @override
  String get latestVersion => 'Najnovšia';

  @override
  String get close => 'Zavrieť';

  @override
  String get errorNoConnection =>
      'Nepodarilo sa pripojiť k serveru. Skontrolujte pripojenie a skúste to znova.';

  @override
  String get errorServiceUnavailable =>
      'Táto funkcia je dočasne nedostupná. Skúste to neskôr.';

  @override
  String get errorRequestFailed => 'Požiadavku sa nepodarilo dokončiť.';

  @override
  String get syncConnecting => 'Pripája sa…';

  @override
  String get syncDownloading => 'Sťahuje sa';

  @override
  String get syncScanning => 'Prehľadáva sa priečinok';

  @override
  String get syncHashing => 'Porovnáva sa obsah súborov';

  @override
  String get syncUploading => 'Nahráva sa';

  @override
  String get syncDeleting => 'Odstraňujú sa položky';

  @override
  String get syncDiscovering =>
      'Vyhľadávajú sa položky — celkový počet zatiaľ nie je známy';

  @override
  String syncProgressCounts(int completed, int total, int remaining) {
    return 'Dokončené položky: $completed / $total · zostáva $remaining';
  }

  @override
  String syncProgressFailures(int count) {
    return 'Počet neúspešných položiek: $count';
  }

  @override
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  ) {
    return '$transferred / $total · zostáva $remaining';
  }

  @override
  String syncKnownProgressCounts(int completed, int total, int remaining) {
    return 'Známe položky: $completed / $total dokončených · zostáva $remaining';
  }

  @override
  String get updateRetry => 'Zopakovať aktualizáciu';

  @override
  String get updateRestarting => 'Dokončuje sa synchronizácia pred reštartom…';

  @override
  String get updateRestart => 'Reštartovať a aktualizovať';

  @override
  String updateDownloading(int percent) {
    return 'Sťahuje sa aktualizácia: $percent%';
  }

  @override
  String updateReady(String version) {
    return 'Aktualizácia $version je pripravená. Nainštaluje sa pri ďalšom spustení.';
  }

  @override
  String get updateFailed =>
      'Automatická aktualizácia zlyhala. Môžete ďalej používať zDrive a skúsiť to znova.';

  @override
  String get shareNotFoundTitle => 'Odkaz sa nenašiel';

  @override
  String get shareNotFoundMessage =>
      'Tento zdieľaný odkaz je neplatný, vypršal alebo bol odstránený.';

  @override
  String get sharePasswordProtectedTitle => 'Vyžaduje sa heslo';

  @override
  String get sharePasswordProtectedMessage =>
      'Tento zdieľaný odkaz je chránený heslom, čo zatiaľ nie je podporované.';

  @override
  String get openZDrive => 'Otvoriť zDrive';

  @override
  String get download => 'Stiahnuť';

  @override
  String shareAvailableUntil(Object date) {
    return 'Dostupné do $date';
  }

  @override
  String get shareWhatIsZDrive => 'Čo je zDrive?';

  @override
  String get shareFooterTagline => 'Zabezpečené pomocou zDrive';

  @override
  String get shareReplaceFile => 'Nahradiť súbor';

  @override
  String get shareDeleteConfirmMessage =>
      'Táto položka bude presunutá do koša vlastníka.';

  @override
  String get shareOverwriteTitle => 'Nahradiť existujúci súbor?';

  @override
  String shareOverwriteMessage(Object name) {
    return 'Súbor s názvom \"$name\" už existuje. Nahratím vznikne jeho nová verzia.';
  }

  @override
  String get shareReplaceConfirm => 'Nahradiť';

  @override
  String get shareErrorNotAllowed => 'Tento odkaz to neumožňuje.';

  @override
  String get shareErrorNameExists =>
      'Súbor alebo priečinok s týmto názvom už existuje.';

  @override
  String get shareErrorQuotaExceeded => 'Úložisko vlastníka je plné.';

  @override
  String get shareErrorTooManyUploads =>
      'Stále sa spracúva príliš veľa nahrávaní. Skúste to o chvíľu znova.';

  @override
  String get tagline => 'Vaše súbory, kdekoľvek.';

  @override
  String get authBenefitSync => 'Synchronizácia naprieč všetkými zariadeniami';

  @override
  String get authBenefitShare => 'Bezpečné zdieľanie súborov a priečinkov';

  @override
  String get authBenefitSecure => 'Vždy šifrované úložisko';

  @override
  String get offlineCloudOnly => 'Iba v cloude';

  @override
  String get offlineDownloading => 'Sťahuje sa';

  @override
  String get offlineAvailable => 'Dostupné v tomto zariadení';

  @override
  String get offlineAlwaysKeep => 'Vždy uchovávané v tomto zariadení';

  @override
  String get keepOnDevice => 'Vždy uchovávať v tomto zariadení';

  @override
  String get freeUpSpace => 'Uvoľniť miesto';

  @override
  String freeUpSkippedUnsynced(int count) {
    return '$count ponechaných v tomto zariadení: nesynchronizované zmeny';
  }

  @override
  String get cloudMigrationTitle => 'Uvoľniť miesto v tomto zariadení?';

  @override
  String cloudMigrationBody(int count, String size) {
    return 'Súbory vo vašom synchronizovanom priečinku sa teraz uchovávajú v cloude a preberajú sa, až keď ich potrebujete. Súborov, ktoré možno z tohto zariadenia odstrániť: $count, až $size.';
  }

  @override
  String get cloudMigrationReassure =>
      'Vaše súbory zostanú dostupné v cloude aj na webe a môžete si ich kedykoľvek prevziať znova. Súbory s doteraz nesynchronizovanými zmenami sa vždy ponechajú.';

  @override
  String get cloudMigrationKeepAll => 'Ponechať všetko v tomto zariadení';

  @override
  String get cloudMigrationLater => 'Rozhodnúť neskôr';

  @override
  String get cloudMigrationWorking => 'Uvoľňuje sa miesto…';

  @override
  String cloudMigrationFreed(int count, String size) {
    return 'Uvoľnených súborov: $count, $size';
  }

  @override
  String freeUpKeptPinned(int count) {
    return '$count ponechaných v tomto zariadení: vždy ponechať';
  }

  @override
  String get cloudMigrationKeeping => 'Ponecháva sa všetko v tomto zariadení…';
}
