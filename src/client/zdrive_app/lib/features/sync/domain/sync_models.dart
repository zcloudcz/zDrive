import 'package:equatable/equatable.dart';

class SyncDevice extends Equatable {
  final String id;
  final String name;
  final String platform;
  final DateTime? lastSyncAt;

  const SyncDevice({required this.id, required this.name, required this.platform, this.lastSyncAt});

  @override
  List<Object?> get props => [id, name, platform];
}

class SyncConflict extends Equatable {
  final String id;
  final String fileId;
  final String status;
  final DateTime createdAt;

  const SyncConflict({required this.id, required this.fileId, required this.status, required this.createdAt});

  @override
  List<Object?> get props => [id, fileId, status];
}
