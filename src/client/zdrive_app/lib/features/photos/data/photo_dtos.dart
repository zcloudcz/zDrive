import 'package:json_annotation/json_annotation.dart';

part 'photo_dtos.g.dart';

@JsonSerializable()
class PhotoDto {
  final String id;
  final String fileId;
  final String? takenAt;
  final double? lat;
  final double? lng;
  final String? cameraMake;
  final String? cameraModel;
  final int? width;
  final int? height;
  final String processingStatus;
  final List<String>? tags;

  const PhotoDto({
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
    this.tags,
  });

  factory PhotoDto.fromJson(Map<String, dynamic> json) => _$PhotoDtoFromJson(json);
  Map<String, dynamic> toJson() => _$PhotoDtoToJson(this);
}

@JsonSerializable()
class AlbumDto {
  final String id;
  final String name;
  final String type;
  final String? coverPhotoId;
  final int photoCount;
  final String createdAt;

  const AlbumDto({
    required this.id,
    required this.name,
    required this.type,
    this.coverPhotoId,
    this.photoCount = 0,
    required this.createdAt,
  });

  factory AlbumDto.fromJson(Map<String, dynamic> json) => _$AlbumDtoFromJson(json);
  Map<String, dynamic> toJson() => _$AlbumDtoToJson(this);
}

@JsonSerializable()
class MemoryDto {
  final String id;
  final String type;
  final String title;
  final String? dateFrom;
  final String? dateTo;
  final List<String> photoIds;
  final bool seen;

  const MemoryDto({
    required this.id,
    required this.type,
    required this.title,
    this.dateFrom,
    this.dateTo,
    this.photoIds = const [],
    this.seen = false,
  });

  factory MemoryDto.fromJson(Map<String, dynamic> json) => _$MemoryDtoFromJson(json);
  Map<String, dynamic> toJson() => _$MemoryDtoToJson(this);
}

@JsonSerializable()
class TimelineResultDto {
  final List<PhotoDto> photos;
  final int totalCount;

  const TimelineResultDto({required this.photos, required this.totalCount});

  factory TimelineResultDto.fromJson(Map<String, dynamic> json) => _$TimelineResultDtoFromJson(json);
  Map<String, dynamic> toJson() => _$TimelineResultDtoToJson(this);
}
