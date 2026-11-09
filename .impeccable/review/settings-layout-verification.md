# Settings layout verification - 2026-11-06

Scope: the receiving-directory field, receive-confirmation information and
save/revert actions in `lib/ui/workspace.dart`. Existing theme and save semantics
are preserved.

## Composition

- The selectable path shares an input-style field with the folder marker and
  edit/open icon buttons. Both actions have tooltips and keyboard focus.
- Long paths wrap. Below 320 logical px adjusted for text scale, the actions move
  to a separate trailing row rather than squeezing the path.
- Mandatory receive confirmation remains an informational row, separated from
  the path by 24 px. It is not a configurable consent bypass.
- A divider separates the form from the right-aligned action footer. Revert is
  before Save; the actions wrap if needed. Saving, disabled and error states use
  the existing behavior.

## Verification

- `flutter test --no-pub --dart-define=CAPTURE_UI=true test/workspace_test.dart`:
  all 8 tests pass, including settings editing at 130% text scale.
- Reviewed current settings captures at 1440x920, 1000x760, 720x700 and 440x760.
  Reading order, path wrapping, icon targets and footer alignment hold without
  overlap or horizontal overflow. Narrow pages remain vertically scrollable.
- `flutter analyze --no-pub`: no issues.
- Scoped Impeccable layout detector: no findings before or after the change.
- Windows Release build and portable package succeeded. Packaged executable and
  `data/app.so` SHA-256 hashes match the Release build.
- Launched the updated portable app and visually checked the native settings
  page. The edit icon opens the directory picker; cancelling preserves the path
  and clean form state. The open icon opens the current receiving directory in
  Explorer; its tooltip is visible on hover. Closed only that test Explorer
  window and left the app on Settings.

Verdict: pass for this layout refinement. No device name, receiving directory or
screenshot preference was changed during native verification. Broader screenshot
and network behavior was outside this change's verification scope.
