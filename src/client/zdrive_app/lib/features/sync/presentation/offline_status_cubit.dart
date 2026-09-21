import 'package:flutter_bloc/flutter_bloc.dart';

import '../../files/domain/file_item.dart';
import '../domain/sync_mirror_entry.dart';
import '../domain/sync_mirror_repository.dart';

/// Per-item "on this device?" state for the file browser's current listing
/// (desktop only — provided only where [SyncBloc] is). One batched mirror
/// lookup per listing, never one per row.
class OfflineStatusCubit extends Cubit<Map<String, OfflineStatus>> {
  final SyncMirrorRepository _mirror;

  List<String> _ids = const [];
  String? _parentId;

  // Latest call wins: a slow lookup for a folder the user already left must
  // not overwrite the state of the folder they are looking at now.
  int _generation = 0;

  OfflineStatusCubit(this._mirror) : super(const {});

  Future<void> load(List<FileItem> items, {String? parentId}) {
    _ids = [for (final item in items) item.id];
    _parentId = parentId;
    return refresh();
  }

  /// Re-reads the current listing, e.g. after a download finished.
  Future<void> refresh() async {
    final generation = ++_generation;
    final statuses = await _mirror.getOfflineStatuses(_ids, parentId: _parentId);
    if (generation == _generation && !isClosed) emit(statuses);
  }
}
