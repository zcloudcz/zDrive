param(
    [Parameter(Mandatory)] [ValidateRange(1, 2147483647)] [int] $ParentProcessId,
    [Parameter(Mandatory)] [ValidatePattern('^\d+\.\d+\.\d+$')] [string] $SourceVersion,
    [Parameter(Mandatory)] [ValidatePattern('^\d+\.\d+\.\d+$')] [string] $Version,
    [Parameter(Mandatory)] [ValidatePattern('^[a-fA-F0-9]{64}$')] [string] $ExpectedSha256,
    [Parameter(Mandatory)] [ValidateRange(1, 2147483648)] [long] $ExpectedSize,
    [Parameter(Mandatory)] [ValidatePattern('^[a-fA-F0-9]{32}$')] [string] $HandoffId
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs/zDrive'))
$updates = Join-Path $root 'updates'
$source = [IO.Path]::GetFullPath((Join-Path $root "releases/$SourceVersion"))
$pending = Join-Path $updates 'pending.json'
$stage = Join-Path $updates ('.apply-' + [guid]::NewGuid().ToString('N'))
$restartVersion = $SourceVersion
$parentExited = $false
$ownsMutex = $false
$mutex = $null
$ready = Join-Path $updates "handoff-$HandoffId.ready"
function Clear-MatchingPending {
    try {
        if (Test-Path -LiteralPath $pending) {
            if ((Get-Content -LiteralPath $pending -Raw | ConvertFrom-Json).version -eq $Version) {
                Remove-Item -LiteralPath $pending -Force
            }
        }
    } catch { }
}
function Start-InstalledApp([string] $releaseVersion) {
    $installBoundary = $root.TrimEnd('\') + '\'
    $running = Get-Process -Name zdrive_app -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith($installBoundary, [StringComparison]::OrdinalIgnoreCase)
    }
    if ($running) { return }
    $exe = Join-Path $root "releases/$releaseVersion/zdrive_app.exe"
    if (Test-Path -LiteralPath $exe -PathType Leaf) {
        Start-Process -FilePath $exe -ArgumentList '--skip-auto-update-once' -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden | Out-Null
    }
}
try {
    if (-not [string]::Equals([IO.Path]::GetFullPath($PSScriptRoot), $source, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath (Join-Path $source 'zdrive_app.exe') -PathType Leaf)) { throw 'Updater must run from the installed source release.' }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $mutex = [Threading.Mutex]::new($false, "Local\zDrive.Update.$sid")
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { return }
    New-Item -ItemType Directory -Path $updates -Force | Out-Null
    $readyJson = @{ version = $Version; processId = $PID } | ConvertTo-Json
    [IO.File]::WriteAllText("$ready.tmp", $readyJson, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath "$ready.tmp" -Destination $ready -Force
    $parent = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
    if ($parent) {
        if (-not [string]::Equals($parent.Path, (Join-Path $source 'zdrive_app.exe'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected parent process.' }
        if (-not $parent.WaitForExit(120000)) { throw 'The application did not close in time.' }
    }
    $parentExited = $true
    $installBoundary = $root.TrimEnd('\') + '\'
    $running = Get-Process -Name zdrive_app -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith($installBoundary, [StringComparison]::OrdinalIgnoreCase)
    }
    if ($running) { throw 'Another zDrive instance is still running.' }
    if ([version]$Version -le [version]$SourceVersion) { throw 'The update is not newer than the running version.' }
    $registration = Get-ItemProperty -LiteralPath 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/zDrive' -ErrorAction SilentlyContinue
    if ($registration -and $registration.DisplayVersion -match '^\d+\.\d+\.\d+$') {
        if ([version]$registration.DisplayVersion -gt [version]$SourceVersion) { $restartVersion = $registration.DisplayVersion }
        if ([version]$registration.DisplayVersion -ge [version]$Version) { throw 'This version or a newer version is already installed.' }
    }
    $zipPath = Join-Path $updates "$Version/payload.zip"
    if ((Get-Item -LiteralPath $zipPath).Length -ne $ExpectedSize) { throw 'Update size does not match.' }
    if ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ne $ExpectedSha256) { throw 'Update checksum does not match.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $stageBoundary = [IO.Path]::GetFullPath($stage).TrimEnd('\') + '\'
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match '(^[/\\]|:|(^|[/\\])\.\.([/\\]|$))') { throw 'Unsafe update archive path.' }
            $destination = [IO.Path]::GetFullPath((Join-Path $stage $entry.FullName))
            if (-not $destination.StartsWith($stageBoundary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe update archive path.' }
        }
    } finally { $archive.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $stage)
    if ((Get-Content -LiteralPath (Join-Path $stage 'version.txt') -Raw).Trim() -ne $Version -or
        (Get-Content -LiteralPath (Join-Path $stage 'app/version.txt') -Raw).Trim() -ne $Version) { throw 'Update package version does not match.' }
    & (Join-Path $stage 'Install.ps1')
    $restartVersion = $Version
    Clear-MatchingPending
    $errorFile = Join-Path $updates 'last-error.json'
    if (Test-Path -LiteralPath $errorFile) { Remove-Item -LiteralPath $errorFile -Force }
    Start-InstalledApp $restartVersion
} catch {
    if ($ownsMutex) {
        $message = $_.Exception.Message
        try {
            New-Item -ItemType Directory -Path $updates -Force | Out-Null
            if ($message.Length -gt 1000) { $message = $message.Substring(0, 1000) }
            $errorJson = @{ version = $Version; message = $message } | ConvertTo-Json
            [IO.File]::WriteAllText((Join-Path $updates 'last-error.json'), $errorJson, [Text.UTF8Encoding]::new($false))
        } catch { }
        Clear-MatchingPending
        if ($parentExited) { Start-InstalledApp $restartVersion }
    }
} finally {
    try {
        try {
            if ($ownsMutex -and (Test-Path -LiteralPath $ready)) { Remove-Item -LiteralPath $ready -Force }
        } catch { }
        try {
            $boundary = [IO.Path]::GetFullPath($updates).TrimEnd('\') + '\'
            if ([IO.Path]::GetFullPath($stage).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $stage)) {
                Remove-Item -LiteralPath $stage -Recurse -Force
            }
        } catch { }
    } finally {
        try { if ($ownsMutex) { $mutex.ReleaseMutex() } }
        finally { if ($mutex) { $mutex.Dispose() } }
    }
}
