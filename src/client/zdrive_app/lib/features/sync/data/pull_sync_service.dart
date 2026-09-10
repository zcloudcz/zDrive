import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../files/domain/file_item.dart';
import '../../files/domain/file_repository.dart';
import '../domain/sync_mirror_entry.dart';
import '../domain/sync_mirror_repository.dart';
import 'device_registration_service.dart';
import 'sync_remote_data_source.dart';

/// The server returns at most this many events per pull
/// (`PullChangesQueryHandler.MaxEventsPerPull`) — a full page means there may
/// be more, so [pullOnce] keeps polling until a short page tells it the tail
/// is reached.
const _maxEventsPerPage = 500;

/// Thrown when [PullSyncService.pullOnce] is called with no designated
/// folder configured yet.
class NoSyncFolderConfiguredException implements Exception {
  const NoSyncFolderConfiguredException();
}

/// Applies remote sync events into the designated local folder.
///
/// Ordering guarantee: events are applied one at a time, strictly in the
/// order the server returned them (already ascending by id). The mirror
/// cursor for this device only advances to an event's id *after* that
/// event's disk write and mirror-row update both complete — so if the app
/// dies mid-[pullOnce], the persisted cursor never points past work that
/// did not land. The event that was in flight (and everything after it)
/// will be re-delivered on the next pull; re-applying it is safe because
/// writing a file or removing one that is already gone are both idempotent.
@lazySingleton
class PullSyncService {
  final SyncRemoteDataSource _syncDataSource;
  final DeviceRegistrationService _deviceRegistration;
  final SyncMirrorRepository _mirror;
  final FileRepository _fileRepository;

  PullSyncService(
    this._syncDataSource,
    this._deviceRegistration,
    this._mirror,
    this._fileRepository,
  );

  /// Pulls and applies everything pending for this device, draining
  /// multiple pages if the server reports more than fit in one. Returns the
  /// number of events applied.
  Future<int> pullOnce(String syncFolderPath) async {
    final deviceId = await _deviceRegistration.ensureRegistered();

    var applied = 0;
    while (true) {
      final cursor = await _mirror.getCursor(deviceId);
      final page = await _syncDataSource.pull(deviceId, cursor);
      final events = (page['events'] as List).cast<Map<String, dynamic>>();
      if (events.isEmpty) break;

      for (final event in events) {
        // No try/catch here: an exception must propagate out of pullOnce
        // immediately, leaving the cursor at the previous event's id — that
        // is the ordering guarantee. Wrapping this loop would let a failed
        // apply be silently skipped and the cursor advance past it anyway.
        await _applyEvent(event, deviceId, syncFolderPath);
        applied++;
      }

      if (events.length < _maxEventsPerPage) break;
    }
    return applied;
  }

  Future<void> _applyEvent(
    Map<String, dynamic> event,
    String deviceId,
    String syncFolderPath,
  ) async {
    final eventId = (event['id'] as num).toInt();
    final fileId = event['fileId'] as String;
    final eventType = event['eventType'] as String;

    if (eventType == 'Delete') {
      await _applyDelete(fileId);
    } else {
      // Create/Update/Move/Rename are all handled the same way: fetch the
      // file's current state and reconcile the local copy against it. This
      // also covers move/rename without a separate code path — the mirror
      // lookup below finds the entry's previous local path (if any) and
      // relocates it when the resolved path has changed.
      await _applyUpsert(fileId, syncFolderPath);
    }

    await _mirror.setCursor(deviceId, eventId);
  }

  Future<void> _applyDelete(String fileId) async {
    final entry = await _mirror.getByServerId(fileId);
    if (entry == null) return; // Never pulled locally — nothing to remove.

    await _deleteLocal(entry.localPath, entry.isFolder);
    await _mirror.deleteByServerId(fileId);
  }

  Future<void> _applyUpsert(String fileId, String syncFolderPath) async {
    final FileItem remote;
    try {
      remote = await _fileRepository.getFile(fileId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // The file is gone by the time we looked it up (e.g. a Create
        // immediately followed by a Delete) — reconcile as a delete instead
        // of failing the whole pull over a stale event.
        await _applyDelete(fileId);
        return;
      }
      rethrow;
    }

    final previous = await _mirror.getByServerId(fileId);
    final dirPath = await _resolveLocalDirPath(remote.parentId, syncFolderPath);
    final localPath = p.join(dirPath, remote.name);

    String? contentHash;
    if (remote.isFolder) {
      await Directory(localPath).create(recursive: true);
    } else {
      final bytes = await _fileRepository.downloadFile(fileId);
      await File(localPath).parent.create(recursive: true);
      await File(localPath).writeAsBytes(bytes, flush: true);
      contentHash = sha256.convert(bytes).toString();
    }

    await _mirror.upsert(SyncMirrorEntry(
      serverId: remote.id,
      localPath: localPath,
      isFolder: remote.isFolder,
      sizeBytes: remote.sizeBytes,
      contentHash: contentHash,
      updatedAt: remote.updatedAt,
      syncedAt: DateTime.now(),
    ));

    // Moved or renamed: the old path is stale now that the new one has been
    // written, so clean it up.
    if (previous != null && previous.localPath != localPath) {
      await _deleteLocal(previous.localPath, previous.isFolder);
    }
  }

  /// Resolves [folderId]'s local directory path under [syncFolderPath],
  /// walking the parentId chain as needed and caching each folder it visits
  /// as a mirror row — so later files under the same folder resolve from
  /// the mirror instead of re-walking the chain.
  Future<String> _resolveLocalDirPath(String? folderId, String syncFolderPath) async {
    if (folderId == null) return syncFolderPath;

    final cached = await _mirror.getByServerId(folderId);
    if (cached != null) return cached.localPath;

    final folder = await _fileRepository.getFile(folderId);
    final parentPath = await _resolveLocalDirPath(folder.parentId, syncFolderPath);
    final dirPath = p.join(parentPath, folder.name);

    await Directory(dirPath).create(recursive: true);
    await _mirror.upsert(SyncMirrorEntry(
      serverId: folder.id,
      localPath: dirPath,
      isFolder: true,
      updatedAt: folder.updatedAt,
      syncedAt: DateTime.now(),
    ));

    return dirPath;
  }

  Future<void> _deleteLocal(String path, bool isFolder) async {
    try {
      if (isFolder) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
    } on PathNotFoundException {
      // Already gone locally — deleting is idempotent, not an error.
    }
  }
}
