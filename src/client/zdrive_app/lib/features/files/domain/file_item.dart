import 'package:equatable/equatable.dart';

class FileItem extends Equatable {
  final String id;
  final String name;
  final bool isFolder;
  final int? sizeBytes;
  final String? mimeType;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;
  final bool isContentReady;

  const FileItem({
    required this.id,
    required this.name,
    required this.isFolder,
    this.sizeBytes,
    this.mimeType,
    this.parentId,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.isContentReady = true,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        isFolder,
        sizeBytes,
        mimeType,
        parentId,
        createdAt,
        updatedAt,
        isDeleted,
        isContentReady,
      ];
}

class ShareInfo extends Equatable {
  final String id;
  final String fileId;
  final SharePermission permission;
  final String linkToken;
  final DateTime? expiresAt;
  final bool allowDelete;

  const ShareInfo({
    required this.id,
    required this.fileId,
    required this.permission,
    required this.linkToken,
    this.expiresAt,
    this.allowDelete = false,
  });

  @override
  List<Object?> get props =>
      [id, fileId, permission, linkToken, expiresAt, allowDelete];
}

enum SharePermission { read, write }

class PagedResult<T> extends Equatable {
  final List<T> items;
  final int totalCount;
  final int page;
  final int pageSize;

  const PagedResult({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  bool get hasMore => page * pageSize < totalCount;

  @override
  List<Object?> get props => [items, totalCount, page, pageSize];
}
