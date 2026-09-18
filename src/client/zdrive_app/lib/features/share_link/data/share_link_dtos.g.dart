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
