import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zdrive_app/core/update/auto_update_io.dart';
import 'package:zdrive_app/core/update/update_manifest.dart';

void main() {
  test(
    'Windows updater starts PowerShell and acknowledges the handoff',
    () async {
      final root = await Directory.systemTemp.createTemp('zdrive-launch-test-');
      final helper = File('${root.path}/probe.ps1');
      await Directory('${root.path}/updates').create();
      await helper.writeAsString(r'''
param($ParentProcessId, $SourceVersion, $Version, $ExpectedSha256, $ExpectedSize, $HandoffId)
$ErrorActionPreference = 'Stop'
$ready = Join-Path $PSScriptRoot "updates/handoff-$HandoffId.ready"
$json = @{ version = $Version; processId = $PID } | ConvertTo-Json
[IO.File]::WriteAllText($ready, $json, [Text.UTF8Encoding]::new($false))
''');
      final backend = WindowsUpdateBackend(root.path, '0.2.3', helper.path);
      try {
        await backend.launch(
          UpdateManifest(
            '0.2.5',
            Uri.parse(
              'https://drive.zcloud.cz/downloads/zDrive-0.2.5-windows-x64.zip',
            ),
            '0' * 64,
            1,
          ),
        );
        expect(await Directory('${root.path}/updates').list().length, 1);
      } finally {
        backend.close();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}
