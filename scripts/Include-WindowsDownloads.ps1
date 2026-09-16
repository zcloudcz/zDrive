param(
    [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')] [string] $Repository,
    [Parameter(Mandatory)] [ValidatePattern('^\d+\.\d+\.\d+$')] [string] $Version,
    [Parameter(Mandatory)] [string] $OutputDirectory
)
$ErrorActionPreference = 'Stop'
$pagesJson = & gh api --paginate --slurp "repos/$Repository/releases"
if ($LASTEXITCODE -ne 0) { throw 'Could not list Windows releases.' }
$pages = ($pagesJson -join "`n") | ConvertFrom-Json
$currentIncluded = $false
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
foreach ($page in $pages) {
    foreach ($release in $page) {
        if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v(\d+\.\d+\.\d+)$') { continue }
        $releaseVersion = $Matches[1]
        $zip = "zDrive-$releaseVersion-windows-x64.zip"
        $setup = "zDrive-$releaseVersion-Setup.exe"
        $names = @($release.assets | ForEach-Object { $_.name })
        if ($zip -notin $names -and $setup -notin $names) { continue }
        if ($zip -notin $names -or $setup -notin $names) {
            throw "Windows release $releaseVersion has an incomplete artifact pair; refusing to drop historical downloads."
        }
        & gh release download $release.tag_name --repo $Repository --pattern $zip --pattern $setup --dir $OutputDirectory
        if ($LASTEXITCODE -ne 0) { throw "Could not download Windows release $releaseVersion." }
        if ($releaseVersion -eq $Version) { $currentIncluded = $true }
    }
}
# Retain every published version: an older installer pins its original ZIP URL.
if (-not $currentIncluded) { throw "Windows release v$Version is incomplete or missing." }
