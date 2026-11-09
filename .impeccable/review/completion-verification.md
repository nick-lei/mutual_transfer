# Transfer Completion Verification

Date: 2026-11-07
Release: 0.2.4+13

## Scope

Both senders and receivers now receive a batch completion event after every file
has completed successfully. Receivers wait for integrity verification, commit and
publication. Group senders aggregate all target recipients into one success event.
Refused, cancelled, invalid-checksum and partially failed batches never announce
all-files completion. Successful retries are new batches; history is not replayed.

Foreground completion uses the incumbent white floating snackbar, green Lucide
check, result title, peer/count/size summary, and tooltip-labelled history/close
icons. Background, minimized and tray completion uses native Windows notification
delivery with a history action. Settings provide independent completion-notice
and completion-sound preferences. Sound is throttled to one per two seconds.

## Validation

- `flutter test --no-pub`: 137 tests passed.
- `flutter analyze --no-pub`: no issues found.
- UI capture run for notification settings and workspace: 32 tests passed.
- Loopback coverage includes multi-file and zero-byte batches, refusal, pending
  cancellation, invalid commit, partial failure followed by successful retry,
  and all-recipient versus partially refused group sending.
- Notification controller tests cover both completion directions, foreground
  sound, mute, independent persisted preferences, notification cleanup, blocked
  delivery, history activation and no replay from changes/restored history.
- Opened all six current Flutter fixture captures in this directory:
  `completion-sent-1440.png`, `completion-received-1440.png`,
  `completion-sent-440.png`, `completion-received-440.png`,
  `notifications-completion-800.png`, `notifications-completion-320.png`.
  Prompt viewports are 1440x760 and 440x760, with 1.3 text scale at 440.
  Settings viewports are 800x600 and 320x720, with 1.5 text scale.
- Fresh independent Impeccable finish review: disposition `ship`, all five
  contract sections returned, no material fixes. Review covered the completion
  prompt and settings extension at the supplied fixture sizes. No HTML/CSS
  detector was used for native Flutter. No separate new-world quality card or
  concept record was supplied because this extension preserves the incumbent
  Operate design. DESIGN.md and .impeccable/design.json are preserved.
- Windows Release build, portable packaging and Inno Setup compilation passed.
- Release and packaged EXE Product/File versions both equal `0.2.4+13`.
  Packaged EXE and `data/app.so` SHA-256 match the final Release build.

## Outputs

- `outputs/NearLink-0.2.4-windows-x64-Setup.exe` (13,717,579 bytes)
  SHA-256: `59260B35EAC411F45EEC3A9FB61BB2787A5263C24FBC3EEDA5DC5EB484B99702`
- `outputs/NearLink-0.2.4-windows-x64.zip` (16,291,703 bytes)
  SHA-256: `617C0A94684D0C97C51ADEB4ED667E00A8394CB5DBED23345D5E605AE3610EC5`

## Evidence Limits

UI captures use Flutter widget fixtures and synthetic test data. They establish
layout and rendering, not physical Windows toast appearance or sound. Controller
tests use a fake notification backend; native notification delivery remains
subject to Windows permission, notification and Do Not Disturb settings. This
release was built and packaged without installing it, launching it, or stopping
the user's existing application. Installation on another computer and physical
multi-device notification/sound behavior were not exercised in this run.
