# NearLink 0.3.10 Windows File Copy

Date: 2026-11-13. Application version: `0.3.10+25`.

## Resulting Behavior

- Windows Home activity and History file cards support single-click selection,
  Ctrl+C and right-click Copy. Escape clears selection. The selected state uses
  the existing blue tint and outline without changing card geometry.
- Copy writes file objects to the Windows system clipboard using Unicode
  CF_HDROP paths and Preferred DropEffect copy. It does not substitute filenames
  or paths as clipboard text. Explorer and other compatible applications can
  consume the standard file clipboard format.
- Sent records copy their local original, including rejected sends. Receives
  require a completed saved file. Missing files and unfinished receives disable
  the context command; keyboard failures show an actionable message. A busy
  clipboard retries asynchronously with a bounded limit.
- Search and other text fields retain ordinary text-copy behavior. This change
  supports one selected file card, not multi-selection. Android retains its
  existing touch interactions and receives the aligned version number.

## Verification

- Full `flutter test --no-pub`: 254 passed, 2 skipped. Default opt-in real LAN
  discovery and optional Android screenshot review tests remain skipped.
- Ten new tests cover API validation/retry handling and Home/History interactions
  at 1440/440 logical pixels. Received and sent paths, rejected originals, Escape,
  text-field isolation, unavailable files and incomplete receives are covered.
  A strengthened incomplete-receive case was rerun after the full suite with an
  existing local fixture and a disabled context command; it passed.
- Eight synthetic fixture screenshots were captured with real shadows and
  visually reviewed. See `.impeccable/review/file-copy-verification.md` for the
  evidence and native test boundary.
- `flutter analyze --no-pub`: no issues. `git diff --check`: passed.
- `tool/test_file_clipboard.ps1`: passed. The native test isolates its clipboard
  in a private Windows window station. It verifies actual file-object formats,
  Unicode paths including Chinese/spaces/emoji, double termination, copy intent,
  source retention and byte-identical copies from the decoded clipboard paths.
  Invalid inputs and clipboard contention preserve the existing clipboard.
- Windows Release, ZIP and installer builds passed. Product version is
  `0.3.10+25`. All 26 non-PDB Release files match the package; all 44 ZIP files and
  all 44 extracted installer payload files match it by SHA-256. No local runtime
  configuration, history, logs or tests were found. The explicit native test
  target outputs outside the runner Release directory and is not packaged.
- Android Release build passed. Manifest versionName is `0.3.10`, versionCode is
  `25`. APK v2 signature verification passed with the existing development signer
  SHA-256 `c6062e6446f539d94931063cb0ca69faf58c8fe75e8c2d1c74055b3c5d57953a`.
  No runtime profiles, history, logs or tests matched among the 86 APK entries.

Evidence is from automated tests, fixture renders and package inspection, not a
manual Explorer/QQ/WeChat paste or new native installation. The user's clipboard
was not overwritten by the native test. No running application was stopped or
replaced, and no installer was executed. Windows remains unsigned; Android uses
its existing development signer. Existing Kotlin migration warnings do not
prevent the Android build. Real LAN discovery was not run.

## Artifacts

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.10-windows-x64-Setup.exe | 13762450 | EABE815FDD6D5FA4770D37EDD60BE22B883F04B82891EA107E5C7217C6668234 |
| NearLink-0.3.10-windows-x64.zip | 16355702 | 68EDEAC8A782425E2FECC31A8848D9B7561813DC9CF701855E88FE71E35ABEBF |
| NearLink-0.3.10-android-preview.apk | 55989204 | 80E72C6D90A00666CBF76F68FC266655A8D99F9AB4324CD2B904DD2C49F453BD |

Checksums are also in `outputs/NearLink-0.3.10-SHA256SUMS.txt`.
