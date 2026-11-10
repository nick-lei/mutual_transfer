# NearLink 0.3.4 Chat Drop And Presence Verification

Date: 2026-11-10. Application version: `0.3.4+19`.

## Resulting Behavior

- Desktop chat accepts files and folders from the OS file manager over the
  selected conversation, including an empty conversation. The drag feedback
  names the recipient. Dropping sends directly and displays existing chat file
  progress without changing the Send queue or message draft.
- Multiple files and folders reuse the existing directory traversal, relative
  paths, deduplication, symlink exclusion and 1000-file limit. The recipient ID
  is captured at drop and resolved again after disk enumeration, so switching
  chats cannot redirect the files. Offline recipients and empty/missing paths
  report an error. A covered conversation cannot receive native drop events.
- Windows and Android conversation previews permanently show readable online or
  offline status with a filled green or hollow gray dot. Status remains visible
  alongside drafts, file previews and unread counts; names retain the first row.
  Group conversations show actual online member counts including the local user,
  only-local-user status, and dissolved/left/removed states.

## Verification

- Full `flutter test --no-pub`: 214 passed, 2 skipped. The skips remain the
  optional Android screenshot review and opt-in real LAN discovery test.
- Ten new interaction tests cover multi-file/folder drop, inline progress,
  preserved drafts and Send queue, recipient changes, offline rejection before
  and during enumeration, missing files, modal-covered targets, and live presence
  with unread counts and group states across Windows and Android layouts.
- `flutter analyze --no-pub`: no issues found. `git diff --check`: passed.
- Widget screenshots were reviewed at desktop widths 1440/1040/720 and phone
  widths 390/320. Narrow phone and 1040-wide desktop cases use 1.3 text scale.
  The capture fixtures do not start real LAN discovery or install test devices.
- Windows Release build passed. Product version is `0.3.4+19`. All 26 non-PDB
  Release files match the package. All 44 ZIP files and all 44 extracted installer
  payload files match the package by SHA-256. No runtime configuration, history,
  logs or test files are included.
- Android Release build passed. APK versionName is `0.3.4`, versionCode is `19`.
  APK v2 signature verification passed and the signer matches 0.3.3. The APK's
  86 entries contain no runtime configuration, history, logs or test data.

Native Windows Explorer dragging and a new physical-phone transfer were not
performed for this change; drop callbacks, routing and rendering were verified
in widget tests. No running application was stopped or replaced. The installer
and `tool/verify_installer.ps1` were not executed. The Windows installer remains
unsigned; Android retains its existing local development signer. Existing
Kotlin future-migration warnings did not prevent the Android build.

## Artifacts

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.4-windows-x64-Setup.exe | 13753047 | D71C1CCE9B75E81D3611E71D5C13E6709F276762A814F3B0BCEEA57999EB14A8 |
| NearLink-0.3.4-windows-x64.zip | 16344873 | E63CA3B52000986A83A79AE2932FE82818A561898F1842BB180101DF89E6356B |
| NearLink-0.3.4-android-preview.apk | 55923668 | 9BFC9A9B8C09A2C6833B45C1AA8F8A1D216B3DD9B60D14C3A35B4548818302EE |

Checksums are also in `outputs/NearLink-0.3.4-SHA256SUMS.txt`.
