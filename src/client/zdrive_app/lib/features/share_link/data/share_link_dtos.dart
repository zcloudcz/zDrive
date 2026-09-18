import 'package:json_annotation/json_annotation.dart';

import '../../files/data/file_dtos.dart';

part 'share_link_dtos.g.dart';

/// Response of `POST /shares/link/{token}/download-grant` — a short-lived
/// grant that authorizes exactly one anonymous file download (see
/// `ShareLinkDataSource.downloadFile`).
@JsonSerializable()
class DownloadGrantDto {
  final String grant;
  final DateTime expiresAt;
  final String fileId;
  final String fileName;
  final int sizeBytes;
  final String? manifestHash;

  const DownloadGrantDto({
    required this.grant,
    required this.expiresAt,
    required this.fileId,
    required this.fileName,
    required this.sizeBytes,
    this.manifestHash,
  });

  factory DownloadGrantDto.fromJson(Map<String, dynamic> json) =>
      _$DownloadGrantDtoFromJson(json);

  Map<String, dynamic> toJson() => _$DownloadGrantDtoToJson(this);
}

/// Owner's storage numbers, present in [ShareInfoDto] only for a link that
/// allows Write — a Read link must not learn how full the owner's account
/// is (security review, see the share-link write API design doc).
@JsonSerializable()
class ShareQuotaDto {
  final int limitBytes;
  final int usedBytes;

  const ShareQuotaDto({required this.limitBytes, required this.usedBytes});

  factory ShareQuotaDto.fromJson(Map<String, dynamic> json) =>
      _$ShareQuotaDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ShareQuotaDtoToJson(this);
}

/// Response of `GET /shares/link/{token}/info` — what this link is allowed
/// to do, fetched alongside the existing metadata load in
/// `ShareLinkCubit.load`. Absent on an older backend (404), in which case
/// the cubit falls back to read-only rather than breaking the page.
@JsonSerializable()
class ShareInfoDto {
  final String permission;
  final bool allowDelete;
  final DateTime? expiresAt;
  final FileDto root;
  final ShareQuotaDto? quota;

  const ShareInfoDto({
    required this.permission,
    required this.allowDelete,
    this.expiresAt,
    required this.root,
    this.quota,
  });

  // "Admin" on a link behaves as "Write" (see the share-link write API design doc).
  bool get canWrite => permission == 'Write' || permission == 'Admin';

  factory ShareInfoDto.fromJson(Map<String, dynamic> json) =>
      _$ShareInfoDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ShareInfoDtoToJson(this);
}

/// Response of `POST /shares/link/{token}/upload-grant` — authorizes one
/// chunked upload session against StorageService's anonymous shared-upload
/// endpoints (see `ShareLinkDataSource.uploadFile`).
@JsonSerializable()
class ShareUploadGrantDto {
  final String grant;
  final DateTime expiresAt;
  final String fileId;
  final String fileName;
  final int maxBytes;

  const ShareUploadGrantDto({
    required this.grant,
    required this.expiresAt,
    required this.fileId,
    required this.fileName,
    required this.maxBytes,
  });

  factory ShareUploadGrantDto.fromJson(Map<String, dynamic> json) =>
      _$ShareUploadGrantDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ShareUploadGrantDtoToJson(this);
}

/// Response of `POST /storage/shared/upload/{sessionId}/complete` — the
/// receipt is StorageService's proof to FileService (via
/// `ShareLinkDataSource.recordFileVersion`) that these exact bytes were
/// written for the granted file.
@JsonSerializable()
class SharedUploadCompleteDto {
  final String manifestHash;
  final int totalSize;
  final String receipt;

  const SharedUploadCompleteDto({
    required this.manifestHash,
    required this.totalSize,
    required this.receipt,
  });

  factory SharedUploadCompleteDto.fromJson(Map<String, dynamic> json) =>
      _$SharedUploadCompleteDtoFromJson(json);

  Map<String, dynamic> toJson() => _$SharedUploadCompleteDtoToJson(this);
}
