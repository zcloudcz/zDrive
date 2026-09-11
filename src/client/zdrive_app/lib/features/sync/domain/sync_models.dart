import 'package:equatable/equatable.dart';

class SyncDevice extends Equatable {
  final String id;
  final String name;
  final String platform;
  final DateTime? lastSyncAt;

  const SyncDevice({required this.id, required this.name, required this.platform, this.lastSyncAt});

  factory SyncDevice.fromJson(Map<String, dynamic> json) => SyncDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        platform: json['platform'] as String,
        lastSyncAt: json['lastSyncAt'] != null
            ? DateTime.tryParse(json['lastSyncAt'] as String)
            : null,
      );

  @override
  List<Object?> get props => [id, name, platform];
}
