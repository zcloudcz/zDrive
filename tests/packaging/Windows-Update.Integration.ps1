# Real child processes; only fixture installation metadata is substituted.
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('zDrive-Update-Integration-' + [guid]::NewGuid().ToString('N'))
$originalProfile = $env:LOCALAPPDATA
$children = @()
function Assert($condition, $message) { if (-not $condition) { throw $message } }
try {
    $env:LOCALAPPDATA = Join-Path $fixture 'profile'
    $root = Join-Path $env:LOCALAPPDATA 'Programs/zDrive'
    $source = Join-Path $root 'releases/0.2.1'
    $updates = Join-Path $root 'updates'
    $package = Join-Path $fixture 'payload'
    New-Item -ItemType Directory -Path $source, (Join-Path $updates '0.2.2'), (Join-Path $package 'app') -Force | Out-Null
    $userMarker = Join-Path $env:LOCALAPPDATA 'user-data.txt'
    Set-Content -LiteralPath $userMarker -Value 'preserve user data'
    $exe = Join-Path $source 'zdrive_app.exe'
    Add-Type -OutputAssembly $exe -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
public static class UpdateFixture {
    public static int Main(string[] args) {
        if (args.Length == 1 && args[0] == "--skip-auto-update-once") {
            File.WriteAllText(Path.Combine(Environment.GetEnvironmentVariable("LOCALAPPDATA"), "restarted.txt"),
                System.Reflection.Assembly.GetExecutingAssembly().Location);
            return 0;
        }
        if (args.Length != 1) return 2;
        var deadline = DateTime.UtcNow.AddSeconds(30);
        while (DateTime.UtcNow < deadline) {
            if (File.Exists(args[0])) return 0;
            Thread.Sleep(20);
        }
        return 3;
    }
}
'@
    Copy-Item -LiteralPath $exe -Destination (Join-Path $package 'app/zdrive_app.exe')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../packaging/windows/Apply-Update.ps1') -Destination $source
    Set-Content -LiteralPath (Join-Path $package 'version.txt') -Value '0.2.2'
    Set-Content -LiteralPath (Join-Path $package 'app/version.txt') -Value '0.2.2'
    @'
$target = Join-Path $env:LOCALAPPDATA 'Programs/zDrive/releases/0.2.2'
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'app/*') -Destination $target -Recurse
'@ | Set-Content -LiteralPath (Join-Path $package 'Install.ps1')
    $zip = Join-Path $updates '0.2.2/payload.zip'
    Compress-Archive -Path (Join-Path $package '*') -DestinationPath $zip
    $hash = (Get-FileHash -LiteralPath $zip).Hash
    $size = (Get-Item -LiteralPath $zip).Length
    $handoff = [guid]::NewGuid().ToString('N')
    $ready = Join-Path $updates "handoff-$handoff.ready"
    Set-Content -LiteralPath (Join-Path $updates 'pending.json') -Value '{"version":"0.2.2"}'
    $old = Start-Process -FilePath $exe -ArgumentList ('"{0}"' -f $ready) -PassThru -WindowStyle Hidden
    $children += $old
    $wrapper = Join-Path $fixture 'invoke-helper.ps1'
    @'
param($Helper, $ParentId, $Hash, $Size, $Handoff)
function Get-ItemProperty {
    param($LiteralPath, $ErrorAction)
    if ($LiteralPath -ne 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/zDrive') { throw 'Unexpected metadata lookup' }
    [pscustomobject]@{ DisplayVersion = '0.2.1' }
}
& $Helper -ParentProcessId $ParentId -SourceVersion 0.2.1 -Version 0.2.2 -ExpectedSha256 $Hash -ExpectedSize $Size -HandoffId $Handoff
'@ | Set-Content -LiteralPath $wrapper
    $helperPath = Join-Path $source 'Apply-Update.ps1'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Helper "{1}" -ParentId {2} -Hash {3} -Size {4} -Handoff {5}' -f $wrapper, $helperPath, $old.Id, $hash, $size, $handoff
    $helper = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru -WindowStyle Hidden
    $children += $helper
    Assert ($helper.WaitForExit(30000)) 'Real updater exceeded 30-second deadline'
    Assert ($helper.ExitCode -eq 0) 'Real updater process failed'
    Assert ($old.WaitForExit(2000) -and $old.ExitCode -eq 0) 'Original application did not exit after handoff'
    $marker = Join-Path $env:LOCALAPPDATA 'restarted.txt'
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while (-not (Test-Path -LiteralPath $marker) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 25 }
    Assert (Test-Path -LiteralPath $marker) 'Updated executable did not run automatically'
    Assert ((Get-Content -LiteralPath $marker -Raw) -eq [IO.Path]::GetFullPath((Join-Path $root 'releases/0.2.2/zdrive_app.exe'))) 'Fallback launched instead of updated executable'
    Assert (-not (Test-Path -LiteralPath (Join-Path $updates 'pending.json'))) 'Successful update left pending descriptor'
    Assert (-not (Test-Path -LiteralPath (Join-Path $updates 'last-error.json'))) 'Successful update recorded an error'
    Assert ((Get-Content -LiteralPath $userMarker) -eq 'preserve user data') 'Update modified user data'
    'PASS: real helper process, handoff, parent exit, verified extraction and automatic new executable launch.'
} finally {
    foreach ($child in $children) {
        if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit(2000) | Out-Null }
        $child.Dispose()
    }
    $env:LOCALAPPDATA = $originalProfile
    $boundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ([IO.Path]::GetFullPath($fixture).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}
