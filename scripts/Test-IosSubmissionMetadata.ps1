$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$plistPath = Join-Path $root 'src/client/zdrive_app/ios/Runner/Info.plist'
$projectPath = Join-Path $root 'src/client/zdrive_app/ios/Runner.xcodeproj/project.pbxproj'
$podfilePath = Join-Path $root 'src/client/zdrive_app/ios/Podfile'

[xml]$plist = Get-Content -LiteralPath $plistPath -Raw
$dictionary = $plist.plist.dict
$purposeNode = $dictionary.SelectSingleNode("key[text()='NSPhotoLibraryUsageDescription']/following-sibling::*[1]")
if ($null -eq $purposeNode) { throw 'NSPhotoLibraryUsageDescription is required for the photo picker dependency.' }
$purpose = $purposeNode.InnerText.Trim()
if ($purpose.Length -lt 20) { throw 'NSPhotoLibraryUsageDescription must clearly explain the user-facing purpose.' }

# Without this key, App Store Connect holds every build in "Missing Compliance"
# until someone answers the encryption question by hand, so TestFlight builds
# never reach testers automatically. The app only uses exempt encryption
# (HTTPS/TLS via the OS and standard hashing), so this must stay false.
$encryptionNode = $dictionary.SelectSingleNode("key[text()='ITSAppUsesNonExemptEncryption']/following-sibling::*[1]")
if ($null -eq $encryptionNode) { throw 'ITSAppUsesNonExemptEncryption is required to avoid manual App Store Connect export-compliance review.' }
if ($encryptionNode.LocalName -ne 'false') { throw 'ITSAppUsesNonExemptEncryption must be false.' }

$project = Get-Content -LiteralPath $projectPath -Raw
if (($project | Select-String -AllMatches 'IPHONEOS_DEPLOYMENT_TARGET = 15\.0;').Matches.Count -ne 3) {
    throw 'Every Runner configuration must use iOS 15.0.'
}
$podfile = Get-Content -LiteralPath $podfilePath -Raw
if ($podfile -notmatch "platform :ios, '15\.0'") { throw 'Podfile must use iOS 15.0.' }

Write-Output 'PASS: iOS photo permission text, export-compliance key, and minimum iOS 15.0 are configured.'
