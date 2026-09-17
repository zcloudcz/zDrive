[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$required = @(
    'ANDROID_KEYSTORE_BASE64',
    'ANDROID_KEYSTORE_PASSWORD',
    'ANDROID_KEY_ALIAS',
    'ANDROID_KEY_PASSWORD'
)

$missing = @($required | Where-Object { [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) })
if ($missing.Count -gt 0) {
    throw "Android signing requires these environment variables: $($missing -join ', ')"
}

try {
    $keystoreBytes = [Convert]::FromBase64String($env:ANDROID_KEYSTORE_BASE64)
} catch {
    throw 'ANDROID_KEYSTORE_BASE64 is not valid Base64.'
}

if ($keystoreBytes.Length -eq 0) {
    throw 'ANDROID_KEYSTORE_BASE64 must contain a non-empty keystore.'
}

$runnerTemp = $env:RUNNER_TEMP
if ([string]::IsNullOrWhiteSpace($runnerTemp)) {
    $runnerTemp = [IO.Path]::GetTempPath()
}

$outputDirectory = Join-Path $runnerTemp 'zdrive-signing'
$outputPath = Join-Path $outputDirectory 'upload.jks'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
[IO.File]::WriteAllBytes($outputPath, $keystoreBytes)

if ($IsWindows) {
    $acl = Get-Acl -LiteralPath $outputPath
    $acl.SetAccessRuleProtection($true, $false)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        $identity,
        [Security.AccessControl.FileSystemRights]::FullControl,
        [Security.AccessControl.AccessControlType]::Allow
    )
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $outputPath -AclObject $acl
} else {
    [IO.File]::SetUnixFileMode(
        $outputPath,
        [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite
    )
}

$env:ZDRIVE_ANDROID_KEYSTORE_PATH = $outputPath
if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_ENV)) {
    Add-Content -LiteralPath $env:GITHUB_ENV -Value "ZDRIVE_ANDROID_KEYSTORE_PATH=$outputPath"
}

Write-Output "Android signing keystore prepared at $outputPath"
