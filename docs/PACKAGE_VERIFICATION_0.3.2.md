# NearLink 0.3.2 Device Cleanup And Package Verification

Date: 2026-11-09. Application version: `0.3.2+17`.

## Device Cleanup

The service previously retained discovered device identities indefinitely. A
confirmed source of extra records was the native UDP integration test, which
created temporary identities and advertised them to the real LAN. One screenshot
entry named `Android verification peer` also matched a local verification
profile. This evidence does not establish the origin of every offline record.
Installers do not contain the runtime device database; upgrades retain existing
application data.

Windows and Android now provide a trash icon on the Devices page. A confirmation
dialog previews the eligible devices. Cleanup protects online, manually connected,
remarked and history/group-related devices, along with pending transfers and live
chat connections. It rechecks the previewed IDs after backup I/O and never adds
unpreviewed IDs. Settings are backed up before removal; backup/storage failures
propagate to the UI. Cleanup writes settings only, preserving history and files.

`tool/cleanup_offline_devices.ps1` supports read-only preview and explicit `-Apply`
for inactive Windows profiles. It respects the service's byte-range profile lock,
backs up original settings bytes, and never rewrites history. The script is a
repository maintenance tool and is not distributed in the installer.

The native UDP integration test is opt-in with
`--dart-define=RUN_LAN_DISCOVERY_TEST=true`; run it only on an isolated test LAN.
Default test runs retain fake-socket discovery coverage without real broadcasts.

## Verification

- Full Flutter suite: 192 passed, 2 skipped. Skips are the optional Android
  screenshot capture and the now opt-in native LAN discovery integration test.
- Five cleanup regressions cover protected records/files, backup persistence,
  state changes after preview, backup/storage failure, the live-profile lock,
  maintenance preview/apply, and UTF-8 remarks under Windows PowerShell.
- Windows layout checks at 1440 and 440 logical pixels; Android at 390 and 320.
  Narrow cases use 1.3 text scale. Preview, cancel and confirm flows pass. Screenshots
  were inspected for content/action clipping and compatibility with the theme.
- `flutter analyze --no-pub`: no issues found. `git diff --check`: passed.
- One accessible, unlocked local profile contained 9 eligible records. After a
  backup and cleanup it contained 0; device identity, name and receive directory
  were unchanged, and the history SHA-256 was unchanged. This was not verified to
  be the 56-entry profile shown by the user. That profile still needs cleanup in
  the upgraded app on its owning device.
- Windows Release, portable ZIP and Inno Setup installer builds passed. Binary
  product version is `0.3.2+17`. All 26 non-PDB Release files match the packaging
  directory; all 44 ZIP files and all 44 extracted installer payload files match
  that directory by SHA-256. No runtime settings, history, logs or test data were
  present in the payload.
- Android Release build passed. APK manifest versionName is `0.3.2`, versionCode
  is `17`. APK v2 signature verification passed and its local development signer
  matches 0.3.1. The 86 archive entries contain no runtime settings, history, logs
  or test data.

No existing Windows application instance was stopped or replaced, and the Windows
installer verification script was not run. No installation or native interactive
cleanup on a running user profile was performed. The Windows installer has no
publisher code signature. Existing Kotlin migration warnings concern a future
Flutter upgrade and did not prevent the Android build.

## Artifacts

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.2-windows-x64-Setup.exe | 13737409 | D66BB210A28CAFB8755F611EDF169216EE55247A755833459ACFB3BDB3291BF6 |
| NearLink-0.3.2-windows-x64.zip | 16319183 | B8C66FE27308A47C59152A28D31A14BD6B13FDE17D99A44A5BAFDD37DA6F3277 |
| NearLink-0.3.2-android-preview.apk | 55546836 | BAD758E02C9025FC2F0A47881CBF2BA623CC0BA4CCEF0C31A9299F7CF0D26513 |

Checksums are also in `outputs/NearLink-0.3.2-SHA256SUMS.txt`.
