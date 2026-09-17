import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'update_controller.dart';
import 'update_manifest.dart';
import '../diagnostics/diagnostics.dart';

Future<UpdateController?> createAutoUpdater({
  required Future<void> Function() drain,
  required Future<void> Function() resume,
}) async {
  if (!Platform.isWindows) return null;
  try {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null) return null;
    final root = await Directory(
      p.join(local, 'Programs', 'zDrive'),
    ).resolveSymbolicLinks();
    final executable = await File(
      Platform.resolvedExecutable,
    ).resolveSymbolicLinks();
    final versionDirectory = p.dirname(executable);
    final version = p.basename(versionDirectory);
    if (!UpdateManifest.versionPattern.hasMatch(version) ||
        !p.equals(p.dirname(versionDirectory), p.join(root, 'releases')) ||
        p.basename(executable).toLowerCase() != 'zdrive_app.exe') {
      return null;
    }
    final installedVersion = (await File(
      p.join(versionDirectory, 'version.txt'),
    ).readAsString()).trim();
    if (installedVersion != version) return null;
    final helper = await File(
      p.join(versionDirectory, 'Apply-Update.ps1'),
    ).resolveSymbolicLinks();
    if (!p.equals(p.dirname(helper), versionDirectory)) return null;
    return UpdateController(
      WindowsUpdateBackend(root, version, helper),
      drain: drain,
      resume: resume,
    );
  } catch (_) {
    // Development, portable and old installations do not support this updater.
    return null;
  }
}

class WindowsUpdateBackend implements UpdateBackend {
  WindowsUpdateBackend(
    this.installRoot,
    this.currentVersion,
    this.helper, {
    HttpClient? httpClient,
  }) : _client = httpClient ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 15);
  }
  final String installRoot;
  @override
  final String currentVersion;
  final String helper;
  final HttpClient _client;
  bool _closed = false;
  String get _updates => p.join(installRoot, 'updates');
  File get _pending => File(p.join(_updates, 'pending.json'));
  File _payload(UpdateManifest manifest) =>
      File(p.join(_updates, manifest.version, 'payload.zip'));

  Future<Object?> _readJson(File file) async {
    if (await file.length() > 16384) {
      throw const FormatException('Update metadata too large');
    }
    return jsonDecode(await file.readAsString());
  }

  @override
  Future<UpdateManifest?> readPending() async {
    if (!await _pending.exists()) return null;
    try {
      final manifest = UpdateManifest.parse(await _readJson(_pending));
      if (!manifest.isNewerThan(currentVersion)) {
        await _pending.delete();
        return null;
      }
      await _verify(_payload(manifest), manifest);
      return manifest;
    } catch (_) {
      if (await _pending.exists()) await _pending.delete();
      rethrow;
    }
  }

  @override
  Future<bool> consumePreviousError() async {
    final file = File(p.join(_updates, 'last-error.json'));
    if (!await file.exists()) return false;
    // Error details are local diagnostics, never rendered as untrusted UI text.
    await file.delete();
    return true;
  }

  Future<HttpClientResponse> _get(Uri uri) async {
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      await response.listen((_) {}).cancel();
      throw HttpException('Update request rejected', uri: uri);
    }
    return response;
  }

  @override
  Future<UpdateManifest> fetchManifest() async {
    final response = await _get(
      Uri.parse('https://drive.zcloud.cz/downloads/windows-latest.json'),
    );
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > 16384) {
        throw const FormatException('Update metadata too large');
      }
      bytes.addAll(chunk);
    }
    return UpdateManifest.parse(jsonDecode(utf8.decode(bytes)));
  }

  @override
  Future<void> prepare(
    UpdateManifest manifest,
    void Function(int) onBytes,
  ) async {
    final payload = _payload(manifest);
    await payload.parent.create(recursive: true);
    final part = File('${payload.path}.part');
    final output = part.openWrite();
    var bytes = 0;
    final throttle = Stopwatch()..start();
    try {
      final response = await _get(manifest.url);
      if (response.contentLength >= 0 &&
          response.contentLength != manifest.sizeBytes) {
        throw const FormatException('Incorrect download length');
      }
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (_closed) throw const HttpException('Updater closed');
        bytes += chunk.length;
        if (bytes > manifest.sizeBytes) {
          throw const FormatException('Download exceeds expected size');
        }
        output.add(chunk);
        // Flush applies backpressure: no unbounded queued buffers on a slow disk.
        await output.flush();
        if (throttle.elapsedMilliseconds >= 150) {
          onBytes(bytes);
          throttle.reset();
        }
      }
      await output.close();
      await _verify(part, manifest);
      if (_closed) return;
      if (await payload.exists()) await payload.delete();
      await part.rename(payload.path);
      final descriptor = File('${_pending.path}.tmp');
      await descriptor.writeAsString(
        jsonEncode(manifest.toJson()),
        flush: true,
      );
      if (await _pending.exists()) await _pending.delete();
      await descriptor.rename(_pending.path);
      onBytes(bytes);
    } catch (_) {
      try {
        await output.close();
      } catch (_) {
        /* Preserve original failure. */
      }
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  Future<void> _verify(File file, UpdateManifest manifest) async {
    final path = file.path;
    final expectedHash = manifest.sha256;
    final expectedSize = manifest.sizeBytes;
    await Isolate.run(() async {
      final input = File(path);
      if (await input.length() != expectedSize ||
          (await sha256.bind(input.openRead()).first).toString() !=
              expectedHash) {
        throw const FormatException('Update integrity check failed');
      }
    });
  }

  @override
  Future<void> launch(UpdateManifest manifest) async {
    final random = Random.secure();
    final handoff = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final marker = File(p.join(_updates, 'handoff-$handoff.ready'));
    final process = await Process.start('powershell.exe', [
      '-NoProfile',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      helper,
      '-ParentProcessId',
      '$pid',
      '-SourceVersion',
      currentVersion,
      '-Version',
      manifest.version,
      '-ExpectedSha256',
      manifest.sha256,
      '-ExpectedSize',
      '${manifest.sizeBytes}',
      '-HandoffId',
      handoff,
    ], mode: ProcessStartMode.detached);
    final deadline = Stopwatch()..start();
    while (!_closed && deadline.elapsed < const Duration(seconds: 15)) {
      if (await marker.exists()) {
        try {
          final value = await _readJson(marker);
          if (value is Map &&
              value['version'] == manifest.version &&
              value['processId'] == process.pid) {
            return;
          }
        } on FormatException {
          /* Writer may still be finishing. */
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const ProcessException(
      'powershell.exe',
      [],
      'Update handoff timed out',
    );
  }

  @override
  Future<void> quit() async {
    Diagnostics.event('app.update.restart');
    await Diagnostics.flush();
    await const MethodChannel(
      'zdrive/windows_lifecycle',
    ).invokeMethod<void>('quit');
  }

  @override
  void close() {
    _closed = true;
    _client.close(force: true);
  }
}
