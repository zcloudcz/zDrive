# Mobile and desktop client releases

This runbook covers releases from `pubspec.yaml` through the GitHub Release and
the web deployment. It applies to the Flutter client in
`src/client/zdrive_app`.

## Release operator flow

1. Update the client version in `src/client/zdrive_app/pubspec.yaml` to the
   next `X.Y.Z+build` value. The public release version is `X.Y.Z`; the build
   number must also increase according to the normal client versioning policy.
2. Open a reviewed pull request and merge it into `master`. The release
   validator reads the version from the merged checkout and, for a tag release,
   verifies that the tagged commit is an ancestor of `origin/master`.
3. Create the matching tag on the merged commit and push it:

   ```powershell
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. The `Release clients` workflow validates that the tag is exactly
   `vX.Y.Z`, runs `flutter pub get --enforce-lockfile`, `flutter analyze
   --fatal-infos`, and `flutter test`, then builds the clients.
5. After all platform jobs pass, the workflow creates an immutable GitHub
   Release for `vX.Y.Z` with generated notes and the collected packages. It
   then dispatches `deploy-web.yml` on `master` with the same release tag.
6. `deploy-web.yml` builds the web client and adds versioned Windows downloads
   from the GitHub Release to the web bundle. Verify the Pages deployment and
   download links without authentication.

The workflow uses the package identifiers `cz.zcloud.zdriveApp` for iOS and
`cz.zcloud.zdrive_app` for Android. Keep release assets immutable. A release
with an existing tag must not be overwritten or have its public assets
replaced.

## What the release workflow builds

For a pushed `vX.Y.Z` tag, the workflow builds:

- Windows release output and the versioned installer package.
- A signed Android APK and Play Store AAB, using the production keystore.
- A signed iOS IPA when the repository variable `IOS_SIGNING_ENABLED` is
  `true`. The Apple signing inputs are then required. If the variable is not
  `true`, the workflow builds an unsigned validation bundle instead. This is
  zipped as `zDrive-X.Y.Z-ios-unsigned.zip` for CI validation, then removed
  before the GitHub Release is created. It cannot be installed on an iPhone or
  uploaded to TestFlight.

The `publish` job runs only for a tag event. `gh release create` uses
`--verify-tag`, so it publishes the tag's artifacts and fails instead of
overwriting an existing release. Treat that failure as a signal to stop and
inspect the release, not as a reason to delete or replace public assets.

## Manual runs

Use the Actions UI to run `Release clients` from `master` when a build preview
is needed. A manual run on `master` builds Windows, a debug Android APK, and an
unsigned iOS validation bundle. It runs validation and uploads CI artifacts for
inspection, but does not create a GitHub Release or dispatch the web deploy.

To publish an existing tag that has not yet received a Release, run the same
workflow manually with the workflow ref set to that tag. The tag must match
the version in `pubspec.yaml`, and the tagged commit must already be contained
in `origin/master`. The production jobs then use the signing configuration and
the publish job creates the Release only if it does not already exist. Never
use this path to replace assets in an existing public release.

The web workflow can also be run manually. Set `release_tag` to a published
tag to deploy that version's web client and downloads. Leave it empty to use
`master`; the workflow reads that checkout's version and resolves the matching
published release, whose tag must be an already reviewed release from
`master`. There is no workflow switch that automatically changes repository
visibility. A private GitHub repository does not prevent public binary
downloads when the web site publishes those binaries into its public Pages
bundle. The workflow does not toggle repository or release visibility.

## Required GitHub configuration

Production Android signing requires these repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

`Prepare-AndroidSigning.ps1` decodes the keystore into the runner's temporary
directory. Never commit the keystore or its passwords. Keep a separate backup
of the newly generated upload key outside the repository, for example under
`~/.zdrive/signing/android`.

Production iOS signing requires these repository secrets and variable:

- Secrets: `IOS_CERTIFICATE_BASE64`, `IOS_CERTIFICATE_PASSWORD`,
  `IOS_PROVISION_PROFILE_BASE64`
- Variable: `IOS_TEAM_ID`

Set the repository variable `IOS_SIGNING_ENABLED` to `true` only after the
certificate, provisioning profile, team ID, and Apple setup have been checked.
The build script validates that the profile belongs to team `IOS_TEAM_ID` and
the `cz.zcloud.zdriveApp` bundle ID. Signing material is imported into a
temporary keychain and removed at the end of the job. Never commit certificates,
profiles, private keys, or decoded signing files.

## TestFlight upload

TestFlight upload is an additional opt-in. Set the repository variable
`TESTFLIGHT_ENABLED` to `true` only when iOS signing is enabled and the App
Store Connect API credentials are ready. The workflow requires these three
secrets:

- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`

After validation and all platform builds complete, the separate TestFlight job
can run when both opt-in variables and all App Store Connect secrets are set.
It writes the private key to a temporary runner directory and uploads the
single signed IPA with `xcrun altool`. The first signed IPA upload cannot be
validated or uploaded until Apple Developer enrollment and App Store Connect
credentials exist. Enrollment, signing credentials, and credential
configuration must be confirmed by the release owner before enabling this
path.

Apple Developer Program enrollment is [US$99 per membership year, with local
regional pricing shown during enrollment](https://developer.apple.com/programs/enroll/).
TestFlight supports up to [100 internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)
and [10,000 external testers](https://developer.apple.com/testflight/). Test
builds expire after 90 days. Testers install the TestFlight app and accept an
invitation sent by email or a public link. They do not need UDID registration.
TestFlight provides tester feedback and crash reports through App Store
Connect.

## Post-release checks

Confirm that:

- The GitHub Release is published under the exact `vX.Y.Z` tag and contains
  the expected immutable Windows, Android, and signed iOS assets.
- The unsigned iOS validation ZIP is absent from the public Release assets.
- The Pages deployment used the intended release tag and the public download
  URLs work without a GitHub login.
- Android installation or Play Console upload uses the signed APK or AAB.
- TestFlight shows the uploaded build only when the opt-in variable and all
  three App Store Connect secrets were enabled.
- The release version and build number shown by each client match the change
  reviewed in the pull request.
