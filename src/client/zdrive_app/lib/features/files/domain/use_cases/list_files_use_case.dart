import 'package:injectable/injectable.dart';

import '../file_item.dart';
import '../file_repository.dart';

@lazySingleton
class ListFilesUseCase {
  final FileRepository _repository;

  ListFilesUseCase(this._repository);

  Future<PagedResult<FileItem>> call(
    String? folderId, {
    int page = 1,
    int pageSize = 50,
  }) {
    return _repository.listChildren(folderId, page: page, pageSize: pageSize);
  }
}
