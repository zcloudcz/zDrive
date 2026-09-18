// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'share_link_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DownloadGrantDto _$DownloadGrantDtoFromJson(Map<String, dynamic> json) =>
    DownloadGrantDto(
      grant: json['grant'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      fileId: json['fileId'] as String,
      fileName: json['fileName'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      manifestHash: json['manifestHash'] as String?,
    );

Map<String, dynamic> _$DownloadGrantDtoToJson(DownloadGrantDto instance) =>
    <String, dynamic>{
      'grant': instance.grant,
      'expiresAt': instance.expiresAt.toIso8601String(),
      'fileId': instance.fileId,
      'fileName': instance.fileName,
      'sizeBytes': instance.sizeBytes,
      'manifestHash': instance.manifestHash,
    };

ShareQuotaDto _$ShareQuotaDtoFromJson(Map<String, dynamic> json) =>
    ShareQuotaDto(
      limitBytes: (json['limitBytes'] as num).toInt(),
      usedBytes: (json['usedBytes'] as num).toInt(),
    );

Map<String, dynamic> _$ShareQuotaDtoToJson(ShareQuotaDto instance) =>
    <String, dynamic>{
      'limitBytes': instance.limitBytes,
      'usedBytes': instance.usedBytes,
    };

ShareInfoDto _$ShareInfoDtoFromJson(Map<String, dynamic> json) => ShareInfoDto(
  permission: json['permission'] as String,
  allowDelete: json['allowDelete'] as bool,
  expiresAt: json['expiresAt'] == null
      ? null
      : DateTime.parse(json['expiresAt'] as String),
  root: FileDto.fromJson(json['root'] as Map<String, dynamic>),
  quota: json['quota'] == null
      ? null
      : ShareQuotaDto.fromJson(json['quota'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ShareInfoDtoToJson(ShareInfoDto instance) =>
    <String, dynamic>{
      'permission': instance.permission,
      'allowDelete': instance.allowDelete,
      'expiresAt': instance.expiresAt?.toIso8601String(),
      'root': instance.root,
      'quota': instance.quota,
    };

ShareUploadGrantDto _$ShareUploadGrantDtoFromJson(Map<String, dynamic> json) =>
    ShareUploadGrantDto(
      grant: json['grant'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      fileId: json['fileId'] as String,
      fileName: json['fileName'] as String,
      maxBytes: (json['maxBytes'] as num).toInt(),
    );

Map<String, dynamic> _$ShareUploadGrantDtoToJson(
  ShareUploadGrantDto instance,
) => <String, dynamic>{
  'grant': instance.grant,
  'expiresAt': instance.expiresAt.toIso8601String(),
  'fileId': instance.fileId,
  'fileName': instance.fileName,
  'maxBytes': instance.maxBytes,
};

SharedUploadCompleteDto _$SharedUploadCompleteDtoFromJson(
  Map<String, dynamic> json,
) => SharedUploadCompleteDto(
  manifestHash: json['manifestHash'] as String,
  totalSize: (json['totalSize'] as num).toInt(),
  receipt: json['receipt'] as String,
);

Map<String, dynamic> _$SharedUploadCompleteDtoToJson(
  SharedUploadCompleteDto instance,
) => <String, dynamic>{
  'manifestHash': instance.manifestHash,
  'totalSize': instance.totalSize,
  'receipt': instance.receipt,
};
