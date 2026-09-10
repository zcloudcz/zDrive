import '../domain/file_repository.dart';
import 'file_remote_data_source.dart';
import 'file_upload_data_source.dart';

/// Web has no way to let the user pick a local directory tree (no
/// `dart:io`, and browsers do not expose a folder picker file_picker could
/// wrap), so folder upload does not exist here. file_browser_page.dart
/// hides the "upload folder" action on web; this only exists so the
/// conditional export in folder_uploader.dart has a web-safe counterpart
/// with the same signature as folder_uploader_io.dart's.
Future<void> uploadFolder(
  FileRepository repository,
  FileUploadDataSource uploadDataSource,
  FileRemoteDataSource remoteDataSource,
  String? parentId,
) async {
  throw UnsupportedError('Folder upload is not supported on web.');
}
