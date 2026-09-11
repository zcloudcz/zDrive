import 'package:injectable/injectable.dart';

import '../file_repository.dart';

@lazySingleton
class UploadFileUseCase {
  final FileRepository _repository;

  UploadFileUseCase(this._repository);

  Future<String> call(
    String? parentId,
    String fileName,
    Stream<List<int>> content,
    int sizeBytes, {
    void Function(double progress)? onProgress,
  }) {
    return _repository.uploadFile(parentId, fileName, content, sizeBytes, onProgress);
  }
}
