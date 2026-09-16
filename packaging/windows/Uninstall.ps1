$ErrorActionPreference = 'Stop'
try {
    $root = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs/zDrive'))
    if ([IO.Path]::GetFullPath($PSScriptRoot) -ne $root) { throw 'Unexpected uninstall location.' }
    $boundary = $root.TrimEnd('\') + '\'
    $running = Get-Process -Name zdrive_app -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)
    }
    if ($running) { throw 'Close zDrive before uninstalling.' }
    foreach ($directory in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {
        Remove-Item -LiteralPath (Join-Path $directory 'zDrive.lnk') -Force -ErrorAction SilentlyContinue
    }
    $releases = [IO.Path]::GetFullPath((Join-Path $root 'releases'))
    if (-not $releases.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe uninstall path.' }
    if (Test-Path -LiteralPath $releases) { Remove-Item -LiteralPath $releases -Recurse -Force }
    Remove-Item -LiteralPath 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/zDrive' -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $root 'Uninstall.ps1') -Force
    # Keep user configuration, credentials and synchronized files.
}
catch {
    Write-Host "Uninstall failed: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
