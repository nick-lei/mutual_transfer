# NearLink 0.3.5 Inline Group Recipients

Date: 2026-11-10. Application version: `0.3.5+20`.

## Resulting Behavior

- Windows and Android Quick Send list existing group conversations directly
  alongside online devices. Users select a group with the same single-selection
  interaction, blue surface and checked icon used for devices. No intermediate
  group picker is opened. Choosing a device replaces the selected group and vice
  versa; the final send summary names the current recipient.
- Group rows show a group avatar, name, member count and online count including
  the local user. Long names are constrained. The existing group file/message
  services and reconnection behavior are retained.
- Only active groups containing the local user and at least one other member
  are listed. Dissolved, left, removed and self-only groups are excluded. If a
  selected group becomes inactive, sending is disabled and staged files remain.
- The former group-picker icon now creates a new group directly. The existing
  editor and the independent message conversation selection remain available.

## Verification

- Full `flutter test --no-pub`: 219 passed, 2 skipped. Skips remain the optional
  Android screenshot review and opt-in real LAN discovery test.
- Five new interaction tests verify inline selection on Windows at widths
  1440/1000/440 and Android at 390/320, with 1.3 text scale in narrow cases.
  Tests cover no picker, recipient switching, named send target, group metadata,
  invalidation and staged-file retention. Screenshots at these sizes were reviewed.
- `flutter analyze --no-pub`: no issues found. `git diff --check`: passed.
- Windows Release, portable ZIP and installer builds passed. Product version
  is `0.3.5+20`. All 26 non-PDB Release files match the package, and all 44 ZIP
  files and all 44 extracted installer payload files match by SHA-256. No local
  configuration, history, logs or test files are bundled.
- Android Release build passed. Manifest versionName is `0.3.5`, versionCode
  is `20`. APK v2 verification passed and the signer matches 0.3.4. No runtime
  configuration, history, logs or test data were found among the APK's 86 entries.

Verification uses automated interactions and fixture screenshots, not a new
physical-device group transfer. No running application was stopped or replaced;
neither the installer nor `tool/verify_installer.ps1` was executed. The Windows
installer remains unsigned; Android retains the existing local development
signer. Existing Kotlin migration warnings did not prevent the Android build.

## Artifacts

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.5-windows-x64-Setup.exe | 13753158 | 1FFA27F06A65B96A435C0C98440FD4E8C60F7676AB7604472D6BF89CFD0BDDFE |
| NearLink-0.3.5-windows-x64.zip | 16343821 | E1F948C5AEE4DD43EB469A18C5DC8EDEC6CB80CD21EE4822F8E683F2B13D787C |
| NearLink-0.3.5-android-preview.apk | 55907288 | A0F63ED99D067702017093C03597B1544E6D8C519382D3893A1577282EFDDF41 |

Checksums are also in `outputs/NearLink-0.3.5-SHA256SUMS.txt`.
