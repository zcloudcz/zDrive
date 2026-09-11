import 'dart:developer';

import 'package:injectable/injectable.dart';

import '../domain/sync_mirror_entry.dart';
import '../domain/sync_mirror_repository.dart';
import 'device_registration_service.dart';
import 'sync_remote_data_source.dart';

export '../domain/sync_mirror_entry.dart' show SyncChangeType;

/// The entry point the files feature calls once one of its own local
/// operations (upload, rename, move, delete) has succeeded, so other
/// devices learn about it on their next pull. This does not touch local
/// disk or the mirror — it only reports to the server what already
/// happened; [PullSyncService] is what applies changes on the receiving
/// end.
///
/// Reports go through the same persistent outbox [LocalChangeScanner] writes
/// to (PR #14 review round 3): a change is durable the moment [reportChange]
/// enqueues it, so a failed send here is never lost — it just waits in
/// `sync_outbox` for the next [drainOutbox] call (the next [reportChange],
/// or the next sync cycle via [SyncCoordinator]).
@lazySingleton
class PushSyncService {
  final SyncRemoteDataSource _syncDataSource;
  final DeviceRegistrationService _deviceRegistration;
  final SyncMirrorRepository _mirror;

  PushSyncService(this._syncDataSource, this._deviceRegistration, this._mirror);

  /// Enqueues one local change for [fileId] and immediately tries to send
  /// it. A send failure is swallowed here (logged, not thrown) — the item
  /// stays in the outbox and the next [drainOutbox] call picks it up, so
  /// the caller (a local file operation that already succeeded) never fails
  /// just because SyncService happened to be unreachable at that instant.
  Future<void> reportChange(String fileId, SyncChangeType type) async {
    // Enqueueing must work offline — [localDeviceId] is a local lookup, no
    // network call, unlike ensureRegistered (PR #14 review round 4). A
    // `null` id (no device registered yet) reads as cursor 0, the honest
    // value for a device that has never pulled anything.
    final deviceId = await _deviceRegistration.localDeviceId();
    // The pull cursor this device had already applied at the time of the
    // change — sent as baseCursor so the server can tell "I pushed after
    // seeing everything up to here" from a push based on stale knowledge
    // (see SyncRemoteDataSource.push's doc comment).
    final baseCursor = deviceId == null ? 0 : await _mirror.getCursor(deviceId);
    await _mirror.commit(enqueue: [
      OutboxItem(fileId: fileId, type: type, baseCursor: baseCursor, createdAt: DateTime.now()),
    ]);
    try {
      await drainOutbox();
    } catch (e, st) {
      log('drain after reportChange($fileId, $type) failed, item stays queued',
          error: e, stackTrace: st, name: 'PushSyncService');
    }
  }

  /// Sends the oldest owed reports, in order, each with the [OutboxItem
  /// .baseCursor] it was enqueued with. Stops at the first failure — leaving
  /// it and everything after it queued for the next call — rather than
  /// reordering around it, since a later report for the same file depends
  /// on the server having seen this one first. Returns how many were sent.
  Future<int> drainOutbox() async {
    final deviceId = await _deviceRegistration.ensureRegistered();
    var sent = 0;
    for (final item in await _mirror.peekOutbox()) {
      try {
        await _syncDataSource.push(
          deviceId,
          [
            {'fileId': item.fileId, 'eventType': item.type.index, 'metadata': null},
          ],
          baseCursor: item.baseCursor,
        );
      } catch (e, st) {
        log('drainOutbox stopped: SyncService unreachable, ${item.id} and everything after it stay queued',
            error: e, stackTrace: st, name: 'PushSyncService');
        return sent;
      }
      await _mirror.removeOutbox(item.id!);
      sent++;
    }
    return sent;
  }

  /// How many reports are still owed — used by [SyncCoordinator] to surface
  /// the queue length in [SyncRunResult.queued].
  Future<int> outboxCount() => _mirror.outboxCount();
}
