class UpdateManifest {
  const UpdateManifest(this.version, this.url, this.sha256, this.sizeBytes);

  final String version;
  final Uri url;
  final String sha256;
  final int sizeBytes;
  static final versionPattern = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
  );
  static const maxPayloadBytes = 512 * 1024 * 1024;

  factory UpdateManifest.parse(Object? value) {
    if (value is! Map<String, dynamic> || value['schemaVersion'] != 1) {
      throw const FormatException('Unsupported update manifest');
    }
    final version = value['version'];
    final hash = value['sha256'];
    final size = value['sizeBytes'];
    if (version is! String ||
        version.length > 40 ||
        !versionPattern.hasMatch(version) ||
        hash is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
        size is! int ||
        size <= 0 ||
        size > maxPayloadBytes) {
      throw const FormatException('Invalid update metadata');
    }
    final expected =
        'https://drive.zcloud.cz/downloads/zDrive-$version-windows-x64.zip';
    if (value['url'] != expected) {
      throw const FormatException('Untrusted update URL');
    }
    return UpdateManifest(
      version,
      Uri.parse(expected),
      hash.toLowerCase(),
      size,
    );
  }

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'version': version,
    'url': url.toString(),
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };

  bool isNewerThan(String current) => compareVersions(version, current) > 0;

  static int compareVersions(String a, String b) {
    if (!versionPattern.hasMatch(a) || !versionPattern.hasMatch(b)) {
      throw const FormatException('Invalid version');
    }
    final left = a.split('.').map(BigInt.parse).toList();
    final right = b.split('.').map(BigInt.parse).toList();
    for (var i = 0; i < 3; i++) {
      final result = left[i].compareTo(right[i]);
      if (result != 0) return result;
    }
    return 0;
  }
}
