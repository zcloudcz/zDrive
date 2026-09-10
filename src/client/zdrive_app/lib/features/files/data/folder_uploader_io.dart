import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';

import '../domain/file_item.dart';
import '../domain/file_repository.dart';
import 'file_remote_data_source.dart';
import 'file_upload_data_source.dart';

/// Lets the user pick a local directory, then mirrors it into zDrive under
/// [parentId]. See [mirrorDirectory] for the traversal itself.
Future<void> uploadFolder(
  FileRepository repository,
  FileUploadDataSource uploadDataSource,
  FileRemoteDataSource remoteDataSource,
  String? parentId,
) async {
  final rootPath = await FilePicker.platform.getDirectoryPath();
  if (rootPath == null) return; // User cancelled the picker.
  await mirrorDirectory(
    repository,
    uploadDataSource,
    remoteDataSource,
    Directory(rootPath),
    parentId,
  );
}

/// Recursively mirrors [dir] into the remote folder [remoteParentId],
/// following `ZDrive.BackupCli/Backup/BackupRunner.cs`'s traversal: list the
/// remote folder's existing children first, create a remote folder only for
/// a local subdirectory that doesn't already have one, and skip uploading a
/// file whose remote chunk manifest already matches its local content
/// exactly (see [_matchesRemote]) — otherwise upload it.
///
/// One disclosed difference from BackupRunner: that CLI also repairs a file
/// whose manifest matches but has no FileService version row (content
/// finished uploading but the process died before recording the version) —
/// a crash-recovery case specific to a resumable CLI backup. This
/// interactive upload does not carry that repair step.
Future<void> mirrorDirectory(
  FileRepository repository,
  FileUploadDataSource uploadDataSource,
  FileRemoteDataSource remoteDataSource,
  Directory dir,
  String? remoteParentId,
) async {
  final existing = await _listExistingByName(repository, remoteParentId);

  final entries = dir.listSync()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final entry in entries) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final match = existing[name];

    if (entry is Directory) {
      final folderId = match != null && match.isFolder
          ? match.id
          : (await repository.createFolder(remoteParentId, name)).id;
      await mirrorDirectory(
        repository,
        uploadDataSource,
        remoteDataSource,
        entry,
        folderId,
      );
    } else if (entry is File) {
      await _uploadFileIfNeeded(
        repository,
        uploadDataSource,
        remoteDataSource,
        entry,
        name,
        remoteParentId,
        match,
      );
    }
  }
}

Future<void> _uploadFileIfNeeded(
  FileRepository repository,
  FileUploadDataSource uploadDataSource,
  FileRemoteDataSource remoteDataSource,
  File file,
  String name,
  String? remoteParentId,
  FileItem? existing,
) async {
  final size = await file.length();

  if (existing != null && !existing.isFolder) {
    if (await _matchesRemote(uploadDataSource, existing.id, file, size)) {
      return; // Unchanged — already uploaded correctly.
    }

    // Changed since a previous run: re-upload into the same node as a new
    // version. FileService rejects a second createFile() with this name in
    // this folder as a duplicate, so this has to go through the same
    // fileId, not repository.uploadFile (which always creates a fresh node).
    final complete = await uploadDataSource.uploadFile(
      existing.id,
      name,
      file.openRead(),
      size,
    );
    await remoteDataSource.createFileVersion(
      existing.id,
      blobVersionId: complete.manifestHash,
      sizeBytes: complete.totalSize,
      manifestHash: complete.manifestHash,
    );
    return;
  }

  await repository.uploadFile(remoteParentId, name, file.openRead(), size, null);
}

/// Whether [file]'s content already matches what's stored remotely for
/// [fileId] — same total size, same chunk count, same hash at every index
/// (mirrors `BackupRunner.Matches()`). A file with no manifest yet (never
/// finished uploading) reports false, so it gets (re-)uploaded.
Future<bool> _matchesRemote(
  FileUploadDataSource uploadDataSource,
  String fileId,
  File file,
  int localSize,
) async {
  final manifest = await uploadDataSource.tryGetManifest(fileId);
  if (manifest == null || manifest.totalSize != localSize) return false;

  final localHashes = <int, String>{};
  var index = 0;
  await for (final chunk in FileUploadDataSource.splitIntoChunks(file.openRead())) {
    localHashes[index] = sha256.convert(chunk).toString();
    index++;
  }
  if (localHashes.length != manifest.chunks.length) return false;

  for (final chunk in manifest.chunks) {
    if (localHashes[chunk.index] != chunk.hash) return false;
  }
  return true;
}

/// All of [remoteParentId]'s existing children, keyed by name — paginated
/// the same way BackupRunner's ListChildrenAsync is, since a folder can hold
/// more than one page.
Future<Map<String, FileItem>> _listExistingByName(
  FileRepository repository,
  String? remoteParentId,
) async {
  final byName = <String, FileItem>{};
  var page = 1;
  const pageSize = 200;
  while (true) {
    final result = await repository.listChildren(
      remoteParentId,
      page: page,
      pageSize: pageSize,
    );
    for (final item in result.items) {
      byName[item.name] = item;
    }
    if (byName.length >= result.totalCount || result.items.isEmpty) {
      return byName;
    }
    page++;
  }
}
