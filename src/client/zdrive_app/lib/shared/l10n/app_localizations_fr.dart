// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get exportDiagnostics => 'Exporter le journal de diagnostic';

  @override
  String get diagnosticsPreparing => 'Préparation du journal de diagnostic…';

  @override
  String get diagnosticsSaved => 'Journal de diagnostic enregistré.';

  @override
  String get diagnosticsFailed =>
      'Exportation du journal impossible. Réessayez.';

  @override
  String get aboutApp => 'À propos';

  @override
  String get exitApp => 'Quitter';

  @override
  String get exitFailed => 'Impossible de quitter l’application. Réessayez.';

  @override
  String get appVersionFailed =>
      'Impossible de charger la version de l’application.';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get appTitle => 'zDrive';

  @override
  String get downloadForWindows => 'Télécharger pour Windows';

  @override
  String get login => 'Connexion';

  @override
  String get register => 'Inscription';

  @override
  String get email => 'Adresse e-mail';

  @override
  String get password => 'Mot de passe';

  @override
  String get confirmPassword => 'Confirmer le mot de passe';

  @override
  String get displayName => 'Nom affiché';

  @override
  String get files => 'Fichiers';

  @override
  String get photos => 'Photos';

  @override
  String get settings => 'Paramètres';

  @override
  String get logout => 'Se déconnecter';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get loginButton => 'Se connecter';

  @override
  String get registerButton => 'Créer un compte';

  @override
  String get emailRequired => 'L’adresse e-mail est obligatoire';

  @override
  String get invalidEmail => 'Saisissez une adresse e-mail valide';

  @override
  String get passwordTooShort =>
      'Le mot de passe doit contenir au moins 8 caractères';

  @override
  String get passwordsDontMatch => 'Les mots de passe ne correspondent pas';

  @override
  String get displayNameRequired => 'Le nom affiché est obligatoire';

  @override
  String get loginFailed => 'Échec de la connexion. Vérifiez vos identifiants.';

  @override
  String get registerFailed => 'Échec de l’inscription. Réessayez.';

  @override
  String comingSoon(String feature) {
    return '$feature sera bientôt disponible';
  }

  @override
  String get folders => 'Dossiers';

  @override
  String get newItem => 'Nouveau';

  @override
  String get newFolder => 'Nouveau dossier';

  @override
  String get uploadFile => 'Importer un fichier';

  @override
  String get rename => 'Renommer';

  @override
  String get delete => 'Supprimer';

  @override
  String get share => 'Partager';

  @override
  String get restore => 'Restaurer';

  @override
  String get emptyTrash => 'Vider la corbeille';

  @override
  String get trash => 'Corbeille';

  @override
  String get search => 'Rechercher';

  @override
  String get clearSearch => 'Effacer la recherche';

  @override
  String get refresh => 'Actualiser';

  @override
  String get gridView => 'Vue en grille';

  @override
  String get listView => 'Vue en liste';

  @override
  String get noFiles => 'Aucun fichier';

  @override
  String get createFolder => 'Créer un dossier';

  @override
  String get folderName => 'Nom du dossier';

  @override
  String get enterFolderName => 'Saisissez le nom du dossier';

  @override
  String get fileDeleted => 'Fichier supprimé';

  @override
  String get fileRestored => 'Fichier restauré';

  @override
  String get shareLink => 'Lien de partage';

  @override
  String get copyLink => 'Copier le lien';

  @override
  String get linkCopied => 'Lien copié';

  @override
  String get permission => 'Autorisation';

  @override
  String get readOnly => 'Lecture seule';

  @override
  String get readWrite => 'Lecture et écriture';

  @override
  String get expiresAt => 'Expire le';

  @override
  String get never => 'Jamais';

  @override
  String get uploadProgress => 'Importation en cours…';

  @override
  String get downloadProgress => 'Téléchargement en cours…';

  @override
  String get uploadComplete => 'Importation terminée';

  @override
  String get confirmDelete => 'Confirmer la suppression';

  @override
  String get confirmEmptyTrash =>
      'Supprimer définitivement tous les éléments de la corbeille ?';

  @override
  String get cancel => 'Annuler';

  @override
  String get ok => 'OK';

  @override
  String get retry => 'Réessayer';

  @override
  String get loadMore => 'Charger plus';

  @override
  String get noPhotos => 'Aucune photo pour le moment';

  @override
  String get albums => 'Albums';

  @override
  String get noAlbums => 'Aucun album pour le moment';

  @override
  String get newAlbum => 'Nouvel album';

  @override
  String get albumName => 'Nom de l’album';

  @override
  String get syncStatus => 'État de la synchronisation';

  @override
  String get syncDevices => 'Appareils';

  @override
  String get syncNoDevices => 'Aucun appareil enregistré';

  @override
  String get syncNeverSynced => 'Jamais synchronisé';

  @override
  String get syncChooseFolder => 'Choisir le dossier à synchroniser';

  @override
  String get syncFolderNotConfigured =>
      'Choisissez un dossier local pour commencer à synchroniser cet appareil.';

  @override
  String get syncPulling => 'Synchronisation en cours…';

  @override
  String get syncDeviceUpToDate => 'Cet appareil est à jour.';

  @override
  String get syncItemsSkipped =>
      'Certains éléments n’ont pas pu être synchronisés';

  @override
  String get syncSkippedItems => 'Éléments ignorés';

  @override
  String get syncFolderNotEmptyTitle => 'Le dossier n’est pas vide';

  @override
  String get syncFolderNotEmptyMessage =>
      'Ce dossier contient déjà des fichiers. La synchronisation n’écrasera aucun fichier qu’elle n’a pas créé elle-même. Les fichiers en conflit seront conservés et indiqués comme ignorés.';

  @override
  String get syncUnsupportedPlatform =>
      'La synchronisation est disponible dans l’application pour Windows et macOS';

  @override
  String get versionHistory => 'Historique des versions';

  @override
  String get noVersions => 'Aucune version pour le moment';

  @override
  String get restoreVersion => 'Restaurer';

  @override
  String versionLabel(int number) {
    return 'Version $number';
  }

  @override
  String get confirmRestoreVersion => 'Restaurer cette version ?';

  @override
  String get versionRestored => 'Version restaurée';

  @override
  String get latestVersion => 'La plus récente';

  @override
  String get close => 'Fermer';

  @override
  String get errorNoConnection =>
      'Impossible de joindre le serveur. Vérifiez votre connexion et réessayez.';

  @override
  String get errorServiceUnavailable =>
      'Cette fonctionnalité est temporairement indisponible. Réessayez plus tard.';

  @override
  String get errorRequestFailed => 'La demande n’a pas pu être traitée.';

  @override
  String get syncConnecting => 'Connexion en cours…';

  @override
  String get syncDownloading => 'Téléchargement';

  @override
  String get syncScanning => 'Analyse du dossier';

  @override
  String get syncHashing => 'Comparaison du contenu des fichiers';

  @override
  String get syncUploading => 'Importation';

  @override
  String get syncDeleting => 'Application des suppressions';

  @override
  String get syncDiscovering =>
      'Recherche des éléments — le total n’est pas encore connu';

  @override
  String syncProgressCounts(int completed, int total, int remaining) {
    return '$completed / $total éléments terminés · $remaining restants';
  }

  @override
  String syncProgressFailures(int count) {
    return '$count éléments en échec';
  }

  @override
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  ) {
    return '$transferred / $total · $remaining restants';
  }

  @override
  String syncKnownProgressCounts(int completed, int total, int remaining) {
    return 'Éléments connus : $completed / $total terminés · $remaining restants';
  }

  @override
  String get updateRetry => 'Réessayer la mise à jour';

  @override
  String get updateRestarting =>
      'Fin de la synchronisation avant le redémarrage…';

  @override
  String get updateRestart => 'Redémarrer et mettre à jour';

  @override
  String updateDownloading(int percent) {
    return 'Téléchargement de la mise à jour : $percent%';
  }

  @override
  String updateReady(String version) {
    return 'La mise à jour $version est prête. Elle sera installée au prochain démarrage.';
  }

  @override
  String get updateFailed =>
      'La mise à jour automatique a échoué. Vous pouvez continuer à utiliser zDrive et réessayer.';

  @override
  String get shareNotFoundTitle => 'Lien introuvable';

  @override
  String get shareNotFoundMessage =>
      'Ce lien de partage est invalide, expiré ou a été supprimé.';

  @override
  String get sharePasswordProtectedTitle => 'Mot de passe requis';

  @override
  String get sharePasswordProtectedMessage =>
      'Ce lien de partage est protégé par un mot de passe, ce qui n’est pas encore pris en charge.';

  @override
  String get openZDrive => 'Ouvrir zDrive';

  @override
  String get download => 'Télécharger';
}
