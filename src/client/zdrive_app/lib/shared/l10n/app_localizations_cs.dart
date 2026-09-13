// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Czech (`cs`).
class AppLocalizationsCs extends AppLocalizations {
  AppLocalizationsCs([String locale = 'cs']) : super(locale);

  @override
  String get appTitle => 'zDrive';

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
  String get refresh => 'Obnovit';

  @override
  String get noFiles => 'Žádné soubory';

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
  String get expiresAt => 'Platnost do';

  @override
  String get never => 'Neomezeně';

  @override
  String get uploadProgress => 'Nahrávání...';

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
}
