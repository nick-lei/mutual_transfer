# NearLink 0.3.8 Separate Home Transfer Cards

Date: 2026-11-11. Application version: `0.3.8+23`.

## Resulting Behavior

- Windows Home's transfer activity uses the same independent white cards as
  History: 8 px corners, 12 px gaps and 18 px horizontal content padding. A shared
  card builder prevents the two lists from drifting apart. The enclosing white
  list surface is removed when records exist, exposing the page canvas between
  records. The existing empty-state surface is retained.
- Device/group identity, status, progress, retry and received-file actions remain
  available. Full timestamps stay right-aligned on the same row as the error or
  size/speed. Home retains its existing active-first order and four-record limit.
- Android already uses individual transfer cards. Its existing layout is
  preserved, and the package version is synchronized with Windows.

## Verification

- Six focused widget tests passed: Home activity and History at widths
  1440/720/440, with 1.3 text scale at 440. The new Home cases check separate
  same-name records, visible card gaps, same-row right-aligned timestamps, retry
  availability and navigation to History. Existing History regression cases pass.
- Fixture screenshots were captured at all three widths. Wide and narrow Home
  captures were visually reviewed. The layout detector returned no findings.
- `flutter analyze --no-pub`: no issues. `git diff --check`: passed. The full
  test suite was not rerun for this scoped visual change. No real LAN discovery
  tests were run; fixtures do not advertise devices.
- Windows Release, portable ZIP and installer builds passed. Product version is
  `0.3.8+23`. All 26 non-PDB Release files match the package; all 44 ZIP files and
  44 extracted installer files match it by SHA-256. No runtime configuration,
  history, logs or test files were found in the package audit.
- Android Release build passed. Manifest versionName is `0.3.8`, versionCode is
  `23`. APK v2 signature verification passed with the existing development signer
  SHA-256 `c6062e6446f539d94931063cb0ca69faf58c8fe75e8c2d1c74055b3c5d57953a`.
  No runtime profiles, history, logs or tests matched among the 86 APK entries.

Verification uses widget fixtures and package inspection. This pass did not
install or launch the new native builds, perform a physical-device transfer,
execute an installer or replace a running application. Windows remains unsigned;
Android keeps its existing local development signer. Existing Kotlin migration
warnings do not prevent the Android build.

## Artifacts

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.8-windows-x64-Setup.exe | 13755058 | 71F001CBB0C668E6DC8C23AEF0F71AE4ADB10D31BBF36CB3B5E312BD248BA6E6 |
| NearLink-0.3.8-windows-x64.zip | 16345197 | F8F40DFB43A81B5E75494C3DF6477894A8EFF2459F8E52D4A91D57133545A1AA |
| NearLink-0.3.8-android-preview.apk | 55989204 | DF702D89D9F1DCCF0CF10C9609DEC8A6BDDBCE0EA3D08D6B4A70066E6A9E7AB7 |

Checksums are also in `outputs/NearLink-0.3.8-SHA256SUMS.txt`.
