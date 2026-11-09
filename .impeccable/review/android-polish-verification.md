# Android UI Refinement Verification

Date: 2026-11-08 (Asia/Shanghai). NearLink 0.3.0+15.

## Delivered Scope

The existing blue, cool-white and mint theme, N brand asset and Lucide icons remain.

- Send: compact file/media selection, a selected-file summary opening the complete
  removable queue, recent recipients and a fixed explicit send action.
- Messages: unframed conversation list with recent times and unread counts; mobile
  chat uses a full-width canvas, time separators and tighter consecutive messages.
- Devices: remarks are primary, original identity remains visible, online/offline
  sections are separate and local addresses live in connection settings.
- Settings: compact identity and four entries opening receiving, notification,
  connection and diagnostic subpages. Independent existing toggles remain.
- Incoming requests: floating notice can collapse and reopen; decisions stay in
  the review sheet. Active transfers use blue badges, unread messages use red.
- History: restored the original individual file cards and the four original
  filters (all, active, received, failed), original spacing, 40 dp file glyphs and
  the file action menu. No batch expansion or separate direction toolbar ships.

The user explicitly rejected the history redesign and requested the earlier
layout. This decision supersedes the history recommendation in critique snapshot
`2026-11-08T07-30-58Z__lib-ui-android-workspace-dart.md`. Preserve the restored
history layout in subsequent refinements. Batch IDs remain backward-compatible
local metadata; no wire protocol was changed.

## Automated Checks

- `flutter analyze --no-pub`: no issues found after the history restoration.
- `flutter test --no-pub`: 158 passed, one opt-in capture test skipped.
- Android-specific tests with `CAPTURE_ANDROID_UI=true`: all 17 passed.
- The capture test passed again after the final spacing restoration, refreshing
  the widget previews. The last spacing-only edit did not change filtering logic.
- Coverage includes individual history records and filters, receiving settings
  routing, complete staged-file removal, incoming notice collapse, recent message
  times, 320x640 with 1.3x text, 780x390 landscape and 1024x768 tablet layouts.
- The small chat test supplies a 280 dp IME inset and verifies that the composer
  and send action stay reachable. This is simulated keyboard coverage.

## Native Evidence

LDPlayer 14.0.34.1, Android 14, 1080x1920 at 420 dpi. Screenshots in this directory:

- `android-polished-send.png`, `android-polished-staged.png`
- `android-polished-messages.png`, `android-polished-chat.png`
- `android-polished-chat-large-type.png` (native system font scale 1.3)
- `android-polished-devices.png`
- `android-polished-history-restored.png` (current approved history layout)
- `android-polished-history-received.png` (received filter on the final APK)
- `android-polished-settings.png`, `android-polished-receiving-settings.png`
- `android-polished-notification-settings.png`, `android-polished-receive-notice.png`

The older `android-polished-history.png`, `android-polished-history-batch.png` and
`android-polished-history-expanded.png` show the rejected intermediate design.
`android-native-history.png` is the earlier visual reference. `android-widget-*`
captures use synthetic fixture data and are layout evidence, not native evidence.

Message delivery, native file selection, receive confirmation, completion prompt
and full bidirectional three-file integrity passed with the isolated test peer:
`build/android-verification/peer-da919d2/result.json` (exit 0).

| File | Bytes | Returned SHA-256 |
| --- | ---: | --- |
| empty.bin | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| message.txt | 1536 | e195874896bcf11d3852c9978ce9cc9e16d62ebcc313452a9488b22341d0ae40 |
| payload-8MiB.bin | 8388608 | cad65a1f46032f6d4ecf9086f0093778849d5ece5a6722471600fd02c80ee025 |

An earlier return attempt timed out after returning only the empty file; it is
not counted as a pass. The successful rerun returned all three files and a reply.
Peer discovery was disabled and its state/files were isolated from Windows data.
Temporary ADB forward/reverse routes and generated SD-card fixture copies were
removed. Native font scale was restored. Background reception remains disabled.
The running Windows NearLink applications were not stopped, restarted or updated.

The final APK was installed with `adb install -r` and cold-launched successfully.
Its restored history was compared with `android-native-history.png`: search,
filter spacing, individual cards, file glyphs and metadata positions agree.
Received filtering and the open/export/share sheet were exercised natively.

## Installable Artifact

Path: `outputs/NearLink-0.3.0-android-preview.apk`

Size: 55,414,160 bytes. Version: 0.3.0+15.

SHA-256: `1270a3ea9456230bcf92ed8c835148e7f2c1cd053f1d7ed9697eb17413ecc50a`

`tool/build_android.ps1` passed (final Gradle assembleRelease: 130.2 seconds).
`apksigner verify --verbose` passed: APK Signature Scheme v2, one development signer.
The existing KGP migration warnings are unchanged and do not fail this build.

## Limits

These are preview builds signed by the local development certificate. Physical
phone installation, normal soft keyboard resizing, gesture navigation, TalkBack,
same-Wi-Fi automatic discovery and OEM background restrictions require hardware
validation. ADB-tunnel transfer success does not prove LAN discovery or throughput.
