import 'package:equatable/equatable.dart';

class Photo extends Equatable {
  final String id;
  final String fileId;
  final DateTime? takenAt;
  final double? lat;
  final double? lng;
  final String? cameraMake;
  final String? cameraModel;
  final int? width;
  final int? height;
  final String processingStatus;
  final List<String> tags;

  const Photo({
    required this.id,
    required this.fileId,
    this.takenAt,
    this.lat,
    this.lng,
    this.cameraMake,
    this.cameraModel,
    this.width,
    this.height,
    this.processingStatus = 'pending',
    this.tags = const [],
  });

  @override
  List<Object?> get props => [id, fileId, takenAt];
}

class Album extends Equatable {
  final String id;
  final String name;
  final String type;
  final String? coverPhotoId;
  final int photoCount;
  final DateTime createdAt;

  const Album({
    required this.id,
    required this.name,
    required this.type,
    this.coverPhotoId,
    this.photoCount = 0,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, name];
}

class Memory extends Equatable {
  final String id;
  final String type;
  final String title;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final List<String> photoIds;
  final bool seen;

  const Memory({
    required this.id,
    required this.type,
    required this.title,
    this.dateFrom,
    this.dateTo,
    this.photoIds = const [],
    this.seen = false,
  });

  @override
  List<Object?> get props => [id, type, title];
}
