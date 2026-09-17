[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'Prepare-AndroidSigning.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('zdrive-signing-test-' + [guid]::NewGuid().ToString('N'))
$originalEnvironment = @{}
$environmentNames = @(
    'ANDROID_KEYSTORE_BASE64',
    'ANDROID_KEYSTORE_PASSWORD',
    'ANDROID_KEY_ALIAS',
    'ANDROID_KEY_PASSWORD',
    'RUNNER_TEMP',
    'GITHUB_ENV',
    'ZDRIVE_ANDROID_KEYSTORE_PATH'
)

function Assert-Condition([bool] $condition, [string] $message) {
    if (-not $condition) { throw $message }
}

function Set-TestEnvironment([hashtable] $values) {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    foreach ($entry in $values.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
    }
}

try {
    foreach ($name in $environmentNames) {
        $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    Set-TestEnvironment @{}
    $missingOutput = (& pwsh -NoProfile -File $scriptPath 2>&1 | Out-String)
    Assert-Condition ($LASTEXITCODE -ne 0) 'Missing signing values were accepted.'
    Assert-Condition ($missingOutput -match 'ANDROID_KEYSTORE_BASE64') 'Missing-value error was unclear.'

    $baseEnvironment = @{
        ANDROID_KEYSTORE_PASSWORD = 'test-store-password'
        ANDROID_KEY_ALIAS = 'test-upload'
        ANDROID_KEY_PASSWORD = 'test-key-password'
        RUNNER_TEMP = $testRoot
        GITHUB_ENV = (Join-Path $testRoot 'github_env')
    }
    Set-TestEnvironment ($baseEnvironment + @{ ANDROID_KEYSTORE_BASE64 = 'invalid-base64' })
    $invalidOutput = (& pwsh -NoProfile -File $scriptPath 2>&1 | Out-String)
    Assert-Condition ($LASTEXITCODE -ne 0) 'Invalid Base64 was accepted.'
    Assert-Condition ($invalidOutput -match 'not valid Base64') 'Invalid Base64 error was unclear.'

    $storeSecret = 'test-store-password'
    $keySecret = 'test-key-password'
    $baseEnvironment.ANDROID_KEYSTORE_BASE64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('fixture-keystore'))
    Set-TestEnvironment $baseEnvironment
    $successOutput = (& pwsh -NoProfile -File $scriptPath 2>&1 | Out-String)
    Assert-Condition ($LASTEXITCODE -eq 0) 'Valid signing preparation failed.'
    $outputPath = Join-Path $testRoot 'zdrive-signing/upload.jks'
    Assert-Condition ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($outputPath)) -eq 'fixture-keystore') 'Keystore bytes changed.'
    Assert-Condition ((Get-Content -Raw -LiteralPath $baseEnvironment.GITHUB_ENV) -match 'ZDRIVE_ANDROID_KEYSTORE_PATH=') 'GITHUB_ENV path is missing.'
    Assert-Condition ($successOutput -notmatch [regex]::Escape($storeSecret) -and $successOutput -notmatch [regex]::Escape($keySecret)) 'Signing secret appeared in output.'

    Write-Output 'PASS: missing values, invalid Base64, valid keystore, GITHUB_ENV path, and secret-safe output.'
} finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
    }
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
