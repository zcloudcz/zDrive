// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get exportDiagnostics => 'Exportar registro de diagnóstico';

  @override
  String get diagnosticsPreparing => 'Preparando el registro de diagnóstico…';

  @override
  String get diagnosticsSaved => 'Registro de diagnóstico guardado.';

  @override
  String get diagnosticsFailed =>
      'No se pudo exportar el registro. Inténtalo de nuevo.';

  @override
  String get aboutApp => 'Acerca de';

  @override
  String get exitApp => 'Salir';

  @override
  String get exitFailed =>
      'No se pudo cerrar la aplicación. Inténtalo de nuevo.';

  @override
  String get appVersionFailed =>
      'No se pudo cargar la versión de la aplicación.';

  @override
  String appVersion(String version) {
    return 'Versión $version';
  }

  @override
  String get appTitle => 'zDrive';

  @override
  String get downloadForWindows => 'Descargar para Windows';

  @override
  String get login => 'Inicio de sesión';

  @override
  String get register => 'Registro';

  @override
  String get email => 'Correo electrónico';

  @override
  String get password => 'Contraseña';

  @override
  String get confirmPassword => 'Confirmar contraseña';

  @override
  String get displayName => 'Nombre visible';

  @override
  String get files => 'Archivos';

  @override
  String get photos => 'Fotos';

  @override
  String get settings => 'Configuración';

  @override
  String get logout => 'Cerrar sesión';

  @override
  String get createAccount => 'Crear cuenta';

  @override
  String get loginButton => 'Iniciar sesión';

  @override
  String get registerButton => 'Crear cuenta';

  @override
  String get emailRequired => 'El correo electrónico es obligatorio';

  @override
  String get invalidEmail =>
      'Introduce una dirección de correo electrónico válida';

  @override
  String get passwordTooShort =>
      'La contraseña debe tener al menos 8 caracteres';

  @override
  String get passwordsDontMatch => 'Las contraseñas no coinciden';

  @override
  String get displayNameRequired => 'El nombre visible es obligatorio';

  @override
  String get loginFailed =>
      'No se pudo iniciar sesión. Comprueba tus credenciales.';

  @override
  String get registerFailed =>
      'No se pudo completar el registro. Inténtalo de nuevo.';

  @override
  String comingSoon(String feature) {
    return '$feature estará disponible pronto';
  }

  @override
  String get folders => 'Carpetas';

  @override
  String get newItem => 'Nuevo';

  @override
  String get newFolder => 'Nueva carpeta';

  @override
  String get uploadFile => 'Subir archivo';

  @override
  String get rename => 'Cambiar nombre';

  @override
  String get delete => 'Eliminar';

  @override
  String get share => 'Compartir';

  @override
  String get restore => 'Restaurar';

  @override
  String get emptyTrash => 'Vaciar papelera';

  @override
  String get trash => 'Papelera';

  @override
  String get search => 'Buscar';

  @override
  String get clearSearch => 'Borrar búsqueda';

  @override
  String get refresh => 'Actualizar';

  @override
  String get gridView => 'Vista de cuadrícula';

  @override
  String get listView => 'Vista de lista';

  @override
  String get noFiles => 'No hay archivos';

  @override
  String get noFilesBody => 'Sube un archivo o crea una carpeta para empezar.';

  @override
  String get createFolder => 'Crear carpeta';

  @override
  String get folderName => 'Nombre de la carpeta';

  @override
  String get enterFolderName => 'Introduce el nombre de la carpeta';

  @override
  String get fileDeleted => 'Archivo eliminado';

  @override
  String get fileRestored => 'Archivo restaurado';

  @override
  String get shareLink => 'Enlace para compartir';

  @override
  String get copyLink => 'Copiar enlace';

  @override
  String get linkCopied => 'Enlace copiado';

  @override
  String get permission => 'Permiso';

  @override
  String get readOnly => 'Solo lectura';

  @override
  String get readWrite => 'Lectura y escritura';

  @override
  String get allowDelete => 'Permitir eliminar';

  @override
  String get allowDeleteHelp =>
      'Los elementos eliminados van a la papelera del propietario.';

  @override
  String get expiresAt => 'Caduca el';

  @override
  String get never => 'Nunca';

  @override
  String get uploadProgress => 'Subiendo…';

  @override
  String get downloadProgress => 'Descargando…';

  @override
  String get uploadComplete => 'Subida completada';

  @override
  String get confirmDelete => 'Confirmar eliminación';

  @override
  String get confirmEmptyTrash =>
      '¿Eliminar permanentemente todos los elementos de la papelera?';

  @override
  String get cancel => 'Cancelar';

  @override
  String get ok => 'Aceptar';

  @override
  String get retry => 'Reintentar';

  @override
  String get loadMore => 'Cargar más';

  @override
  String get noPhotos => 'Aún no hay fotos';

  @override
  String get albums => 'Álbumes';

  @override
  String get noAlbums => 'Aún no hay álbumes';

  @override
  String get newAlbum => 'Nuevo álbum';

  @override
  String get albumName => 'Nombre del álbum';

  @override
  String get syncStatus => 'Estado de sincronización';

  @override
  String get syncDevices => 'Dispositivos';

  @override
  String get syncNoDevices => 'No hay dispositivos registrados';

  @override
  String get syncNeverSynced => 'Nunca sincronizado';

  @override
  String get syncChooseFolder => 'Elegir carpeta de sincronización';

  @override
  String get syncFolderNotConfigured =>
      'Elige una carpeta local para empezar a sincronizar este dispositivo.';

  @override
  String get syncPulling => 'Sincronizando…';

  @override
  String get syncDeviceUpToDate => 'Este dispositivo está actualizado.';

  @override
  String get syncItemsSkipped => 'No se pudieron sincronizar algunos elementos';

  @override
  String get syncSkippedItems => 'Elementos omitidos';

  @override
  String get syncFolderNotEmptyTitle => 'La carpeta no está vacía';

  @override
  String get syncFolderNotEmptyMessage =>
      'Esta carpeta ya contiene archivos. La sincronización no sobrescribirá nada que no haya creado ella misma; los archivos que entren en conflicto se conservarán y aparecerán como omitidos.';

  @override
  String get syncUnsupportedPlatform =>
      'La sincronización está disponible en la aplicación para Windows y macOS';

  @override
  String get versionHistory => 'Historial de versiones';

  @override
  String get noVersions => 'Aún no hay versiones';

  @override
  String get restoreVersion => 'Restaurar';

  @override
  String versionLabel(int number) {
    return 'Versión $number';
  }

  @override
  String get confirmRestoreVersion => '¿Restaurar esta versión?';

  @override
  String get versionRestored => 'Versión restaurada';

  @override
  String get latestVersion => 'Más reciente';

  @override
  String get close => 'Cerrar';

  @override
  String get errorNoConnection =>
      'No se pudo conectar con el servidor. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get errorServiceUnavailable =>
      'Esta función no está disponible temporalmente. Inténtalo más tarde.';

  @override
  String get errorRequestFailed => 'No se pudo completar la solicitud.';

  @override
  String get syncConnecting => 'Conectando…';

  @override
  String get syncDownloading => 'Descargando';

  @override
  String get syncScanning => 'Explorando carpeta';

  @override
  String get syncHashing => 'Comparando el contenido de los archivos';

  @override
  String get syncUploading => 'Subiendo';

  @override
  String get syncDeleting => 'Aplicando eliminaciones';

  @override
  String get syncDiscovering => 'Buscando elementos: aún no se conoce el total';

  @override
  String syncProgressCounts(int completed, int total, int remaining) {
    return '$completed / $total elementos completados · quedan $remaining';
  }

  @override
  String syncProgressFailures(int count) {
    return '$count elementos fallidos';
  }

  @override
  String syncTransferredBytes(
    String transferred,
    String total,
    String remaining,
  ) {
    return '$transferred / $total · quedan $remaining';
  }

  @override
  String syncKnownProgressCounts(int completed, int total, int remaining) {
    return 'Elementos conocidos: $completed / $total completados · quedan $remaining';
  }

  @override
  String get updateRetry => 'Reintentar actualización';

  @override
  String get updateRestarting =>
      'Finalizando la sincronización antes de reiniciar…';

  @override
  String get updateRestart => 'Reiniciar y actualizar';

  @override
  String updateDownloading(int percent) {
    return 'Descargando actualización: $percent%';
  }

  @override
  String updateReady(String version) {
    return 'La actualización $version está lista. Se instalará en el próximo inicio.';
  }

  @override
  String get updateFailed =>
      'La actualización automática falló. Puedes seguir usando zDrive e intentarlo de nuevo.';

  @override
  String get shareNotFoundTitle => 'Enlace no encontrado';

  @override
  String get shareNotFoundMessage =>
      'Este enlace para compartir no es válido, ha caducado o se ha eliminado.';

  @override
  String get sharePasswordProtectedTitle => 'Se requiere contraseña';

  @override
  String get sharePasswordProtectedMessage =>
      'Este enlace está protegido con contraseña, algo que aún no es compatible.';

  @override
  String get openZDrive => 'Abrir zDrive';

  @override
  String get download => 'Descargar';

  @override
  String shareAvailableUntil(Object date) {
    return 'Disponible hasta $date';
  }

  @override
  String get shareWhatIsZDrive => '¿Qué es zDrive?';

  @override
  String get shareFooterTagline => 'Protegido por zDrive';

  @override
  String get shareReplaceFile => 'Reemplazar archivo';

  @override
  String get shareDeleteConfirmMessage =>
      'Este elemento se moverá a la papelera del propietario.';

  @override
  String get shareOverwriteTitle => '¿Reemplazar el archivo existente?';

  @override
  String shareOverwriteMessage(Object name) {
    return 'Ya existe un archivo llamado \"$name\". Subirlo lo reemplazará con una nueva versión.';
  }

  @override
  String get shareReplaceConfirm => 'Reemplazar';

  @override
  String get shareErrorNotAllowed => 'Este enlace no permite esa acción.';

  @override
  String get shareErrorNameExists =>
      'Ya existe un archivo o carpeta con este nombre.';

  @override
  String get shareErrorQuotaExceeded =>
      'El almacenamiento del propietario está lleno.';

  @override
  String get shareErrorTooManyUploads =>
      'Todavía se están procesando demasiadas subidas. Inténtalo de nuevo en un momento.';

  @override
  String get tagline => 'Tus archivos, en todas partes.';

  @override
  String get authBenefitSync => 'Sincronización en todos los dispositivos';

  @override
  String get authBenefitShare => 'Comparte archivos y carpetas de forma segura';

  @override
  String get authBenefitSecure => 'Almacenamiento siempre cifrado';

  @override
  String get offlineCloudOnly => 'Solo en la nube';

  @override
  String get offlineDownloading => 'Descargando';

  @override
  String get offlineAvailable => 'Disponible en este dispositivo';

  @override
  String get offlineAlwaysKeep => 'Siempre conservado en este dispositivo';

  @override
  String get keepOnDevice => 'Conservar siempre en este dispositivo';

  @override
  String get freeUpSpace => 'Liberar espacio';

  @override
  String freeUpSkippedUnsynced(int count) {
    return '$count conservados en este dispositivo: cambios sin sincronizar';
  }
}
