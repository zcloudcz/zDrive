import 'package:json_annotation/json_annotation.dart';

part 'file_dtos.g.dart';

@JsonSerializable()
class FileDto {
  final String id;
  final String name;
  final bool isFolder;
  final int? sizeBytes;
  final String? mimeType;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const FileDto({
    required this.id,
    required this.name,
    required this.isFolder,
    this.sizeBytes,
    this.mimeType,
    this.parentId,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  factory FileDto.fromJson(Map<String, dynamic> json) =>
      _$FileDtoFromJson(json);

  Map<String, dynamic> toJson() => _$FileDtoToJson(this);
}

@JsonSerializable()
class ShareDto {
  final String id;
  final String fileId;
  final String permission;
  final String linkToken;
  final DateTime? expiresAt;

  const ShareDto({
    required this.id,
    required this.fileId,
    required this.permission,
    required this.linkToken,
    this.expiresAt,
  });

  factory ShareDto.fromJson(Map<String, dynamic> json) =>
      _$ShareDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ShareDtoToJson(this);
}

@JsonSerializable()
class PagedResultDto {
  final List<dynamic> items;
  final int totalCount;
  final int page;
  final int pageSize;

  const PagedResultDto({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  factory PagedResultDto.fromJson(Map<String, dynamic> json) =>
      _$PagedResultDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PagedResultDtoToJson(this);
}

@JsonSerializable()
class UploadSessionDto {
  final String sessionId;
  final String fileId;
  final int totalChunks;

  const UploadSessionDto({
    required this.sessionId,
    required this.fileId,
    required this.totalChunks,
  });

  factory UploadSessionDto.fromJson(Map<String, dynamic> json) =>
      _$UploadSessionDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UploadSessionDtoToJson(this);
}

@JsonSerializable()
class UploadCompleteDto {
  final String fileId;
  final String name;
  final int sizeBytes;

  const UploadCompleteDto({
    required this.fileId,
    required this.name,
    required this.sizeBytes,
  });

  factory UploadCompleteDto.fromJson(Map<String, dynamic> json) =>
      _$UploadCompleteDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UploadCompleteDtoToJson(this);
}
