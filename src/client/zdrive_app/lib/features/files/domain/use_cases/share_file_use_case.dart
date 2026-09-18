import 'package:injectable/injectable.dart';

import '../file_item.dart';
import '../file_repository.dart';

@lazySingleton
class ShareFileUseCase {
  final FileRepository _repository;

  ShareFileUseCase(this._repository);

  Future<ShareInfo> call(
    String fileId,
    SharePermission permission,
    DateTime? expiresAt, {
    bool allowDelete = false,
  }) {
    return _repository.createShare(fileId, permission, expiresAt,
        allowDelete: allowDelete);
  }
}
