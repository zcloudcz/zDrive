param(
    [Parameter(Mandatory)] [string] $ReleaseDirectory,
    [Parameter(Mandatory)] [ValidatePattern('^\d+\.\d+\.\d+(?:\.\d+)?$')] [string] $Version,
    [Parameter(Mandatory)] [Uri] $PayloadUrl,
    [string] $RuntimeDirectory,
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '../build/windows-installer')
)
$ErrorActionPreference = 'Stop'
if ($PayloadUrl.Scheme -ne 'https' -or $PayloadUrl.UserInfo -or $PayloadUrl.Query -or $PayloadUrl.Fragment) {
    throw 'PayloadUrl must be a public immutable HTTPS URL without credentials, query or fragment.'
}
$repository = Split-Path -Parent $PSScriptRoot
$source = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
$work = Join-Path ([IO.Path]::GetTempPath()) ('zDrive-Package-' + [guid]::NewGuid().ToString('N'))
try {
    $package = Join-Path $work 'payload'
    $app = Join-Path $package 'app'
    $bootstrap = Join-Path $work 'bootstrap'
    New-Item -ItemType Directory -Path $app, $bootstrap, $output -Force | Out-Null
    Copy-Item -Path (Join-Path $source '*') -Destination $app -Recurse -Force
    foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $app $dll)) -and $RuntimeDirectory) {
            Copy-Item -LiteralPath (Join-Path $RuntimeDirectory $dll) -Destination $app
        }
    }
    foreach ($file in @('zdrive_app.exe', 'flutter_windows.dll', 'data/icudtl.dat', 'data/app.so', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $app $file) -PathType Leaf)) { throw "Incomplete release: $file (supply RuntimeDirectory for the x64 Visual C++ runtime)." }
    }
    foreach ($file in @('Install.ps1', 'Uninstall.ps1')) {
        Copy-Item -LiteralPath (Join-Path $repository "packaging/windows/$file") -Destination $package
    }
    Set-Content -LiteralPath (Join-Path $package 'version.txt') -Value $Version -Encoding ASCII
    $archive = Join-Path $output "zDrive-$Version-windows-x64.zip"
    Compress-Archive -Path (Join-Path $package '*') -DestinationPath $archive -CompressionLevel Optimal -Force
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    @{ version = $Version; url = $PayloadUrl.AbsoluteUri; sha256 = $hash } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bootstrap 'release.json') -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $repository 'packaging/windows/Bootstrap.ps1') -Destination $bootstrap
    $setup = Join-Path $output "zDrive-$Version-Setup.exe"
    $sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$setup
FriendlyName=zDrive Setup
AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -File Bootstrap.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[SourceFiles]
SourceFiles0=$bootstrap\
[SourceFiles0]
%FILE0%=
%FILE1%=
[Strings]
FILE0="Bootstrap.ps1"
FILE1="release.json"
"@
    $sedPath = Join-Path $work 'setup.sed'
    [IO.File]::WriteAllText($sedPath, ($sed -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
    $process = Start-Process -FilePath "$env:WINDIR/System32/iexpress.exe" -ArgumentList @('/N', '/Q', 'setup.sed') -WorkingDirectory $work -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $setup)) { throw "IExpress failed: $($process.ExitCode)" }
    if ((Get-Item -LiteralPath $setup).Length -gt 5MB) { throw 'Bootstrap installer exceeds 5 MB.' }
    Copy-Item -LiteralPath (Join-Path $bootstrap 'release.json') -Destination (Join-Path $output "zDrive-release-$Version.json") -Force
    foreach ($artifact in @($archive, $setup)) {
        $digest = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
        Set-Content -LiteralPath "$artifact.sha256" -Value "$digest  $([IO.Path]::GetFileName($artifact))" -Encoding ASCII
        Get-Item -LiteralPath $artifact | Select-Object Name, Length, FullName
    }
}
finally {
    $boundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ([IO.Path]::GetFullPath($work).StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}


