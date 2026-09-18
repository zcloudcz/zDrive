// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Finnish (`fi`).
class AppLocalizationsFi extends AppLocalizations {
  AppLocalizationsFi([String locale = 'fi']) : super(locale);

  @override
  String get exportDiagnostics => 'Vie diagnostiikkaloki';

  @override
  String get diagnosticsPreparing => 'Valmistellaan diagnostiikkalokia…';

  @override
  String get diagnosticsSaved => 'Diagnostiikkaloki tallennettu.';

  @override
  String get diagnosticsFailed => 'Lokin vienti epäonnistui. Yritä uudelleen.';

  @override
  String get aboutApp => 'Tietoja sovelluksesta';

  @override
  String get exitApp => 'Lopeta';

  @override
  String get exitFailed => 'Sovellusta ei voitu sulkea. Yritä uudelleen.';

  @override
  String get appVersionFailed => 'Sovelluksen versiota ei voitu ladata.';

  @override
  String appVersion(String version) {
    return 'Versio $version';
  }

  @override
  String get appTitle => 'zDrive';

  @override
  String get downloadForWindows => 'Lataa Windowsille';

  @override
  String get login => 'Kirjautuminen';

  @override
  String get register => 'Rekisteröityminen';

  @override
  String get email => 'Sähköposti';

  @override
  String get password => 'Salasana';

  @override
  String get confirmPassword => 'Vahvista salasana';

  @override
  String get displayName => 'Näyttönimi';

  @override
  String get files => 'Tiedostot';

  @override
  String get photos => 'Kuvat';

  @override
  String get settings => 'Asetukset';

  @override
  String get logout => 'Kirjaudu ulos';

  @override
  String get createAccount => 'Luo tili';

  @override
  String get loginButton => 'Kirjaudu sisään';

  @override
  String get registerButton => 'Luo tili';

  @override
  String get emailRequired => 'Sähköpostiosoite vaaditaan';

  @override
  String get invalidEmail => 'Anna kelvollinen sähköpostiosoite';

  @override
  String get passwordTooShort =>
      'Salasanan on oltava vähintään 8 merkkiä pitkä';

  @override
  String get passwordsDontMatch => 'Salasanat eivät täsmää';

  @override
  String get displayNameRequired => 'Näyttönimi vaaditaan';

  @override
  String get loginFailed =>
      'Kirjautuminen epäonnistui. Tarkista kirjautumistietosi.';

  @override
  String get registerFailed =>
      'Rekisteröityminen epäonnistui. Yritä uudelleen.';

  @override
  String comingSoon(String feature) {
    return '$feature tulossa pian';
  }

  @override
  String get folders => 'Kansiot';

  @override
  String get newItem => 'Uusi';

  @override
  String get newFolder => 'Uusi kansio';

  @override
  String get uploadFile => 'Lähetä tiedosto';

  @override
  String get rename => 'Nimeä uudelleen';

  @override
  String get delete => 'Poista';

  @override
  String get share => 'Jaa';

  @override
  String get restore => 'Palauta';

  @override
  String get emptyTrash => 'Tyhjennä roskakori';

  @override
  String get trash => 'Roskakori';

  @override
  String get search => 'Hae';

  @override
  String get clearSearch => 'Tyhjennä haku';

  @override
  String get refresh => 'Päivitä';

  @override
  String get gridView => 'Ruudukkonäkymä';

  @override
  String get listView => 'Luettelonäkymä';

  @override
  String get noFiles => 'Ei tiedostoja';

  @override
  String get createFolder => 'Luo kansio';

  @override
  String get folderName => 'Kansion nimi';

  @override
  String get enterFolderName => 'Anna kansion nimi';

  @override
  String get fileDeleted => 'Tiedosto poistettu';

  @override
  String get fileRestored => 'Tiedosto palautettu';

  @override
  String get shareLink => 'Jakolinkki';

  @override
  String get copyLink => 'Kopioi linkki';

  @override
  String get linkCopied => 'Linkki kopioitu';

  @override
  String get permission => 'Käyttöoikeus';

  @override
  String get readOnly => 'Vain luku';

  @override
  String get readWrite => 'Luku ja kirjoitus';

  @override
  String get allowDelete => 'Salli poistaminen';

  @override
  String get allowDeleteHelp =>
      'Poistetut kohteet siirtyvät omistajan roskakoriin.';

  @override
  String get expiresAt => 'Voimassa asti';

  @override
  String get never => 'Ei koskaan';

  @override
  String get uploadProgress => 'Lähetetään…';

  @override
  String get downloadProgress => 'Ladataan…';

  @override
  String get uploadComplete => 'Lähetys valmis';

  @override
  String get confirmDelete => 'Vahvista poistaminen';

  @override
  String get confirmEmptyTrash =>
      'Poistetaanko kaikki roskakorin kohteet pysyvästi?';

  @override
  String get cancel => 'Peruuta';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Yritä uudelleen';

  @override
  String get loadMore => 'Lataa lisää';

  @override
  String get noPhotos => 'Ei vielä kuvia';

  @override
  String get albums => 'Albumit';

  @override
  String get noAlbums => 'Ei vielä albumeita';

  @override
  String get newAlbum => 'Uusi albumi';

  @override
  String get albumName => 'Albumin nimi';

  @override
  String get syncStatus => 'Synkronoinnin tila';

  @override
  String get syncDevices => 'Laitteet';

  @override
  String get syncNoDevices => 'Ei rekisteröityjä laitteita';

  @override
  String get syncNeverSynced => 'Ei koskaan synkronoitu';

  @override
  String get syncChooseFolder => 'Valitse synkronointikansio';

  @override
  String get syncFolderNotConfigured =>
      'Valitse paikallinen kansio aloittaaksesi tämän laitteen synkronoinnin.';

  @override
  String get syncPulling => 'Synkronoidaan…';

  @override
  String get syncDeviceUpToDate => 'Tämä laite on ajan tasalla.';

  @override
  String get syncItemsSkipped => 'Joitakin kohteita ei voitu synkronoida';

  @override
  String get syncSkippedItems => 'Ohitetut kohteet';

  @override
  String get syncFolderNotEmptyTitle => 'Kansio ei ole tyhjä';

  @override
  String get syncFolderNotEmptyMessage =>
      'Tässä kansiossa on jo tiedostoja. Synkronointi ei korvaa tiedostoja, joita se ei itse ole luonut. Ristiriitaiset tiedostot jätetään ennalleen ja näytetään ohitettuina.';

  @override
  String get syncUnsupportedPlatform =>
      'Synkronointi on käytettävissä Windows- ja macOS-sovelluksessa';

  @override
  String get versionHistory => 'Versiohistoria';

  @override
  String get noVersions => 'Ei vielä versioita';

  @override
  String get restoreVersion => 'Palauta';

  @override
  String versionLabel(int number) {
    return 'Versio $number';
  }

  @override
  String get confirmRestoreVersion => 'Palautetaanko tämä versio?';

  @override
  String get versionRestored => 'Versio palautettu';

  @override
  String get latestVersion => 'Uusin';

  @override
  String get close => 'Sulje';

  @override
  String get errorNoConnection =>
      'Palvelimeen ei saada yhteyttä. Tarkista yhteys ja yritä uudelleen.';

  @override
  String get errorServiceUnavailable =>
      'Tämä toiminto on tilapäisesti poissa käytöstä. Yritä myöhemmin uudelleen.';

  @override
  String get errorRequestFailed => 'Pyyntöä ei voitu suorittaa.';

  @override
  String get syncConnecting => 'Yhdistetään…';

  @override
  String get syncDownloading => 'Ladataan';

  @override
  String get syncScanning => 'Tarkistetaan kansiota';

  @override
  String get syncHashing => 'Verrataan tiedostojen sisältöä';

  @override
  String get syncUploading => 'Lähetetään';

  @override
  String get syncDeleting => 'Suoritetaan poistoja';

  @override
  String get syncDiscovering =>
      'Etsitään kohteita — kokonaismäärä ei ole vielä tiedossa';

  @override
  String syncProgressCounts(int completed, int total, int remaining) {
    return '$completed / $total kohdetta valmiina · $remaining jäljellä';
  }

  @override
  String syncProgressFailures(int count) {
    return '$count kohdetta epäonnistui';
  }

  @override
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  ) {
    return '$transferred / $total · $remaining jäljellä';
  }

  @override
  String syncKnownProgressCounts(int completed, int total, int remaining) {
    return 'Tunnetut kohteet: $completed / $total valmiina · $remaining jäljellä';
  }

  @override
  String get updateRetry => 'Yritä päivitystä uudelleen';

  @override
  String get updateRestarting =>
      'Viimeistellään synkronointi ennen uudelleenkäynnistystä…';

  @override
  String get updateRestart => 'Käynnistä uudelleen ja päivitä';

  @override
  String updateDownloading(int percent) {
    return 'Ladataan päivitystä: $percent%';
  }

  @override
  String updateReady(String version) {
    return 'Päivitys $version on valmis. Se asennetaan seuraavan käynnistyksen yhteydessä.';
  }

  @override
  String get updateFailed =>
      'Automaattinen päivitys epäonnistui. Voit jatkaa zDriven käyttöä ja yrittää uudelleen.';

  @override
  String get shareNotFoundTitle => 'Linkkiä ei löytynyt';

  @override
  String get shareNotFoundMessage =>
      'Tämä jakolinkki on virheellinen, vanhentunut tai poistettu.';

  @override
  String get sharePasswordProtectedTitle => 'Salasana vaaditaan';

  @override
  String get sharePasswordProtectedMessage =>
      'Tämä jakolinkki on salasanasuojattu, mitä ei vielä tueta.';

  @override
  String get openZDrive => 'Avaa zDrive';

  @override
  String get download => 'Lataa';
}
