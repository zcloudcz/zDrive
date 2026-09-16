# Run in a fresh PowerShell process. Registry and shortcut writes are mocked;
# installation, upgrade, payload validation and uninstall use real temporary files.
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('zDrive-Install-Test-' + [guid]::NewGuid().ToString('N'))
$originalLocalAppData = $env:LOCALAPPDATA
$global:zDriveTestRegistry = @{}
$global:zDriveTestShortcuts = @{}
$global:zDriveTestRunningPath = $null
$global:zDriveTestFailure = $null
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Get-Process { param($Name, $ErrorAction); if ($global:zDriveTestRunningPath) { [pscustomobject]@{ Path = $global:zDriveTestRunningPath } } }
function New-Item {
    param($Path, $ItemType, [switch]$Force)
    if ($Path -like 'HKCU:*') { return }
    Microsoft.PowerShell.Management\New-Item -Path $Path -ItemType $ItemType -Force:$Force
}
function New-ItemProperty {
    param($Path, $Name, $Value, $PropertyType, [switch]$Force)
    Assert ($Path -eq 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/zDrive') 'Unexpected registry key'
    $global:zDriveTestRegistry[$Name] = $Value
}
function Copy-Item {
    param($Path, $LiteralPath, $Destination, [switch]$Recurse, [switch]$Force)
    if ($Destination -like '*.stage-*') {
        if ($global:zDriveTestFailure -eq 'copy') {
            Set-Content -LiteralPath (Join-Path $Destination 'zdrive_app.exe') -Value 'incomplete copy'
            throw 'Injected copy failure'
        }
        if ($global:zDriveTestFailure -eq 'opened') { $global:zDriveTestRunningPath = Join-Path $env:LOCALAPPDATA 'Programs/zDrive/releases/0.2.0/zdrive_app.exe' }
    }
    if ($LiteralPath) { Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Recurse:$Recurse -Force:$Force }
    else { Microsoft.PowerShell.Management\Copy-Item -Path $Path -Destination $Destination -Recurse:$Recurse -Force:$Force }
}
function Move-Item {
    param($LiteralPath, $Destination)
    foreach ($path in @($LiteralPath, $Destination)) {
        Assert ([IO.Path]::GetFullPath($path).StartsWith($fixture.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) 'Unsafe test move'
    }
    if ($LiteralPath -like '*.stage-*' -and $global:zDriveTestFailure -eq 'swap') { throw 'Injected swap failure' }
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
}
function New-Object {
    param($ComObject)
    Assert ($ComObject -eq 'WScript.Shell') 'Unexpected COM object'
    $shell = [pscustomobject]@{}
    $shell | Add-Member -MemberType ScriptMethod -Name CreateShortcut -Value {
        param($path)
        $shortcut = [pscustomobject]@{ Path = $path; TargetPath = ''; WorkingDirectory = ''; IconLocation = '' }
        $shortcut | Add-Member -MemberType ScriptMethod -Name Save -Value { $global:zDriveTestShortcuts[$this.Path] = $this.TargetPath }
        return $shortcut
    }
    return $shell
}
function Remove-Item {
    param($LiteralPath, [switch]$Recurse, [switch]$Force, $ErrorAction)
    if ($LiteralPath -like 'HKCU:*') { $global:zDriveTestRegistry.Clear(); return }
    if ($global:zDriveTestShortcuts.ContainsKey($LiteralPath)) { $global:zDriveTestShortcuts.Remove($LiteralPath); return }
    $resolved = [IO.Path]::GetFullPath($LiteralPath)
    Assert ($resolved.StartsWith($fixture.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) "Unsafe test removal: $resolved"
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Recurse:$Recurse -Force:$Force
}
try {
    $env:LOCALAPPDATA = Join-Path $fixture 'profile'
    $package = Join-Path $fixture 'payload'
    New-Item -ItemType Directory -Path (Join-Path $package 'app/data') -Force | Out-Null
    Copy-Item -Path (Join-Path $repository 'packaging/windows/*.ps1') -Destination $package
    foreach ($file in @('zdrive_app.exe', 'flutter_windows.dll', 'data/icudtl.dat', 'data/app.so', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'plugin.dll')) {
        Set-Content -LiteralPath (Join-Path $package "app/$file") -Value 'version one fixture'
    }
    New-Item -ItemType Directory -Path (Join-Path $env:LOCALAPPDATA 'zdrive_app') -Force | Out-Null
    $userData = Join-Path $env:LOCALAPPDATA 'zdrive_app/settings.json'
    Set-Content -LiteralPath $userData -Value 'preserve me'
    Set-Content -LiteralPath (Join-Path $package 'version.txt') -Value '0.1.0'
    & (Join-Path $package 'Install.ps1')
    $root = Join-Path $env:LOCALAPPDATA 'Programs/zDrive'
    Assert (Test-Path -LiteralPath (Join-Path $root 'releases/0.1.0/plugin.dll')) 'Plugin missing after install'
    Assert ($global:zDriveTestRegistry.DisplayVersion -eq '0.1.0') 'Wrong install version'
    Assert ($global:zDriveTestShortcuts.Count -eq 2) 'Expected two shortcuts'
    $global:zDriveTestRunningPath = Join-Path $root 'releases/0.1.0/zdrive_app.exe'
    try { & (Join-Path $package 'Install.ps1'); throw 'Running app was not rejected' }
    catch { Assert ($_.Exception.Message -like 'Close zDrive*') 'Unexpected running-app error' }
    $global:zDriveTestRunningPath = $null
    Set-Content -LiteralPath (Join-Path $package 'version.txt') -Value '0.2.0'
    Set-Content -LiteralPath (Join-Path $package 'app/zdrive_app.exe') -Value 'version two fixture'
    & (Join-Path $package 'Install.ps1')
    Assert ($global:zDriveTestRegistry.DisplayVersion -eq '0.2.0') 'Upgrade registration failed'
    foreach ($target in $global:zDriveTestShortcuts.Values) { Assert ($target -like '*releases*0.2.0*zdrive_app.exe') 'Shortcut not upgraded' }
    Assert ((Get-Content -LiteralPath (Join-Path $root 'releases/0.2.0/zdrive_app.exe')) -eq 'version two fixture') 'Upgrade did not copy new binary'
    $installedExe = Join-Path $root 'releases/0.2.0/zdrive_app.exe'
    Set-Content -LiteralPath (Join-Path $package 'app/zdrive_app.exe') -Value 'reinstalled version two'
    $shortcutsBefore = @{} + $global:zDriveTestShortcuts
    foreach ($failure in @('copy', 'swap', 'opened')) {
        $global:zDriveTestFailure = $failure
        try { & (Join-Path $package 'Install.ps1'); throw 'Reinstall failure was not detected' }
        catch { Assert ($_.Exception.Message -like 'Injected * failure' -or $_.Exception.Message -like 'Close zDrive*') "Unexpected reinstall error: $_" }
        $global:zDriveTestFailure = $null
        $global:zDriveTestRunningPath = $null
        Assert ((Get-Content -LiteralPath $installedExe) -eq 'version two fixture') "Failed $failure reinstall damaged original executable"
        foreach ($shortcut in $shortcutsBefore.Keys) {
            Assert ($global:zDriveTestShortcuts[$shortcut] -eq $shortcutsBefore[$shortcut]) "Failed $failure reinstall changed shortcut"
            Assert (Test-Path -LiteralPath $global:zDriveTestShortcuts[$shortcut]) 'Shortcut target no longer exists'
        }
        Assert (@(Get-ChildItem -LiteralPath (Join-Path $root 'releases') -Force | Where-Object Name -like '.*').Count -eq 0) 'Failure left staging or backup directories'
        Assert ($global:zDriveTestRegistry.DisplayVersion -eq '0.2.0') 'Failed reinstall changed registration'
    }
    & (Join-Path $package 'Install.ps1')
    Assert ((Get-Content -LiteralPath $installedExe) -eq 'reinstalled version two') 'Same-version reinstall did not update executable'
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $root 'releases') -Force | Where-Object Name -like '.*').Count -eq 0) 'Successful reinstall left staging or backup directories'
    Remove-Item -LiteralPath (Join-Path $package 'app/flutter_windows.dll') -Force
    Set-Content -LiteralPath (Join-Path $package 'version.txt') -Value '0.3.0'
    try { & (Join-Path $package 'Install.ps1'); throw 'Incomplete package was accepted' }
    catch { Assert ($_.Exception.Message -like 'Incomplete package:*') 'Unexpected validation error' }
    Assert ($global:zDriveTestRegistry.DisplayVersion -eq '0.2.0') 'Failed upgrade changed installed version'
    Assert (-not (Test-Path -LiteralPath (Join-Path $root 'releases/0.3.0'))) 'Failed upgrade created release directory'
    & (Join-Path $root 'Uninstall.ps1')
    Assert (-not (Test-Path -LiteralPath (Join-Path $root 'releases'))) 'Uninstall left binaries'
    Assert ($global:zDriveTestRegistry.Count -eq 0) 'Uninstall left registry entry'
    Assert ($global:zDriveTestShortcuts.Count -eq 0) 'Uninstall left shortcuts'
    Assert ((Get-Content -LiteralPath $userData) -eq 'preserve me') 'Uninstall removed user data'
    'PASS: install, running-app guards, upgrade, same-version copy/swap rollback, reinstall, invalid payload and uninstall; user data preserved.'
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $boundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ([IO.Path]::GetFullPath($fixture).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name zDriveTestRegistry, zDriveTestShortcuts, zDriveTestRunningPath, zDriveTestFailure -Scope Global -ErrorAction SilentlyContinue
}
