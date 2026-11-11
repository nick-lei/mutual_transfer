# NearLink 0.3.7 Transfer History Layout

Date: 2026-11-11. Application version: `0.3.7+22`.

## Resulting Behavior

- Windows history displays independent file/recipient cards with 8 px corners and
  12 px gaps. Date headings show the full calendar date and record count. Device
  and group names distinguish records that share the same file name.
- Each record retains its full local creation timestamp, `yyyy-MM-dd HH:mm:ss`,
  right-aligned on the same row as the error or size/speed information. There is
  no timestamp-only row. Active transfer speeds do not replace timestamps.
- Android preserves the existing individual file cards and four filters. Device
  and group identity remain visible; size and timestamp share the bottom row,
  with the timestamp aligned right. Its flexible width avoids overflow at
  narrow sizes and larger text settings.
- Existing progress, cancellation, retry and received-file actions are retained.
  Timestamps describe record creation, not file completion.

## Verification

- Full `flutter test --no-pub`: 235 passed, 2 skipped. The existing optional
  Android screenshot review and opt-in real LAN discovery tests remain skipped.
- Five new widget tests cover Windows widths 1440/720/440 and Android widths
  390/320, including 1.3 text scale at the narrowest sizes. They verify separate
  cards for matching file names, recipient/group/result labels, distinct full
  timestamps, right alignment and same-row placement. Timestamps remain visible
  during active speed display, and existing Windows actions remain available.
- Windows and Android fixture screenshots were captured and reviewed. A targeted
  Android screenshot rerun after the final width constraint change passed both
  history cases. Fixtures do not broadcast devices to the LAN.
- `flutter analyze --no-pub`: no issues. `git diff --check`: passed.
- Windows Release, portable ZIP and installer builds passed. Product version is
  `0.3.7+22`. All 26 non-PDB Release files match the package; all 44 ZIP files and
  44 extracted installer payload files match the package by SHA-256. No local
  configuration, history, logs or test files are bundled.
- Android Release build passed. Manifest versionName is `0.3.7`, versionCode is
  `22`. APK v2 signature verification passed with the existing signer SHA-256
  `c6062e6446f539d94931063cb0ca69faf58c8fe75e8c2d1c74055b3c5d57953a`.
  No local configuration, history, logs or test data were found among its 86
  archive entries.

Evidence is from automated tests, fixture renders and package inspection, not a
new native installation or physical-device transfer. No running application was
stopped or replaced, and no installer was executed. Windows remains unsigned;
Android keeps the existing local development signer. Existing Kotlin migration
warnings do not prevent the Android build. Real LAN discovery was not run.

## Artifacts

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.7-windows-x64-Setup.exe | 13756073 | 53AD6F76B5C4585E0030DFC076DCF1409B4C64FD21E4599F5D175DC1AFE38F44 |
| NearLink-0.3.7-windows-x64.zip | 16346931 | 04B583978A4234A90541D4699DC9AFA33D9F19A9A8E85B83C1298C16D5DCDB35 |
| NearLink-0.3.7-android-preview.apk | 55989204 | 326C26CCA7CB2C5567B0399400ADC04E27FC49A13D2FE2D98CDADF99769C9923 |

Checksums are also in `outputs/NearLink-0.3.7-SHA256SUMS.txt`.
