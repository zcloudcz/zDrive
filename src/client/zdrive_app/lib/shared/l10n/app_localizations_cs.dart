// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Czech (`cs`).
class AppLocalizationsCs extends AppLocalizations {
  AppLocalizationsCs([String locale = 'cs']) : super(locale);

  @override
  String get exportDiagnostics => 'Exportovat diagnostický log';

  @override
  String get diagnosticsPreparing => 'Připravuji diagnostický log…';

  @override
  String get diagnosticsSaved => 'Diagnostický log byl uložen.';

  @override
  String get diagnosticsFailed =>
      'Log se nepodařilo vyexportovat. Zkuste to znovu.';

  @override
  String get aboutApp => 'O programu';

  @override
  String get exitApp => 'Ukončit';

  @override
  String get exitFailed => 'Aplikaci se nepodařilo ukončit. Zkuste to znovu.';

  @override
  String get appVersionFailed => 'Verzi aplikace se nepodařilo načíst.';

  @override
  String appVersion(String version) {
    return 'Verze $version';
  }

  @override
  String get appTitle => 'zDrive';

  @override
  String get downloadForWindows => 'Stáhnout pro Windows';

  @override
  String get login => 'Přihlášení';

  @override
  String get register => 'Registrace';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Heslo';

  @override
  String get confirmPassword => 'Potvrdit heslo';

  @override
  String get displayName => 'Zobrazované jméno';

  @override
  String get files => 'Soubory';

  @override
  String get photos => 'Fotky';

  @override
  String get settings => 'Nastavení';

  @override
  String get logout => 'Odhlásit';

  @override
  String get createAccount => 'Vytvořit účet';

  @override
  String get loginButton => 'Přihlásit se';

  @override
  String get registerButton => 'Vytvořit účet';

  @override
  String get emailRequired => 'E-mail je povinný';

  @override
  String get invalidEmail => 'Zadejte platný e-mail';

  @override
  String get passwordTooShort => 'Heslo musí mít alespoň 8 znaků';

  @override
  String get passwordsDontMatch => 'Hesla se neshodují';

  @override
  String get displayNameRequired => 'Zobrazované jméno je povinné';

  @override
  String get loginFailed => 'Přihlášení selhalo. Zkontrolujte údaje.';

  @override
  String get registerFailed => 'Registrace selhala. Zkuste to znovu.';

  @override
  String comingSoon(String feature) {
    return '$feature již brzy';
  }

  @override
  String get folders => 'Složky';

  @override
  String get newItem => 'Nové';

  @override
  String get newFolder => 'Nová složka';

  @override
  String get uploadFile => 'Nahrát soubor';

  @override
  String get rename => 'Přejmenovat';

  @override
  String get delete => 'Smazat';

  @override
  String get share => 'Sdílet';

  @override
  String get restore => 'Obnovit';

  @override
  String get emptyTrash => 'Vysypat koš';

  @override
  String get trash => 'Koš';

  @override
  String get search => 'Hledat';

  @override
  String get clearSearch => 'Vymazat hledání';

  @override
  String get refresh => 'Obnovit';

  @override
  String get gridView => 'Zobrazit mřížku';

  @override
  String get listView => 'Zobrazit seznam';

  @override
  String get noFiles => 'Žádné soubory';

  @override
  String get noFilesBody => 'Nahrajte soubor nebo vytvořte složku a začněte.';

  @override
  String get createFolder => 'Vytvořit složku';

  @override
  String get folderName => 'Název složky';

  @override
  String get enterFolderName => 'Zadejte název složky';

  @override
  String get fileDeleted => 'Soubor smazán';

  @override
  String get fileRestored => 'Soubor obnoven';

  @override
  String get shareLink => 'Odkaz ke sdílení';

  @override
  String get copyLink => 'Kopírovat odkaz';

  @override
  String get linkCopied => 'Odkaz zkopírován';

  @override
  String get permission => 'Oprávnění';

  @override
  String get readOnly => 'Jen ke čtení';

  @override
  String get readWrite => 'Čtení a zápis';

  @override
  String get allowDelete => 'Povolit mazání';

  @override
  String get allowDeleteHelp => 'Smazané položky skončí v koši vlastníka.';

  @override
  String get expiresAt => 'Platnost do';

  @override
  String get never => 'Neomezeně';

  @override
  String get uploadProgress => 'Nahrávání...';

  @override
  String get downloadProgress => 'Stahování...';

  @override
  String get uploadComplete => 'Nahrávání dokončeno';

  @override
  String get confirmDelete => 'Potvrdit smazání';

  @override
  String get confirmEmptyTrash => 'Trvale smazat vše v koši?';

  @override
  String get cancel => 'Zrušit';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Zkusit znovu';

  @override
  String get loadMore => 'Načíst další';

  @override
  String get noPhotos => 'Zatím žádné fotky';

  @override
  String get albums => 'Alba';

  @override
  String get noAlbums => 'Zatím žádná alba';

  @override
  String get newAlbum => 'Nové album';

  @override
  String get albumName => 'Název alba';

  @override
  String get syncStatus => 'Stav synchronizace';

  @override
  String get syncDevices => 'Zařízení';

  @override
  String get syncNoDevices => 'Žádná zaregistrovaná zařízení';

  @override
  String get syncNeverSynced => 'Nikdy nesynchronizováno';

  @override
  String get syncChooseFolder => 'Vybrat synchronizovanou složku';

  @override
  String get syncFolderNotConfigured =>
      'Vyberte místní složku, aby se toto zařízení začalo synchronizovat.';

  @override
  String get syncPulling => 'Synchronizuji…';

  @override
  String get syncDeviceUpToDate => 'Toto zařízení je aktuální.';

  @override
  String get syncItemsSkipped => 'Některé položky se nepodařilo synchronizovat';

  @override
  String get syncSkippedItems => 'Přeskočené položky';

  @override
  String get syncFolderNotEmptyTitle => 'Složka není prázdná';

  @override
  String get syncFolderNotEmptyMessage =>
      'Tato složka už obsahuje soubory. Synchronizace nic z toho, co v ní není z jejího vlastního zásahu, nepřepíše — kolidující soubory zůstanou beze změny a zobrazí se jako přeskočené.';

  @override
  String get syncUnsupportedPlatform =>
      'Synchronizace je k dispozici v aplikaci pro Windows a macOS';

  @override
  String get versionHistory => 'Historie verzí';

  @override
  String get noVersions => 'Zatím žádné verze';

  @override
  String get restoreVersion => 'Obnovit';

  @override
  String versionLabel(int number) {
    return 'Verze $number';
  }

  @override
  String get confirmRestoreVersion => 'Obnovit tuto verzi?';

  @override
  String get versionRestored => 'Verze obnovena';

  @override
  String get latestVersion => 'Aktuální';

  @override
  String get close => 'Zavřít';

  @override
  String get errorNoConnection =>
      'Server je nedostupný. Zkontroluj připojení a zkus to znovu.';

  @override
  String get errorServiceUnavailable =>
      'Tato funkce je teď nedostupná. Zkus to prosím později.';

  @override
  String get errorRequestFailed => 'Požadavek se nepodařilo dokončit.';

  @override
  String get syncConnecting => 'Připojování…';

  @override
  String get syncDownloading => 'Stahování';

  @override
  String get syncScanning => 'Procházení složky';

  @override
  String get syncHashing => 'Porovnávání obsahu souborů';

  @override
  String get syncUploading => 'Nahrávání';

  @override
  String get syncDeleting => 'Zpracování smazání';

  @override
  String get syncDiscovering =>
      'Hledání položek — celkový počet zatím není znám';

  @override
  String syncProgressCounts(int completed, int total, int remaining) {
    return 'Dokončeno $completed / $total položek · zbývá $remaining';
  }

  @override
  String syncProgressFailures(int count) {
    return 'Selhalo $count položek';
  }

  @override
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  ) {
    return '$transferred / $total · zbývá $remaining';
  }

  @override
  String syncKnownProgressCounts(int completed, int total, int remaining) {
    return 'Známé položky: dokončeno $completed / $total · zbývá $remaining';
  }

  @override
  String get updateRetry => 'Zkusit aktualizaci znovu';

  @override
  String get updateRestarting => 'Dokončuji synchronizaci před restartováním…';

  @override
  String get updateRestart => 'Restartovat a aktualizovat';

  @override
  String updateDownloading(int percent) {
    return 'Stahování aktualizace: $percent%';
  }

  @override
  String updateReady(String version) {
    return 'Aktualizace $version je připravena. Nainstaluje se při příštím spuštění.';
  }

  @override
  String get updateFailed =>
      'Automatická aktualizace se nezdařila. zDrive můžete dál používat a zkusit to znovu.';

  @override
  String get shareNotFoundTitle => 'Odkaz nenalezen';

  @override
  String get shareNotFoundMessage =>
      'Tento sdílený odkaz je neplatný, vypršel nebo byl odstraněn.';

  @override
  String get sharePasswordProtectedTitle => 'Vyžaduje se heslo';

  @override
  String get sharePasswordProtectedMessage =>
      'Tento sdílený odkaz je chráněný heslem, což zatím není podporováno.';

  @override
  String get openZDrive => 'Otevřít zDrive';

  @override
  String get download => 'Stáhnout';

  @override
  String shareAvailableUntil(Object date) {
    return 'Dostupné do $date';
  }

  @override
  String get shareWhatIsZDrive => 'Co je zDrive?';

  @override
  String get shareFooterTagline => 'Zabezpečeno pomocí zDrive';

  @override
  String get shareReplaceFile => 'Nahradit soubor';

  @override
  String get shareDeleteConfirmMessage =>
      'Tato položka bude přesunuta do koše vlastníka.';

  @override
  String get shareOverwriteTitle => 'Nahradit existující soubor?';

  @override
  String shareOverwriteMessage(Object name) {
    return 'Soubor s názvem \"$name\" již existuje. Nahráním vznikne jeho nová verze.';
  }

  @override
  String get shareReplaceConfirm => 'Nahradit';

  @override
  String get shareErrorNotAllowed => 'Tento odkaz to neumožňuje.';

  @override
  String get shareErrorNameExists =>
      'Soubor nebo složka s tímto názvem již existuje.';

  @override
  String get shareErrorQuotaExceeded => 'Úložiště vlastníka je plné.';

  @override
  String get shareErrorTooManyUploads =>
      'Stále se zpracovává příliš mnoho nahrávání. Zkuste to prosím za chvíli znovu.';

  @override
  String get tagline => 'Vaše soubory, kdekoli.';

  @override
  String get authBenefitSync => 'Synchronizace napříč všemi zařízeními';

  @override
  String get authBenefitShare => 'Bezpečné sdílení souborů a složek';

  @override
  String get authBenefitSecure => 'Vždy šifrované úložiště';

  @override
  String get offlineCloudOnly => 'Pouze v cloudu';

  @override
  String get offlineDownloading => 'Stahuje se';

  @override
  String get offlineAvailable => 'Dostupné v tomto zařízení';

  @override
  String get offlineAlwaysKeep => 'Vždy uchováváno v tomto zařízení';

  @override
  String get keepOnDevice => 'Vždy uchovávat v tomto zařízení';

  @override
  String get freeUpSpace => 'Uvolnit místo';

  @override
  String freeUpSkippedUnsynced(int count) {
    return '$count ponecháno v tomto zařízení: nesynchronizované změny';
  }

  @override
  String get cloudMigrationTitle => 'Uvolnit místo v tomto zařízení?';

  @override
  String cloudMigrationBody(int count, String size) {
    return 'Soubory ve vaší synchronizované složce se nyní uchovávají v cloudu a stahují se, až když je potřebujete. Souborů, které lze z tohoto zařízení odstranit: $count, až $size.';
  }

  @override
  String get cloudMigrationReassure =>
      'Vaše soubory zůstanou dostupné v cloudu i na webu a můžete si je kdykoli stáhnout znovu. Soubory s dosud nesynchronizovanými změnami se vždy ponechají.';

  @override
  String get cloudMigrationKeepAll => 'Ponechat vše v tomto zařízení';

  @override
  String get cloudMigrationLater => 'Rozhodnout později';

  @override
  String get cloudMigrationWorking => 'Uvolňuje se místo…';

  @override
  String cloudMigrationFreed(int count, String size) {
    return 'Uvolněno souborů: $count, $size';
  }

  @override
  String freeUpKeptPinned(int count) {
    return '$count ponecháno v tomto zařízení: vždy ponechat';
  }

  @override
  String get cloudMigrationKeeping => 'Ponechává se vše v tomto zařízení…';
}
