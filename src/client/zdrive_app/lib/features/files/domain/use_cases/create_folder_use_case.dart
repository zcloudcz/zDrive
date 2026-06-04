import 'package:injectable/injectable.dart';

import '../file_item.dart';
import '../file_repository.dart';

@lazySingleton
class CreateFolderUseCase {
  final FileRepository _repository;

  CreateFolderUseCase(this._repository);

  Future<FileItem> call(String? parentId, String name) {
    return _repository.createFolder(parentId, name);
  }
}
