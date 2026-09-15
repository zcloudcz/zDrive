import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zdrive_app/features/files/data/file_saver_io.dart';

class TestFilePicker extends FilePicker {
  String? selectedPath;
  Uint8List? savedBytes;
  int calls = 0;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    calls++;
    savedBytes = bytes;
    return selectedPath;
  }
}

void main() {
  late Directory temporary;
  late TestFilePicker picker;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('file_saver_test_');
    picker = TestFilePicker();
    FilePicker.platform = picker;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    temporary.deleteSync(recursive: true);
  });

  test('Save_Cancelled_DoesNotSubscribeToContent', () async {
    var consumed = false;
    Stream<Uint8List> content() async* {
      consumed = true;
      yield Uint8List.fromList([1]);
    }

    await saveFileStream('doc.txt', content());

    expect(picker.calls, 1);
    expect(consumed, isFalse);
    expect(temporary.listSync(), isEmpty);
  });

  test('Save_PartialStreamFails_PreservesTargetAndCleansStaging', () async {
    final destination = File(p.join(temporary.path, 'doc.txt'));
    await destination.writeAsString('original');
    picker.selectedPath = destination.path;
    final failure = Exception('verification failed at end of stream');
    Stream<Uint8List> content() async* {
      expect(picker.calls, 1);
      yield Uint8List.fromList([1, 2]);
      final staging = temporary.listSync().whereType<Directory>().single;
      expect(await File(p.join(staging.path, 'content')).length(), 2);
      expect(await destination.readAsString(), 'original');
      throw failure;
    }

    await expectLater(saveFileStream('doc.txt', content()), throwsA(same(failure)));

    expect(await destination.readAsString(), 'original');
    expect(temporary.listSync().map((e) => p.basename(e.path)), ['doc.txt']);
    expect(picker.savedBytes, isNull);
  });

  test('Save_MultipleChunks_ReplacesTargetOnlyAfterCompletion', () async {
    final destination = File(p.join(temporary.path, 'doc.txt'));
    await destination.writeAsString('original');
    picker.selectedPath = destination.path;
    Stream<Uint8List> content() async* {
      expect(picker.calls, 1);
      yield Uint8List.fromList([1, 2]);
      expect(await destination.readAsString(), 'original');
      yield Uint8List.fromList([3, 4]);
    }

    await saveFileStream('doc.txt', content());

    expect(await destination.readAsBytes(), [1, 2, 3, 4]);
    expect(temporary.listSync(), hasLength(1));
    expect(picker.savedBytes, isNull);
  });

  test('Save_EmptyStream_CreatesEmptyFile', () async {
    final destination = File(p.join(temporary.path, 'empty.txt'));
    picker.selectedPath = destination.path;

    await saveFileStream('empty.txt', const Stream.empty());

    expect(await destination.length(), 0);
    expect(temporary.listSync(), hasLength(1));
  });

  test('Save_Mobile_CollectsBytesForPlatformPlugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await saveFileStream('doc.txt', Stream.fromIterable([
      Uint8List.fromList([1, 2]), Uint8List.fromList([3, 4]),
    ]));

    expect(picker.calls, 1);
    expect(picker.savedBytes, [1, 2, 3, 4]);
  });
}
