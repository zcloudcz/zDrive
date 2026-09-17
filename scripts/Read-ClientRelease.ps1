$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$line = Get-Content (Join-Path $root 'src/client/zdrive_app/pubspec.yaml') | Where-Object { $_ -match '^version:' }
if ($line -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'Expected version X.Y.Z+build in pubspec.yaml' }
$version = $Matches[1]
$publish = $env:GITHUB_EVENT_NAME -ne 'pull_request' -and $env:GITHUB_REF -like 'refs/tags/*'
$tag = ''
if ($publish) {
    $tag = $env:GITHUB_REF.Substring('refs/tags/'.Length)
    if ($tag -ne "v$version") { throw 'Release tag must match pubspec.yaml version' }
    git fetch origin master
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch trusted master branch' }
    git merge-base --is-ancestor HEAD origin/master
    if ($LASTEXITCODE -ne 0) { throw 'Only reviewed commits merged into master can be released' }
}
@("version=$version", "publish=$($publish.ToString().ToLowerInvariant())", "tag=$tag") | Add-Content -LiteralPath $env:GITHUB_OUTPUT
