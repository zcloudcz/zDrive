$ErrorActionPreference = 'Stop'
$work = Join-Path ([IO.Path]::GetTempPath()) ('zDrive-Setup-' + [guid]::NewGuid().ToString('N'))
try {
    $release = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
    $uri = [Uri]$release.url
    if ($uri.Scheme -ne 'https' -or $release.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid installer configuration.' }
    New-Item -ItemType Directory -Path $work | Out-Null
    $archive = Join-Path $work 'payload.zip'
    Write-Host 'Downloading zDrive...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $archive
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $release.sha256) { throw 'Download integrity check failed.' }
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $work 'payload')
    & (Join-Path $work 'payload/Install.ps1')
    Write-Host 'zDrive is installed. Open zDrive from the Start menu.'
    Read-Host 'Press Enter to close'
}
catch {
    Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
finally {
    $boundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ([IO.Path]::GetFullPath($work).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
