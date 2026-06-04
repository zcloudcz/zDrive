// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PhotoDto _$PhotoDtoFromJson(Map<String, dynamic> json) => PhotoDto(
  id: json['id'] as String,
  fileId: json['fileId'] as String,
  takenAt: json['takenAt'] as String?,
  lat: (json['lat'] as num?)?.toDouble(),
  lng: (json['lng'] as num?)?.toDouble(),
  cameraMake: json['cameraMake'] as String?,
  cameraModel: json['cameraModel'] as String?,
  width: (json['width'] as num?)?.toInt(),
  height: (json['height'] as num?)?.toInt(),
  processingStatus: json['processingStatus'] as String? ?? 'pending',
  tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList(),
);

Map<String, dynamic> _$PhotoDtoToJson(PhotoDto instance) => <String, dynamic>{
  'id': instance.id,
  'fileId': instance.fileId,
  'takenAt': instance.takenAt,
  'lat': instance.lat,
  'lng': instance.lng,
  'cameraMake': instance.cameraMake,
  'cameraModel': instance.cameraModel,
  'width': instance.width,
  'height': instance.height,
  'processingStatus': instance.processingStatus,
  'tags': instance.tags,
};

AlbumDto _$AlbumDtoFromJson(Map<String, dynamic> json) => AlbumDto(
  id: json['id'] as String,
  name: json['name'] as String,
  type: json['type'] as String,
  coverPhotoId: json['coverPhotoId'] as String?,
  photoCount: (json['photoCount'] as num?)?.toInt() ?? 0,
  createdAt: json['createdAt'] as String,
);

Map<String, dynamic> _$AlbumDtoToJson(AlbumDto instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'type': instance.type,
  'coverPhotoId': instance.coverPhotoId,
  'photoCount': instance.photoCount,
  'createdAt': instance.createdAt,
};

MemoryDto _$MemoryDtoFromJson(Map<String, dynamic> json) => MemoryDto(
  id: json['id'] as String,
  type: json['type'] as String,
  title: json['title'] as String,
  dateFrom: json['dateFrom'] as String?,
  dateTo: json['dateTo'] as String?,
  photoIds:
      (json['photoIds'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  seen: json['seen'] as bool? ?? false,
);

Map<String, dynamic> _$MemoryDtoToJson(MemoryDto instance) => <String, dynamic>{
  'id': instance.id,
  'type': instance.type,
  'title': instance.title,
  'dateFrom': instance.dateFrom,
  'dateTo': instance.dateTo,
  'photoIds': instance.photoIds,
  'seen': instance.seen,
};

TimelineResultDto _$TimelineResultDtoFromJson(Map<String, dynamic> json) =>
    TimelineResultDto(
      photos: (json['photos'] as List<dynamic>)
          .map((e) => PhotoDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCount: (json['totalCount'] as num).toInt(),
    );

Map<String, dynamic> _$TimelineResultDtoToJson(TimelineResultDto instance) =>
    <String, dynamic>{
      'photos': instance.photos,
      'totalCount': instance.totalCount,
    };
