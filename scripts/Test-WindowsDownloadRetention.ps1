$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('zDrive-Downloads-Test-' + [guid]::NewGuid().ToString('N'))
$global:zDriveDownloadTestCalls = @()
$global:zDriveDownloadTestFail = $false
function gh {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'api') {
        return '[[{"tag_name":"v0.1.0","draft":false,"assets":[{"name":"zDrive-0.1.0-windows-x64.zip"},{"name":"zDrive-0.1.0-Setup.exe"}]}],[{"tag_name":"v0.2.0","draft":false,"assets":[{"name":"zDrive-0.2.0-windows-x64.zip"},{"name":"zDrive-0.2.0-Setup.exe"}]},{"tag_name":"v0.3.0","draft":true,"assets":[]}]]'
    }
    $global:zDriveDownloadTestCalls += $args[2]
    if ($global:zDriveDownloadTestFail) { $global:LASTEXITCODE = 1 }
}
try {
    $include = Join-Path $PSScriptRoot 'Include-WindowsDownloads.ps1'
    & $include -Repository zcloudcz/zDrive -Version 0.2.0 -OutputDirectory $fixture
    if (($global:zDriveDownloadTestCalls -join ',') -ne 'v0.1.0,v0.2.0') { throw 'Historical versions were not retained or a draft was included.' }
    $rejected = $false
    try { & $include -Repository zcloudcz/zDrive -Version 0.4.0 -OutputDirectory $fixture }
    catch { $rejected = $_.Exception.Message -like '*incomplete or missing*' }
    if (-not $rejected) { throw 'Missing required release was accepted.' }
    $global:zDriveDownloadTestFail = $true
    $rejected = $false
    try { & $include -Repository zcloudcz/zDrive -Version 0.2.0 -OutputDirectory $fixture }
    catch { $rejected = $_.Exception.Message -like 'Could not download*' }
    if (-not $rejected) { throw 'Download failure was ignored.' }
    Write-Output 'PASS: release pagination, historical retention, draft exclusion, required version and download failure.'
}
finally {
    $boundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ([IO.Path]::GetFullPath($fixture).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $fixture)) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
    Remove-Variable zDriveDownloadTestCalls, zDriveDownloadTestFail -Scope Global
}
