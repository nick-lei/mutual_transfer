# NearLink 0.3.6 Group File Outcomes

Date: 2026-11-10. Application version: `0.3.6+21`.

## Resulting Behavior

- Group transfers retain independent recipient sessions. A refusal, unreachable
  device, timeout or cancellation affects that recipient, while other recipients
  can continue accepting and receiving the files.
- The sender now gets one result after all recipient sessions settle, including
  mixed and unsuccessful outcomes. Counts distinguish fully completed, rejected,
  incomplete and cancelled recipients. A partially delivered recipient does not
  count as fully completed, and completed files remain available.
- Mixed results use an amber icon and a neutral title on Windows and Android.
  Counts wrap as complete labels on narrow screens. Foreground prompts and
  background notifications retain existing reminder and sound preferences, with
  an action to open history. All-success and direct receive notices are retained.
- Group connection failures show Chinese recovery messages and log the original
  exception with group/recipient IDs. Confirmation timeout now returns HTTP 408
  and counts as incomplete; explicit refusal remains HTTP 409. Older receivers
  can still return 409 for either refusal or timeout, which cannot be distinguished
  by the sender. Upgrade both sides for accurate timeout classification.

## Verification

- Full `flutter test --no-pub`: 230 passed, 2 skipped. The existing optional
  Android screenshot review and opt-in real LAN discovery tests remain skipped.
- Localhost integration tests use temporary profiles and disabled LAN discovery.
  They cover multiple files with one receiver refusing before another accepts,
  unreachable devices marked online/offline, unanswered requests, all receivers
  refusing, partial file failure, individual cancellation and all-success notices.
  Received file contents were checked independently of the result notification.
- Four widget tests verify group results and history navigation on Windows at
  widths 1440/440 and Android at 390/320, including 1.3 text scale on narrow sizes.
  Screenshots were captured and reviewed. Background notification tests verify
  mixed results and notification settings.
- `flutter analyze --no-pub`: no issues. `git diff --check`: passed.
- Windows Release, portable ZIP and installer builds passed. Product version is
  `0.3.6+21`. All 26 non-PDB Release files match the package; all 44 ZIP files and
  44 extracted installer payload files match the package by SHA-256. No local
  configuration, history, logs or test files are bundled.
- Android Release build passed. Manifest versionName is `0.3.6`, versionCode is
  `21`. APK v2 signature verification passed; the signer matches 0.3.5. No local
  configuration, history, logs or test data were found among the APK's 86 entries.

Evidence is from localhost services, automated interactions and fixture captures,
not a new physical-device group transfer. No running application was stopped or
replaced, and no installer was executed. Windows remains unsigned; Android keeps
the existing local development signer. Existing Kotlin migration warnings do not
prevent the current Android build.

## Artifacts

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.6-windows-x64-Setup.exe | 13753704 | 562C7173BE70BC084E45FB34FBEB4339BE6FD360BA58835C835BC2B8011882A7 |
| NearLink-0.3.6-windows-x64.zip | 16346432 | 247FB94507C79CF1026B62DC738A3E1B0B1C977383776B5969D3D022C9688CDA |
| NearLink-0.3.6-android-preview.apk | 55923668 | 7F5F3AA8171FB46B1FE8A6E836224F6B65668D7F40B2D03DEEE3341A7FC03AD9 |

Checksums are also in `outputs/NearLink-0.3.6-SHA256SUMS.txt`.
