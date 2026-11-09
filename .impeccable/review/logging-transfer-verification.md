# Logging and large-file transfer verification

Date: 2026-11-07. Platform: Windows x64, Flutter 3.44 / Dart 3.12.2.

## Result

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: all 70 tests passed.
- `flutter build windows --release --no-pub`: passed.
- Portable package rebuilt and launched from `outputs/NearLink-0.1.0-windows-x64`.
- Native settings log viewer displayed real launch, service and discovery records.
- Native JSONL export completed through the Windows save dialog; exported lines
  were parsed successfully from `outputs/performance/native-log-export.jsonl`.
- Sidebar collapsed and close-to-tray restored; startup remains off. Screenshot
  shortcut remains Alt+A, enabled; hide-window-on-capture remains false.

## Coverage

The service tests cover binary/empty/Unicode files, legacy compatibility in both
directions, pending commit visibility, wrong token, wrong source address, wrong
digest, repeated upload/commit, source size changes, commit timeout, active upload
cancellation, pending cancellation, shutdown cleanup, original messaging and
persistence behavior. Native digest tests compare CNG with the independent Dart
SHA-256 implementation, including known vectors and chunk boundaries, and require
that Windows actually selects CNG.

Logger tests cover nested redaction, exception-source suppression, rotation,
retention, export, failed export recovery, disk failure recovery, malformed final
lines, restart after an incomplete line, bounded queues and shutdown flushing.
Viewer tests cover filters, search, structured details, live entries, read failure,
retry, empty records, and 1100/440 logical-pixel layouts with increased text size.

## Visual Review

`log-viewer-1100.png` and `log-viewer-440.png` use synthetic diagnostic fixtures
only in Flutter tests. Both were rendered and inspected against the existing
Chinese typography, Lucide icon family, spacing and status colors. The native
viewer was also inspected with real runtime records. Search/filter controls stack
at narrow widths. No text or controls overlap; icon actions have tooltips and
keyboard focus. The log section and viewer preserve the current product theme.

Verdict: pass for the requested diagnostics surface and supported Windows build.

## Performance Evidence And Limits

Raw results are in `outputs/performance`. See `docs/PERFORMANCE.md` for measurements
and the reproduction command. The 256 MiB average elapsed time decreased from
7.284 to 1.344 seconds; the 1 GiB check finished in 4.738 seconds with independent
digest verification and about 234 MiB process RSS.

These are generated-fixture, same-process IPv4 loopback benchmarks in the Dart VM,
not a throughput measurement of the Release executable or two physical devices.
Real Wi-Fi, multi-device links, mixed storage and sustained multi-hour transfers
remain outside this verification. Failed transfers still restart from byte zero.
