/// Only numeric/boolean values leave callers. Arbitrary text can contain file
/// names, URLs, credentials, or server response bodies.
Map<String, Object?> diagnosticRecord(
  String name,
  Map<String, Object?> fields,
) {
  return {
    'time': DateTime.now().toUtc().toIso8601String(),
    'event': RegExp(r'^[a-zA-Z0-9_.]{1,80}$').hasMatch(name)
        ? name
        : 'invalid_event',
    for (final entry in fields.entries.take(24))
      if (RegExp(r'^[a-zA-Z0-9_]{1,40}$').hasMatch(entry.key))
        entry.key:
            (entry.value is num && (entry.value as num).isFinite) ||
                entry.value is bool ||
                entry.value == null
            ? entry.value
            : '[redacted]',
  };
}

/// Retain code frames, never absolute filesystem paths or exception messages.
List<String> diagnosticStack(StackTrace? stack) => (stack?.toString() ?? '')
    .split('\n')
    .where(
      (line) => line.contains('package:zdrive_app/') || line.contains('dart:'),
    )
    .take(20)
    .map((line) {
      final match = RegExp(
        r'(?:package:zdrive_app/|dart:)[a-zA-Z0-9_./:-]+',
      ).firstMatch(line);
      final frame = match?.group(0) ?? '[frame]';
      return frame.substring(0, frame.length.clamp(0, 240));
    })
    .toList();
