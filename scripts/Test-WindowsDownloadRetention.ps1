$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('zDrive-Downloads-Test-' + [guid]::NewGuid().ToString('N'))
$global:zDriveDownloadTestCalls = @()
$global:zDriveDownloadTestWindowsCalls = @()
$global:zDriveDownloadTestFail = $false
$global:zDriveDownloadTestPartial = $false
function gh {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'api') {
        if ($global:zDriveDownloadTestPartial) {
            return '[[{"tag_name":"v0.1.0","draft":false,"assets":[{"name":"zDrive-0.1.0-windows-x64.zip"}]}]]'
        }
        return '[[{"tag_name":"v0.1.0","draft":false,"assets":[{"name":"zDrive-0.1.0-windows-x64.zip"},{"name":"zDrive-0.1.0-Setup.exe"}]}],[{"tag_name":"v0.2.0","draft":false,"assets":[{"name":"zDrive-0.2.0-windows-x64.zip"},{"name":"zDrive-0.2.0-Setup.exe"},{"name":"zDrive-0.2.0-android.apk"}]},{"tag_name":"v0.3.0","draft":true,"assets":[{"name":"zDrive-0.3.0-windows-x64.zip"},{"name":"zDrive-0.3.0-Setup.exe"}]},{"tag_name":"v0.4.0","prerelease":true,"assets":[{"name":"zDrive-0.4.0-windows-x64.zip"},{"name":"zDrive-0.4.0-Setup.exe"}]},{"tag_name":"v0.5.0","assets":[]}]]'
    }
    $releaseVersion = $args[2].TrimStart('v')
    $apkName = "zDrive-$releaseVersion-android.apk"
    if ($args -contains $apkName) {
        [IO.File]::WriteAllText((Join-Path $fixture "zDrive-$releaseVersion-android.apk"), 'fixture apk payload')
    } else {
        $global:zDriveDownloadTestCalls += $args[2]
        $global:zDriveDownloadTestWindowsCalls += $args[2]
        [IO.File]::WriteAllText((Join-Path $fixture "zDrive-$releaseVersion-windows-x64.zip"), 'fixture payload')
    }
    if ($global:zDriveDownloadTestFail) { $global:LASTEXITCODE = 1 }
}
try {
    $include = Join-Path $PSScriptRoot 'Include-WindowsDownloads.ps1'
    & $include -Repository zcloudcz/zDrive -Version 0.2.0 -OutputDirectory $fixture
    if (($global:zDriveDownloadTestWindowsCalls -join ',') -ne 'v0.1.0,v0.2.0') { throw 'Historical versions were not retained or a draft/prerelease was included.' }
    $apk = Join-Path $fixture 'zDrive-0.2.0-android.apk'
    if (-not (Test-Path -LiteralPath $apk -PathType Leaf) -or (Get-Content -Raw -LiteralPath $apk) -ne 'fixture apk payload') { throw 'Published Android APK was not downloaded.' }
    if (-not (Test-Path -LiteralPath (Join-Path $fixture 'zDrive-0.1.0-windows-x64.zip') -PathType Leaf)) { throw 'Historical Windows download was not retained.' }
    $feed = Get-Content -LiteralPath (Join-Path $fixture 'windows-latest.json') -Raw | ConvertFrom-Json
    if ($feed.version -ne '0.2.0' -or $feed.schemaVersion -ne 1 -or $feed.sizeBytes -ne 15 -or $feed.sha256 -ne (Get-FileHash (Join-Path $fixture 'zDrive-0.2.0-windows-x64.zip')).Hash.ToLowerInvariant()) { throw 'Invalid update feed.' }
    $rejected = $false
    try { & $include -Repository zcloudcz/zDrive -Version 0.4.0 -OutputDirectory $fixture }
    catch { $rejected = $_.Exception.Message -like '*incomplete or missing*' }
    if (-not $rejected) { throw 'Missing required release was accepted.' }
    $global:zDriveDownloadTestFail = $true
    $rejected = $false
    try { & $include -Repository zcloudcz/zDrive -Version 0.2.0 -OutputDirectory $fixture }
    catch { $rejected = $_.Exception.Message -like 'Could not download*' }
    if (-not $rejected) { throw 'Download failure was ignored.' }
    $global:zDriveDownloadTestFail = $false
    $global:zDriveDownloadTestPartial = $true
    $rejected = $false
    try { & $include -Repository zcloudcz/zDrive -Version 0.2.0 -OutputDirectory $fixture }
    catch { $rejected = $_.Exception.Message -like '*incomplete artifact pair*' }
    if (-not $rejected) { throw 'Partial historical release was silently dropped.' }
    Write-Output 'PASS: pagination, historical retention, draft/prerelease exclusion, partial release rejection and download failure.'
}
finally {
    $boundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ([IO.Path]::GetFullPath($fixture).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $fixture)) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
    Remove-Variable zDriveDownloadTestCalls, zDriveDownloadTestWindowsCalls, zDriveDownloadTestFail, zDriveDownloadTestPartial -Scope Global
}
# The last mocked gh call intentionally fails; do not leak its exit code to CI.
$global:LASTEXITCODE = 0
