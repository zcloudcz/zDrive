#!/usr/bin/env bash
# Build the Flutter iOS app for CI. Signed builds require an App Store
# distribution certificate and an explicit provisioning profile supplied by CI.
set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly APP_DIR="${REPO_ROOT}/src/client/zdrive_app"
readonly IOS_DIR="${APP_DIR}/ios"
readonly BUNDLE_ID="cz.zcloud.zdriveApp"
readonly DEFAULT_API_BASE_URL="https://zdrive-gateway.azurewebsites.net/api/v1"

die() { echo "Build-IosRelease: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "required command is missing: $1"; }

IOS_SIGNED="${IOS_SIGNED:-false}"
API_BASE_URL="${API_BASE_URL:-${DEFAULT_API_BASE_URL}}"
# Native Entra sign-in (ADR 0003) — empty (unset) keeps the button hidden,
# same gate as the other client builds.
ENTRA_CLIENT_ID="${ENTRA_CLIENT_ID:-}"
ENTRA_API_SCOPE="${ENTRA_API_SCOPE:-}"
case "${IOS_SIGNED}" in
  false|true) ;;
  *) die "IOS_SIGNED must be exactly true or false" ;;
esac

require_command flutter
require_command base64
require_command security
require_command xcodebuild
require_command plutil

cd -- "${APP_DIR}"
flutter pub get --enforce-lockfile

if [[ ! -f ios/Podfile ]]; then
  die "ios/Podfile is missing"
fi
if command -v pod >/dev/null 2>&1; then
  pod install --project-directory="${IOS_DIR}"
else
  die "required command is missing: pod"
fi

readonly DART_DEFINES=(
  "--dart-define=API_BASE_URL=${API_BASE_URL}"
  "--dart-define=ENTRA_CLIENT_ID=${ENTRA_CLIENT_ID}"
  "--dart-define=ENTRA_API_SCOPE=${ENTRA_API_SCOPE}"
)

if [[ "${IOS_SIGNED}" == "false" ]]; then
  flutter build ios --release --no-codesign "${DART_DEFINES[@]}"
  [[ -d build/ios/iphoneos/Runner.app ]] || die "unsigned Runner.app was not produced"
  echo "Unsigned validation app: ${APP_DIR}/build/ios/iphoneos/Runner.app"
  exit 0
fi

for variable in IOS_CERTIFICATE_BASE64 IOS_CERTIFICATE_PASSWORD IOS_PROVISION_PROFILE_BASE64 IOS_TEAM_ID; do
  [[ -n "${!variable:-}" ]] || die "${variable} is required when IOS_SIGNED=true"
done

require_command openssl
require_command /usr/libexec/PlistBuddy

RUNNER_TEMP_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
mkdir -p -- "${RUNNER_TEMP_DIR}"
TEMP_ROOT="$(mktemp -d "${RUNNER_TEMP_DIR%/}/zdrive-ios.XXXXXX")"
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
KEYCHAIN_PATH="${TEMP_ROOT}/zdrive-signing.keychain-db"
CERTIFICATE_PATH="${TEMP_ROOT}/certificate.p12"
PROFILE_PATH="${TEMP_ROOT}/profile.mobileprovision"
PROFILE_PLIST="${TEMP_ROOT}/profile.plist"
INSTALLED_PROFILE=""
PBXPROJ_PATH="${IOS_DIR}/Runner.xcodeproj/project.pbxproj"
PBXPROJ_BACKUP="${TEMP_ROOT}/project.pbxproj"

cleanup() {
  set +e
  [[ -n "${INSTALLED_PROFILE}" ]] && rm -f -- "${INSTALLED_PROFILE}"
  security delete-keychain "${KEYCHAIN_PATH}" >/dev/null 2>&1 || true
  rm -f -- "${CERTIFICATE_PATH}" "${PROFILE_PATH}" "${PROFILE_PLIST}" "${TEMP_ROOT}/ExportOptions.plist"
  if [[ -f "${PBXPROJ_BACKUP}" ]]; then
    cp -- "${PBXPROJ_BACKUP}" "${PBXPROJ_PATH}"
  fi
  rm -rf -- "${TEMP_ROOT}"
}
trap cleanup EXIT

printf '%s' "${IOS_CERTIFICATE_BASE64}" | base64 -D >"${CERTIFICATE_PATH}"
printf '%s' "${IOS_PROVISION_PROFILE_BASE64}" | base64 -D >"${PROFILE_PATH}"

security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security import "${CERTIFICATE_PATH}" -P "${IOS_CERTIFICATE_PASSWORD}" -A -t cert -f pkcs12 -k "${KEYCHAIN_PATH}" >/dev/null
security set-key-partition-list -S apple-tool:,apple: -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}" >/dev/null
security list-keychain -d user -s "${KEYCHAIN_PATH}"

security cms -D -i "${PROFILE_PATH}" -o "${PROFILE_PLIST}"
PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "${PROFILE_PLIST}")"
PROFILE_TEAM="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "${PROFILE_PLIST}")"
PROFILE_APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "${PROFILE_PLIST}")"
[[ "${IOS_TEAM_ID}" =~ ^[A-Za-z0-9]{10}$ ]] || die "IOS_TEAM_ID must be 10 alphanumeric characters"
[[ "${PROFILE_UUID}" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]] || die "provisioning profile UUID is invalid"
[[ "${PROFILE_TEAM}" == "${IOS_TEAM_ID}" ]] || die "provisioning profile team does not match IOS_TEAM_ID"
[[ "${PROFILE_APP_ID}" == "${IOS_TEAM_ID}.${BUNDLE_ID}" ]] || die "provisioning profile application identifier must be ${IOS_TEAM_ID}.${BUNDLE_ID}"

PROFILE_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p -- "${PROFILE_DIR}"
INSTALLED_PROFILE="${PROFILE_DIR}/${PROFILE_UUID}.mobileprovision"
cp -- "${PROFILE_PATH}" "${INSTALLED_PROFILE}"

SIGNING_IDENTITY="$(security find-identity -v -p codesigning "${KEYCHAIN_PATH}" | awk '/^[[:space:]]*[0-9]+\)/ { print $2; exit }')"
[[ "${SIGNING_IDENTITY}" =~ ^[A-Fa-f0-9]{40}$ ]] || die "no valid code-signing identity hash found in imported certificate"
[[ -n "${SIGNING_IDENTITY}" ]] || die "no code-signing identity found in imported certificate"

flutter build ios --release --no-codesign --config-only "${DART_DEFINES[@]}"
ARCHIVE_PATH="${APP_DIR}/build/ios/archive/Runner.xcarchive"
EXPORT_DIR="${APP_DIR}/build/ios/ipa"
EXPORT_OPTIONS="${TEMP_ROOT}/ExportOptions.plist"
mkdir -p -- "${EXPORT_DIR}"

cp -- "${PBXPROJ_PATH}" "${PBXPROJ_BACKUP}"
require_command ruby
ruby -r xcodeproj -e '
  path, team, identity, profile = ARGV
  project = Xcodeproj::Project.open(File.dirname(path))
  target = project.targets.find { |candidate| candidate.name == "Runner" }
  abort "Runner target not found" unless target
  target.build_configurations.each do |configuration|
    next unless configuration.name == "Release"
    settings = configuration.build_settings
    settings["CODE_SIGN_STYLE"] = "Manual"
    settings["DEVELOPMENT_TEAM"] = team
    settings["CODE_SIGN_IDENTITY"] = identity
    settings["PROVISIONING_PROFILE_SPECIFIER"] = profile
  end
  project.save
' "${PBXPROJ_PATH}" "${IOS_TEAM_ID}" "${SIGNING_IDENTITY}" "${PROFILE_UUID}"

xcodebuild archive \
  -workspace "${IOS_DIR}/Runner.xcworkspace" \
  -scheme Runner \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  -destination 'generic/platform=iOS' \
  | tee "${TEMP_ROOT}/xcodebuild-archive.log"

cat >"${EXPORT_OPTIONS}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>signingStyle</key><string>manual</string>
<key>teamID</key><string>${IOS_TEAM_ID}</string>
<key>provisioningProfiles</key><dict>
<key>${BUNDLE_ID}</key><string>${PROFILE_UUID}</string>
</dict>
</dict></plist>
EOF

xcodebuild -exportArchive -archivePath "${ARCHIVE_PATH}" -exportPath "${EXPORT_DIR}" -exportOptionsPlist "${EXPORT_OPTIONS}" \
  | tee "${TEMP_ROOT}/xcodebuild-export.log"
compgen -G "${EXPORT_DIR}/*.ipa" >/dev/null || die "signed IPA was not produced"
echo "Signed IPA: ${EXPORT_DIR}"
