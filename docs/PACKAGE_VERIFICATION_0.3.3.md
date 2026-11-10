# NearLink 0.3.3 Chat Forwarding And Package Verification

Date: 2026-11-10. Application version: `0.3.3+18`.

## Resulting Behavior

- Completed sent and received chat files expose an icon-only forward action.
  Forwarding uses the local source or received file without changing the Send
  queue. The destination chat opens and displays the existing transfer progress,
  acceptance, cancellation and completion states. Original drafts remain intact.
- Desktop two-pane chat supports dragging the completed file card onto another
  conversation. A compact floating preview follows the pointer; eligible targets
  receive a blue outline, while unavailable targets use a rejection state. Drops
  outside a target or back onto the source conversation send nothing.
- Android tablets support long-press dragging between visible conversations.
- Android's forward icon opens a full-page recipient selector with the current
  app theme, file summary, searchable names/remarks/groups, single selection and
  a bottom confirmation action. It has no modal dialog or dimmed chat background.
  Back returns without sending. Selecting a recipient dismisses search input.
- Recipient availability updates while choosing. Inactive or unavailable groups
  and offline devices cannot be selected. The sender rechecks the recipient and
  the local file after I/O before starting a transfer. Active or incomplete
  transfers cannot be forwarded; missing files report an actionable error.
- Direct and group forwards reuse existing transfer services. The receiver still
  confirms the request. The covered source conversation does not consume unread
  messages while the recipient selector is open.

## Verification

- Full `flutter test --no-pub`: 204 passed, 2 skipped. Skips remain the optional
  Android screenshot review case and opt-in real LAN discovery test.
- Twelve new interaction cases cover desktop drag/drop, group target feedback,
  cancellation, offline/source targets, deleted files and a target going offline
  after drop; Android sent/received forwards at 390 and 320 logical pixels,
  availability changes, unread protection, back navigation, remark search over a
  long recipient list and tablet long-press dragging. The narrow phone cases use
  1.3 text scale and retain drafts and inline transfer progress.
- `flutter analyze --no-pub`: no issues found. `git diff --check`: passed.
- Local widget screenshots were inspected for the desktop drag preview, mobile
  recipient pages at both sizes, and forwarded-file progress. They use test
  fixtures and do not establish native operation on a physical phone.
- Windows Release, portable ZIP and Inno Setup installer builds passed. Binary
  product version is `0.3.3+18`. All 26 non-PDB Release files match the packaging
  directory. All 44 ZIP entries and all 44 extracted installer payload files match
  that directory by SHA-256; no runtime configuration, history, logs or tests are
  bundled.
- Android Release build passed. Manifest versionName is `0.3.3`, versionCode is
  `18`. APK v2 signature verification passed, retaining the 0.3.2 local development
  signer. None of the APK's 86 entries contain runtime configuration, history,
  logs or test data.

No running Windows application was stopped or replaced. The Windows installer
and installer verification script were not executed. The emulator and physical
phone were not reinstalled or used for a new native transfer in this change.
The installer remains unsigned; Android retains its existing preview signer.
Existing Kotlin future-migration warnings did not prevent the Android build.

## Artifacts

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.3-windows-x64-Setup.exe | 13749502 | DC086BEA308E78332989FF8E23A02EC7F68420034D01824070758047FFD2AA9D |
| NearLink-0.3.3-windows-x64.zip | 16339758 | 62ECCD4887AED432C3F9241A718286E258A263BD9CE2304AE9FA200AEA868EE0 |
| NearLink-0.3.3-android-preview.apk | 55907284 | 5959F89694CDC944CF8B34063CA926D671820FC61C6D26B1BB2AAEAA3711D206 |

Checksums are also in `outputs/NearLink-0.3.3-SHA256SUMS.txt`.
