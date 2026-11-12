# NearLink 0.3.9 Online-First Lists

Date: 2026-11-12. Application version: `0.3.9+24`.

## Resulting Behavior

- Windows and Android conversations prioritize current availability before
  message/file recency. A recently active offline device no longer displaces an
  online device, including online devices with no conversation history. Existing
  recency and name rules continue within each availability state.
- Groups rank with online conversations only while active and with another
  member online. Groups with only the local member online, and left/dissolved
  groups, rank with offline conversations. Presence updates reorder the list
  without changing the selected chat or its draft.
- Nearby devices and forwarding selectors reuse the same availability comparison.
  Quick Send retains its online-device filter and valid group choices; groups
  with other online members precede groups whose other members are all offline.
  Existing group-editor online-first ordering is preserved.
- Group details show online members first, preserving original order within each
  state and leaving the stored group membership untouched. These are presentation
  changes; transfer history and unread-notification chronology retain their order.

## Verification

- Full `flutter test --no-pub`: 244 passed, 2 skipped. The existing optional
  Android screenshot review and opt-in real LAN discovery tests remain skipped.
- Six new widget tests cover Windows at 1440/720 and Android at 390/1024, plus
  recipient/device lists and live group-member ordering. Cases include newer
  offline history, online devices without history, live presence changes,
  left/dissolved groups, retained unread messages, selected chats and drafts.
- Four fixture screenshots were captured and reviewed: Windows 1440/720 and
  Android phone/tablet 390/1024. Fixtures do not advertise devices to the LAN.
- `flutter analyze --no-pub`: no issues. `git diff --check`: passed. The layout
  detector returned no findings.
- Windows Release, ZIP and installer builds passed. Product version is
  `0.3.9+24`. All 26 non-PDB Release files match the package; all 44 ZIP files and
  44 extracted installer payload files match it by SHA-256. No local runtime
  configuration, history, logs or tests were found in the package audit.
- Android Release build passed. Manifest versionName is `0.3.9`, versionCode is
  `24`. APK v2 signature verification passed with the existing development signer
  SHA-256 `c6062e6446f539d94931063cb0ca69faf58c8fe75e8c2d1c74055b3c5d57953a`.
  No runtime profiles, history, logs or tests matched among the 86 APK entries.

Evidence is from automated tests, fixture renders and package inspection, not a
new native installation or physical-device presence test. No running application
was stopped or replaced, and no installer was executed. Windows remains unsigned;
Android retains its existing development signer. Existing Kotlin migration
warnings do not prevent the Android build. Real LAN discovery was not run.

## Artifacts

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.9-windows-x64-Setup.exe | 13755322 | B40F6716F564DF79B9722D56333888D81DB7E72034D3D03E1144FEFB92663558 |
| NearLink-0.3.9-windows-x64.zip | 16345754 | EEDA58C7D6632D614BE9438C3370FD1AF7B048381E15A94685352D12E1D65A7D |
| NearLink-0.3.9-android-preview.apk | 55989204 | EFF71B37A5DBFC4DFAF4E3386BE3DF72875F7191BAA6F7D0E820E16D43075202 |

Checksums are also in `outputs/NearLink-0.3.9-SHA256SUMS.txt`.
