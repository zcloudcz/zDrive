import 'package:mime/mime.dart';

/// What the in-app preview can show for a file.
enum PreviewKind { image, text, pdf, unsupported }

/// Files above this many bytes are offered for download instead of previewed.
const int previewMaxBytes = 50 * 1024 * 1024;

/// Text previews are capped lower — [SelectableText] lays out the whole string.
const int previewTextMaxBytes = 1024 * 1024;

const _imageMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
  // Decoded only where the platform codec supports it; the preview page falls
  // back to "preview unavailable" when decoding fails.
  'image/heic',
  'image/heif',
};

const _textMimeTypes = {
  'application/json',
  'application/xml',
  'application/javascript',
  'application/x-sh',
  'application/yaml',
  'application/x-yaml',
};

// The `mime` package has no mapping for these, or maps them to a non-text type
// (`.ts` is video/mp2t).
const _textExtensions = {
  'txt', 'md', 'json', 'csv', 'log', 'xml', 'yaml', 'yml', 'toml', 'ini',
  'cs', 'dart', 'py', 'js', 'ts', 'java', 'kt', 'go', 'rs', 'sh', 'html',
  'css', 'sql',
};

/// MIME type for [fileName] from its extension, or null when unknown.
String? mimeTypeForFileName(String fileName) => lookupMimeType(fileName);

/// The preview kind for a file, from its stored [mimeType] when it is
/// informative, otherwise from the extension of [fileName].
PreviewKind detectPreviewKind({String? mimeType, required String fileName}) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  if (_textExtensions.contains(extension)) return PreviewKind.text;

  final stored = mimeType?.toLowerCase();
  final mime = stored == null || stored.isEmpty || stored == 'application/octet-stream'
      ? mimeTypeForFileName(fileName)
      : stored;
  if (mime == null) return PreviewKind.unsupported;
  if (_imageMimeTypes.contains(mime)) return PreviewKind.image;
  if (mime == 'application/pdf') return PreviewKind.pdf;
  // Other images (SVG, TIFF, ...) are not decodable by Image.memory.
  if (mime.startsWith('image/')) return PreviewKind.unsupported;
  if (mime.startsWith('text/') ||
      _textMimeTypes.contains(mime) ||
      mime.endsWith('+json') ||
      mime.endsWith('+xml')) {
    return PreviewKind.text;
  }
  return PreviewKind.unsupported;
}
