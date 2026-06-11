import 'package:equatable/equatable.dart';

/// One recorded version of a file's content. `blobVersionId` is the manifest
/// hash under which StorageService keeps the immutable snapshot.
class FileVersion extends Equatable {
  final String id;
  final String fileId;
  final int versionNumber;
  final String blobVersionId;
  final int sizeBytes;
  final String? manifestHash;
  final String? comment;
  final DateTime createdAt;

  const FileVersion({
    required this.id,
    required this.fileId,
    required this.versionNumber,
    required this.blobVersionId,
    required this.sizeBytes,
    this.manifestHash,
    this.comment,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, fileId, versionNumber];
}
