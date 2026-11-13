# NearLink 0.3.11 Android APK Installation

Date: 2026-11-13. Application version: `0.3.11+26`.

## Resulting Behavior

- Android declares `android.permission.REQUEST_INSTALL_PACKAGES`. Explicitly
  opening an APK from a chat or received-file record checks the per-source
  installation permission before invoking the system package installer.
- If permission is missing, the app opens its own
  `ACTION_MANAGE_UNKNOWN_APP_SOURCES` settings page. Returning rechecks the actual
  permission rather than the settings activity's result code, then opens the
  originally chosen APK once. Denial reports a readable error and permits retry.
- The installer receives a FileProvider content URI, explicit APK MIME type and
  temporary read access. The original file is revalidated after permission
  settings, retaining the existing canonical-path and file-availability checks.
- Concurrent permission requests cannot replace the pending APK. Missing system
  handlers and unavailable files report errors. Process death discards the pending
  action; the user must open the APK again after restarting the app.
- Receiving and sharing APKs never initiate installation. Ordinary files retain
  their existing open/share flow. The Android system still owns installation
  confirmation, signature/version checks and manufacturer restrictions.

## Verification

- Full `flutter test --no-pub`: 256 passed, 2 skipped. Optional Android capture
  and opt-in real LAN discovery remain skipped.
- Two new Android host tests verify explicit open-file routing and readable
  native permission errors.
- `tool/test_android_install.ps1`: 8 Kotlin/JUnit tests passed, 0 failures/errors.
  They cover existing authorization, grant-and-return, denial/retry, concurrent
  requests, file disappearance during settings, missing settings, unavailable
  installer and unsolicited/repeated activity returns. The test report is in
  `build/app/test-results/testDebugUnitTest/`.
- `flutter analyze --no-pub`: no issues. Dart formatting and `git diff --check`
  passed. The test-only JUnit dependency does not become a release dependency.
- Android Release build passed. `aapt dump badging` confirms package
  `app.nearlink.mutual_transfer`, versionName `0.3.11`, versionCode `26`, minSdk
  `26`, targetSdk `36`, and the installation permission in the built manifest.
- APK v2 signature verification passed. Certificate SHA-256 remains
  `c6062e6446f539d94931063cb0ca69faf58c8fe75e8c2d1c74055b3c5d57953a`, matching
  the previous preview package. No runtime profiles, history, logs or test paths
  matched among the 86 archive entries.

The initial unit-test run requested a release test task unavailable in this
configuration; the script now uses the existing debug unit-test task. A subsequent
debug engine dependency download stalled; the completed native tests and release
build used the `https://storage.flutter-io.cn` Flutter artifact mirror through a
process-local environment variable. No global repository settings were changed.
Existing Android/Kotlin migration warnings remain unrelated to this change.

No connected Android device or emulator was available. These checks verify the
application logic, compilation and package contents, not physical-device settings
navigation or a completed system installation. No installed app was replaced.
No system installation permission was changed, and real LAN discovery was not run.
This release builds an Android APK only; no new Windows installer was generated.

## First Upgrade From Older Versions

Versions without the installation permission may be unable to open this update
in-app. Save the new APK to the phone and install it once through the system file
manager (or a browser download). After upgrading, opening another APK in NearLink
can use the new per-source permission flow. The system requires the user to
enable the permission and confirm installation; it is not granted silently.

## Artifact

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.11-android-preview.apk | 55989240 | 30795D700253107882A644EE4D37AFC529FFC8D48A28776F9E0F639686BDAED4 |

Checksum: `outputs/NearLink-0.3.11-SHA256SUMS.txt`.
