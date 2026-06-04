import 'package:injectable/injectable.dart';

import '../file_item.dart';
import '../file_repository.dart';

@lazySingleton
class SearchFilesUseCase {
  final FileRepository _repository;

  SearchFilesUseCase(this._repository);

  Future<PagedResult<FileItem>> call(
    String query, {
    int page = 1,
    int pageSize = 50,
  }) {
    return _repository.searchFiles(query, page: page, pageSize: pageSize);
  }
}
