import 'package:json_annotation/json_annotation.dart';

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
