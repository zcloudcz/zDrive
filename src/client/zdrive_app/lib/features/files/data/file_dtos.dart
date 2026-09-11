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
  // Null when no upload has ever completed for this node — but that is also
  // true while an upload into it is still running, from this device or
  // another, so it is only a necessary condition for reuse on a 409 from
  // createFile, not sufficient on its own. _createOrReuseNode
  // (file_repository_impl.dart) additionally requires the node's id to be in
  // this app instance's own _failedUploadNodeIds before treating it as an
  // orphan safe to reuse.
  final String? manifestHash;
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
    this.manifestHash,
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
  final String sasUploadUrl;

  const UploadSessionDto({
    required this.sessionId,
    required this.sasUploadUrl,
  });

  factory UploadSessionDto.fromJson(Map<String, dynamic> json) =>
      _$UploadSessionDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UploadSessionDtoToJson(this);
}

@JsonSerializable()
class UploadCompleteDto {
  final String blobPath;
  final String manifestHash;
  final int totalSize;

  const UploadCompleteDto({
    required this.blobPath,
    required this.manifestHash,
    required this.totalSize,
  });

  factory UploadCompleteDto.fromJson(Map<String, dynamic> json) =>
      _$UploadCompleteDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UploadCompleteDtoToJson(this);
}

/// The chunk manifest, fetched via `GET /storage/download/{fileId}/manifest`.
/// StorageService's `GetManifestQueryHandler` reads the raw
/// `ChunkManifest`/`ChunkInfo` value objects off blob storage (written
/// PascalCase by a bare `JsonSerializer.Serialize`, see
/// `AzureBlobStorageService.UploadManifestAsync`) and re-serves them through
/// the normal controller pipeline, which is camelCase like every other
/// endpoint — so, unlike the blob-stored manifest itself, this DTO needs no
/// `@JsonKey` overrides.
@JsonSerializable()
class ManifestDto {
  final int totalSize;
  final List<ManifestChunkDto> chunks;

  const ManifestDto({required this.totalSize, required this.chunks});

  factory ManifestDto.fromJson(Map<String, dynamic> json) =>
      _$ManifestDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ManifestDtoToJson(this);
}

@JsonSerializable()
class ManifestChunkDto {
  final String hash;
  final int index;

  const ManifestChunkDto({required this.hash, required this.index});

  factory ManifestChunkDto.fromJson(Map<String, dynamic> json) =>
      _$ManifestChunkDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ManifestChunkDtoToJson(this);
}
