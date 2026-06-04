import 'package:injectable/injectable.dart';

import '../file_repository.dart';

@lazySingleton
class DeleteFileUseCase {
  final FileRepository _repository;

  DeleteFileUseCase(this._repository);

  Future<void> call(String id) {
    return _repository.deleteFile(id);
  }
}
