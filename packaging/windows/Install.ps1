$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitOperatingSystem) { throw 'zDrive requires 64-bit Windows.' }
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'version.txt') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$') { throw 'Invalid package version.' }
$root = Join-Path $env:LOCALAPPDATA 'Programs/zDrive'
$target = Join-Path $root "releases/$version"
$boundary = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
$running = Get-Process -Name zdrive_app -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and $_.Path.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)
}
if ($running) { throw 'Close zDrive before installing an update, then run Setup again.' }
$source = Join-Path $PSScriptRoot 'app'
foreach ($file in @('zdrive_app.exe', 'flutter_windows.dll', 'data/icudtl.dat', 'data/app.so', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)) { throw "Incomplete package: $file" }
}
$releases = [IO.Path]::GetFullPath((Join-Path $root 'releases'))
$releaseBoundary = $releases.TrimEnd('\') + '\'
$stage = Join-Path $releases ('.stage-' + [guid]::NewGuid().ToString('N'))
$backup = Join-Path $releases ('.backup-' + [guid]::NewGuid().ToString('N'))
foreach ($path in @($target, $stage, $backup)) {
    if (-not [IO.Path]::GetFullPath($path).StartsWith($releaseBoundary, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe installer path: $path" }
}
function Remove-InstallerDirectory([string] $path) {
    $resolved = [IO.Path]::GetFullPath($path)
    if (-not $resolved.StartsWith($releaseBoundary, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe installer cleanup path: $resolved" }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Copy-Item -Path (Join-Path $source '*') -Destination $stage -Recurse -Force
    foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
        $relative = $file.FullName.Substring($source.TrimEnd('\').Length).TrimStart('\')
        $copied = Join-Path $stage $relative
        if (-not (Test-Path -LiteralPath $copied -PathType Leaf) -or
            (Get-FileHash -LiteralPath $copied).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) {
            throw "Incomplete staged package: $relative"
        }
    }
    # Copying can take time; the user may have opened the old app meanwhile.
    $running = Get-Process -Name zdrive_app -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)
    }
    if ($running) { throw 'Close zDrive before installing an update, then run Setup again.' }
    if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $backup }
    try { Move-Item -LiteralPath $stage -Destination $target }
    catch {
        if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination $target }
        throw
    }
    Remove-InstallerDirectory $backup
}
finally { Remove-InstallerDirectory $stage }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination $root -Force
$shell = New-Object -ComObject WScript.Shell
foreach ($directory in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {
    $shortcut = $shell.CreateShortcut((Join-Path $directory 'zDrive.lnk'))
    $shortcut.TargetPath = Join-Path $target 'zdrive_app.exe'
    $shortcut.WorkingDirectory = $target
    $shortcut.IconLocation = $shortcut.TargetPath
    $shortcut.Save()
}
$key = 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/zDrive'
New-Item -Path $key -Force | Out-Null
$values = @{
    DisplayName = 'zDrive'; DisplayVersion = $version; Publisher = 'zCloud'
    InstallLocation = $root; DisplayIcon = (Join-Path $target 'zdrive_app.exe')
    UninstallString = ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'Uninstall.ps1'))
}
foreach ($name in $values.Keys) { New-ItemProperty -Path $key -Name $name -Value $values[$name] -PropertyType String -Force | Out-Null }
foreach ($name in @('NoModify', 'NoRepair')) { New-ItemProperty -Path $key -Name $name -Value 1 -PropertyType DWord -Force | Out-Null }
# Launch at login so sync stays continuous instead of only running while the
# user remembers to open the app. Rewritten on every install/update, since
# $target is per-version (releases/<version>) and would otherwise go stale
# the moment an update moves the exe. --start-hidden skips the window and
# goes straight to the tray icon (see windows/runner/flutter_window.cpp).
New-ItemProperty -Path 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Run' -Name 'zDrive' `
    -Value ('"{0}" --start-hidden' -f (Join-Path $target 'zdrive_app.exe')) -PropertyType String -Force | Out-Null
