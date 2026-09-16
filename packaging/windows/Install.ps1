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
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force
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
