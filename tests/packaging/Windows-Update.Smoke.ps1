# Execute in a fresh Windows PowerShell process. All writes stay in a temp profile.
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('zDrive-Update-Test-' + [guid]::NewGuid().ToString('N'))
$originalProfile = $env:LOCALAPPDATA
$global:launched = @()
$global:parentMode = 'gone'
$global:installedVersion = '0.2.1'
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Get-Process {
    param($Id, $Name, $ErrorAction)
    if ($Name) {
        if ($global:parentMode -eq 'another') { [pscustomobject]@{ Path = (Join-Path $source 'zdrive_app.exe') } }
        return
    }
    if ($global:parentMode -eq 'gone') { return }
    if ($global:parentMode -eq 'invalid') { return [pscustomobject]@{ Path = 'C:\unrelated.exe' } }
    $process = [pscustomobject]@{ Path = (Join-Path $source 'zdrive_app.exe') }
    $process | Add-Member ScriptMethod WaitForExit {
        param($timeout)
        Assert (Test-Path (Join-Path $updates "handoff-$handoff.ready")) 'Parent waited before readiness signal'
        Assert ([IO.File]::ReadAllBytes((Join-Path $updates "handoff-$handoff.ready"))[0] -eq 123) 'Readiness JSON has UTF-8 BOM'
        return $global:parentMode -ne 'running'
    }
    $process
}
function Get-ItemProperty { param($LiteralPath, $ErrorAction); [pscustomobject]@{ DisplayVersion = $global:installedVersion } }
function Start-Process {
    param($FilePath, $ArgumentList, $WorkingDirectory, $WindowStyle)
    if ($global:injectLaunchFailure -and $FilePath -like '*releases*0.2.2*zdrive_app.exe') { throw 'Injected new executable launch failure' }
    $global:launched += $FilePath
    Assert ($ArgumentList -eq '--skip-auto-update-once') 'Missing restart guard'
}
function Move-Item {
    param($LiteralPath, $Destination, [switch]$Force)
    if ($Destination -like '*.ready') {
        $global:readinessPublished = $true
        Assert ($global:parentMode -ne 'invalid') 'Readiness published before parent validation'
    }
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
}
function Remove-Item {
    param($LiteralPath, [switch]$Recurse, [switch]$Force, $ErrorAction)
    if ($global:injectCleanupFailure -and ($LiteralPath -like '*.apply-*' -or $LiteralPath -like '*.ready')) { throw 'Injected cleanup failure' }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Recurse:$Recurse -Force:$Force -ErrorAction Stop
}
try {
    $env:LOCALAPPDATA = Join-Path $fixture 'profile'
    $root = Join-Path $env:LOCALAPPDATA 'Programs/zDrive'
    $source = [IO.Path]::GetFullPath((Join-Path $root 'releases/0.2.1'))
    $updates = Join-Path $root 'updates'
    $package = Join-Path $fixture 'payload'
    New-Item -ItemType Directory -Path $source, (Join-Path $updates '0.2.2'), (Join-Path $package 'app'), (Join-Path $env:LOCALAPPDATA 'zdrive_app') -Force | Out-Null
    $userdata = Join-Path $env:LOCALAPPDATA 'zdrive_app/settings.json'
    Set-Content $userdata 'preserve me'
    Set-Content (Join-Path $source 'zdrive_app.exe') 'old executable'
    Copy-Item (Join-Path $PSScriptRoot '../../packaging/windows/Apply-Update.ps1') $source
    Set-Content (Join-Path $package 'version.txt') '0.2.2'
    Set-Content (Join-Path $package 'app/version.txt') '0.2.2'
    Set-Content (Join-Path $package 'app/zdrive_app.exe') 'new executable'
    @'
if ($global:injectInstallFailure) { throw 'Injected installer failure' }
$target = Join-Path $env:LOCALAPPDATA 'Programs/zDrive/releases/0.2.2'
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'app/*') $target -Recurse
'@ | Set-Content (Join-Path $package 'Install.ps1')
    $zip = Join-Path $updates '0.2.2/payload.zip'
    Compress-Archive -Path (Join-Path $package '*') -DestinationPath $zip
    $hash = (Get-FileHash $zip).Hash
    $size = (Get-Item $zip).Length
    $helper = Join-Path $source 'Apply-Update.ps1'
    $handoff = [guid]::NewGuid().ToString('N')
    Add-Type -TypeDefinition @'
using System;
using System.Threading;
public sealed class UpdateTestLock : IDisposable {
    readonly ManualResetEvent ready = new ManualResetEvent(false);
    readonly ManualResetEvent release = new ManualResetEvent(false);
    readonly Thread thread;
    public UpdateTestLock(string name) {
        thread = new Thread(() => {
            using (var mutex = new Mutex(false, name)) {
                mutex.WaitOne(); ready.Set(); release.WaitOne(); mutex.ReleaseMutex();
            }
        });
        thread.Start(); ready.WaitOne();
    }
    public void Dispose() { release.Set(); thread.Join(); ready.Dispose(); release.Dispose(); }
    public static bool Available(string name) {
        bool available = false;
        var probe = new Thread(() => {
            using (var mutex = new Mutex(false, name)) {
                available = mutex.WaitOne(0);
                if (available) mutex.ReleaseMutex();
            }
        });
        probe.Start(); probe.Join(); return available;
    }
}
'@
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $held = [UpdateTestLock]::new("Local\zDrive.Update.$sid")
    try {
        Set-Content (Join-Path $updates 'pending.json') '{"version":"0.2.2"}'
        & $helper -ParentProcessId 123 -SourceVersion 0.2.1 -Version 0.2.2 -ExpectedSha256 $hash -ExpectedSize $size -HandoffId $handoff
        Assert (Test-Path (Join-Path $updates 'pending.json')) 'Concurrent helper changed pending update'
        Assert ($global:launched.Count -eq 0) 'Concurrent helper launched app'
        Assert (-not (Test-Path (Join-Path $updates "handoff-$handoff.ready"))) 'Concurrent helper signaled readiness'
    } finally { $held.Dispose() }
    foreach ($scenario in @('size', 'hash', 'timeout', 'another', 'invalid', 'older', 'install', 'launch', 'success')) {
        $global:launched = @()
        $global:readinessPublished = $false
        $global:injectInstallFailure = $scenario -eq 'install'
        $global:injectLaunchFailure = $scenario -eq 'launch'
        $global:parentMode = if ($scenario -eq 'timeout') { 'running' } elseif ($scenario -in @('another', 'invalid')) { $scenario } else { 'exited' }
        $global:installedVersion = if ($scenario -eq 'older') { '0.2.3' } else { '0.2.1' }
        if ($scenario -eq 'older') {
            New-Item -ItemType Directory -Path (Join-Path $root 'releases/0.2.3') -Force | Out-Null
            Set-Content (Join-Path $root 'releases/0.2.3/zdrive_app.exe') 'newer executable'
        }
        Set-Content (Join-Path $updates 'pending.json') '{"version":"0.2.2"}'
        $testSize = if ($scenario -eq 'size') { $size + 1 } else { $size }
        $testHash = if ($scenario -eq 'hash') { '0' * 64 } else { $hash }
        & $helper -ParentProcessId 123 -SourceVersion 0.2.1 -Version 0.2.2 -ExpectedSha256 $testHash -ExpectedSize $testSize -HandoffId $handoff
        Assert (-not (Test-Path (Join-Path $updates 'pending.json'))) "$scenario left pending restart loop"
        Assert (-not (Test-Path (Join-Path $updates "handoff-$handoff.ready"))) 'Readiness marker leaked'
        if ($scenario -eq 'invalid') { Assert (-not $global:readinessPublished) 'Invalid parent received readiness handshake' }
        Assert ((Get-Content $userdata) -eq 'preserve me') "$scenario modified user data"
        Assert ((Get-Content (Join-Path $source 'zdrive_app.exe')) -eq 'old executable') "$scenario damaged old installation"
        Assert (@(Get-ChildItem $updates -Force | Where-Object Name -like '.apply-*').Count -eq 0) 'Extraction directory leaked'
        if ($scenario -in @('timeout', 'another', 'invalid')) { Assert ($global:launched.Count -eq 0) 'Launched duplicate app while another app still running' }
        else {
            Assert ($global:launched.Count -eq 1) "$scenario did not restart"
            $expected = switch ($scenario) { 'success' { '0.2.2' } 'older' { '0.2.3' } default { '0.2.1' } }
            Assert ($global:launched[0] -like "*releases*$expected*zdrive_app.exe") "$scenario restarted wrong version"
        }
        if ($scenario -eq 'success') { Assert (-not (Test-Path (Join-Path $updates 'last-error.json'))) 'Success left error' }
        else {
            Assert (Test-Path (Join-Path $updates 'last-error.json')) "$scenario did not record error"
            Assert ([IO.File]::ReadAllBytes((Join-Path $updates 'last-error.json'))[0] -eq 123) 'Error JSON has UTF-8 BOM'
        }
    }
    # Failure reporting and cleanup cannot prevent restarting the usable release.
    $errorPath = Join-Path $updates 'last-error.json'
    New-Item -ItemType Directory -Path $errorPath -Force | Out-Null
    $global:injectCleanupFailure = $true
    $global:injectInstallFailure = $true
    $global:launched = @()
    Set-Content (Join-Path $updates 'pending.json') '{"version":"0.2.2"}'
    try {
        & $helper -ParentProcessId 123 -SourceVersion 0.2.1 -Version 0.2.2 -ExpectedSha256 $hash -ExpectedSize $size -HandoffId $handoff
        Assert ($global:launched.Count -eq 1 -and $global:launched[0] -like '*releases*0.2.1*zdrive_app.exe') 'Log/cleanup failure prevented fallback restart'
        Assert (-not (Test-Path (Join-Path $updates 'pending.json'))) 'Log failure left restart loop'
        Assert ([UpdateTestLock]::Available("Local\zDrive.Update.$sid")) 'Cleanup failure leaked update mutex'
        Assert ((Get-Content $userdata) -eq 'preserve me') 'Recovery failure damaged user data'
    } finally {
        $global:injectCleanupFailure = $false
        $global:injectInstallFailure = $false
        Remove-Item -LiteralPath $errorPath -Recurse -Force
        foreach ($remaining in Get-ChildItem $updates -Force | Where-Object { $_.Name -like '.apply-*' -or $_.Name -like '*.ready' }) {
            $resolved = [IO.Path]::GetFullPath($remaining.FullName)
            Assert ($resolved.StartsWith([IO.Path]::GetFullPath($updates).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) 'Unsafe fixture cleanup'
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
    # A valid checksum does not make path traversal safe to extract.
    Remove-Item -LiteralPath $zip -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $archive.CreateEntry('../escape.txt')
        $writer = [IO.StreamWriter]::new($entry.Open())
        try { $writer.Write('escape') } finally { $writer.Dispose() }
    } finally { $archive.Dispose() }
    $global:parentMode = 'gone'
    $global:installedVersion = '0.2.1'
    & $helper -ParentProcessId 123 -SourceVersion 0.2.1 -Version 0.2.2 -ExpectedSha256 (Get-FileHash $zip).Hash -ExpectedSize (Get-Item $zip).Length -HandoffId $handoff
    Assert (-not (Test-Path (Join-Path $updates 'escape.txt'))) 'ZIP escaped extraction directory'
    Assert ((Get-Content (Join-Path $updates 'last-error.json') -Raw | ConvertFrom-Json).message -eq 'Unsafe update archive path.') 'Unsafe ZIP not rejected'
    'PASS: update success, size/hash and unsafe ZIP rejection, concurrent helper, parent timeout, other instance, newer-install protection, installer failure recovery and preserved user data.'
} finally {
    $env:LOCALAPPDATA = $originalProfile
    $boundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ([IO.Path]::GetFullPath($fixture).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
}
