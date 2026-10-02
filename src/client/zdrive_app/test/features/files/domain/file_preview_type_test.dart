import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/features/files/domain/file_preview_type.dart';

void main() {
  group('detectPreviewKind', () {
    test('DetectPreviewKind_ImageMimeType_ReturnsImage', () {
      expect(
        detectPreviewKind(mimeType: 'image/png', fileName: 'x'),
        PreviewKind.image,
      );
    });

    test('DetectPreviewKind_PdfMimeType_ReturnsPdf', () {
      expect(
        detectPreviewKind(mimeType: 'application/pdf', fileName: 'x'),
        PreviewKind.pdf,
      );
    });

    test('DetectPreviewKind_TextMimeType_ReturnsText', () {
      expect(
        detectPreviewKind(mimeType: 'text/csv', fileName: 'x'),
        PreviewKind.text,
      );
      expect(
        detectPreviewKind(mimeType: 'application/json', fileName: 'x'),
        PreviewKind.text,
      );
    });

    test('DetectPreviewKind_StoredMimeTypeWins_OverExtension', () {
      expect(
        detectPreviewKind(mimeType: 'image/png', fileName: 'photo.pdf'),
        PreviewKind.image,
      );
    });

    test('DetectPreviewKind_NullMimeType_FallsBackToExtension', () {
      for (final name in [
        'a.jpg',
        'A.JPEG',
        'a.png',
        'a.gif',
        'a.webp',
        'a.bmp',
        'a.heic',
      ]) {
        expect(detectPreviewKind(fileName: name), PreviewKind.image, reason: name);
      }
      expect(detectPreviewKind(fileName: 'a.pdf'), PreviewKind.pdf);
    });

    test('DetectPreviewKind_OctetStreamMimeType_FallsBackToExtension', () {
      expect(
        detectPreviewKind(mimeType: 'application/octet-stream', fileName: 'a.png'),
        PreviewKind.image,
      );
    });

    test('DetectPreviewKind_TextAndCodeExtensions_ReturnsText', () {
      for (final name in [
        'a.txt',
        'a.md',
        'a.json',
        'a.csv',
        'a.log',
        'a.xml',
        'a.yaml',
        'a.yml',
        'a.py',
        'a.cs',
        'a.dart',
        'a.ts',
      ]) {
        expect(detectPreviewKind(fileName: name), PreviewKind.text, reason: name);
      }
    });

    test('DetectPreviewKind_UnknownOrOtherTypes_ReturnsUnsupported', () {
      expect(detectPreviewKind(fileName: 'noextension'), PreviewKind.unsupported);
      expect(detectPreviewKind(fileName: 'a.docx'), PreviewKind.unsupported);
      expect(detectPreviewKind(fileName: 'a.mp4'), PreviewKind.unsupported);
      expect(detectPreviewKind(fileName: 'a.svg'), PreviewKind.unsupported);
      expect(
        detectPreviewKind(mimeType: 'video/mp4', fileName: 'a.bin'),
        PreviewKind.unsupported,
      );
    });
  });

  group('mimeTypeForFileName', () {
    test('MimeTypeForFileName_KnownExtension_ReturnsMimeType', () {
      expect(mimeTypeForFileName('photo.JPG'), 'image/jpeg');
      expect(mimeTypeForFileName('doc.pdf'), 'application/pdf');
    });

    test('MimeTypeForFileName_UnknownExtension_ReturnsNull', () {
      expect(mimeTypeForFileName('noextension'), isNull);
    });
  });

  group('detectPreviewKind stored type precedence', () {
    test('DetectPreviewKind_StoredImageTypeWithTextExtension_ReturnsImage', () {
      expect(
        detectPreviewKind(mimeType: 'image/png', fileName: 'scan.txt'),
        PreviewKind.image,
      );
    });

    test('DetectPreviewKind_StoredPdfTypeWithTextExtension_ReturnsPdf', () {
      expect(
        detectPreviewKind(mimeType: 'application/pdf', fileName: 'scan.md'),
        PreviewKind.pdf,
      );
    });

    test('DetectPreviewKind_TsWithVideoMimeType_StillReturnsText', () {
      expect(
        detectPreviewKind(mimeType: 'video/mp2t', fileName: 'app.ts'),
        PreviewKind.text,
      );
    });
  });
}
