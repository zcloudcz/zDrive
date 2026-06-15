// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FileDto _$FileDtoFromJson(Map<String, dynamic> json) => FileDto(
  id: json['id'] as String,
  name: json['name'] as String,
  isFolder: json['isFolder'] as bool,
  sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
  mimeType: json['mimeType'] as String?,
  parentId: json['parentId'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  isDeleted: json['isDeleted'] as bool? ?? false,
);

Map<String, dynamic> _$FileDtoToJson(FileDto instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'isFolder': instance.isFolder,
  'sizeBytes': instance.sizeBytes,
  'mimeType': instance.mimeType,
  'parentId': instance.parentId,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'isDeleted': instance.isDeleted,
};

ShareDto _$ShareDtoFromJson(Map<String, dynamic> json) => ShareDto(
  id: json['id'] as String,
  fileId: json['fileId'] as String,
  permission: json['permission'] as String,
  linkToken: json['linkToken'] as String,
  expiresAt: json['expiresAt'] == null
      ? null
      : DateTime.parse(json['expiresAt'] as String),
);

Map<String, dynamic> _$ShareDtoToJson(ShareDto instance) => <String, dynamic>{
  'id': instance.id,
  'fileId': instance.fileId,
  'permission': instance.permission,
  'linkToken': instance.linkToken,
  'expiresAt': instance.expiresAt?.toIso8601String(),
};

PagedResultDto _$PagedResultDtoFromJson(Map<String, dynamic> json) =>
    PagedResultDto(
      items: json['items'] as List<dynamic>,
      totalCount: (json['totalCount'] as num).toInt(),
      page: (json['page'] as num).toInt(),
      pageSize: (json['pageSize'] as num).toInt(),
    );

Map<String, dynamic> _$PagedResultDtoToJson(PagedResultDto instance) =>
    <String, dynamic>{
      'items': instance.items,
      'totalCount': instance.totalCount,
      'page': instance.page,
      'pageSize': instance.pageSize,
    };

UploadSessionDto _$UploadSessionDtoFromJson(Map<String, dynamic> json) =>
    UploadSessionDto(
      sessionId: json['sessionId'] as String,
      sasUploadUrl: json['sasUploadUrl'] as String,
    );

Map<String, dynamic> _$UploadSessionDtoToJson(UploadSessionDto instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
      'sasUploadUrl': instance.sasUploadUrl,
    };

UploadCompleteDto _$UploadCompleteDtoFromJson(Map<String, dynamic> json) =>
    UploadCompleteDto(
      blobPath: json['blobPath'] as String,
      manifestHash: json['manifestHash'] as String,
      totalSize: (json['totalSize'] as num).toInt(),
    );

Map<String, dynamic> _$UploadCompleteDtoToJson(UploadCompleteDto instance) =>
    <String, dynamic>{
      'blobPath': instance.blobPath,
      'manifestHash': instance.manifestHash,
      'totalSize': instance.totalSize,
    };

DownloadUrlDto _$DownloadUrlDtoFromJson(Map<String, dynamic> json) =>
    DownloadUrlDto(
      sasUrl: json['sasUrl'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
    );

Map<String, dynamic> _$DownloadUrlDtoToJson(DownloadUrlDto instance) =>
    <String, dynamic>{
      'sasUrl': instance.sasUrl,
      'expiresAt': instance.expiresAt.toIso8601String(),
    };
