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
}
