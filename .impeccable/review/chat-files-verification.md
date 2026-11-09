# Chat Files Verification

Date: 2026-11-09. Scope: send files inside an existing conversation and show live
transfer cards, preserving the NearLink theme. Shared Flutter implementation,
Android preview packaged. No Windows instance was stopped or replaced, and no
Windows installer was built or exercised.

## Behavior

- The composer paperclip and chat-header file icon open the native multi-file
  picker. Confirming it sends to the captured conversation without navigation.
- Text drafts and the independent Send queue survive file selection/cancellation.
  Switching chats while picking never changes the captured recipient.
- The timeline merges text and local transfer records by timestamp with stable
  ties. It includes existing Send-page transfers and retains one source of truth
  for progress, status and saved paths. File cards share history retention/clearing.
- Cards show identity, size, true byte progress, percentage/speed, waiting,
  validation, completion, rejection, cancellation and failure states. Incoming
  confirmation accepts/rejects the entire existing batch. Other actions reuse
  cancellation, retry and file opening. Android received-file menus retain export
  and share. Group cards identify each member and keep individual outcomes.
- Conversation previews, timestamps and order now include file activity. Drafts
  remain the highest-priority preview. File cards do not invent message unread
  counts; the existing file-request attention remains separate.
- No wire protocol, integrity algorithm, transfer concurrency, or permission
  expansion. Existing large-file streaming remains in use.

## Automated Checks

- `flutter analyze --no-pub`: no issues found.
- Full suite with `CAPTURE_ANDROID_UI=true` and `CAPTURE_UI=true`: **169 passed**.
- Eight new Android cases cover direct sending, preserving drafts/Send queue,
  picker cancellation, recipient capture during navigation, live progress and
  terminal states/actions, inline acceptance, group-specific cards and isolation,
  and small/expanded layouts at 1.3x text.
- Two new desktop layout cases cover shared file cards and live completion at
  1440 and 440 logical pixels. The existing group, transport/integrity,
  notification, screenshot and navigation suites also passed.
- Existing group service integration tests verify independent receiving
  confirmation and aggregate completion; no synthetic widget test is presented
  as real group-network evidence.

## Native Android

Android 14, LDPlayer 14, serial `127.0.0.1:5555`, installed over the existing
preview with `adb install -r` and data preserved.

- From Messages, opened the generated verification peer conversation and accepted
  its three files directly on a file card.
- Opened the paperclip's native document picker, selected three generated test
  files, and sent them back without leaving chat. Followed by a text reply.
- Empty file, 1536-byte text and 8 MiB binary completed in both directions.
  All return SHA-256 digests match the generated fixtures. Result:
  `build/android-verification/peer-2a93d459/result.json`.
- The verification peer runs with isolated data and discovery disabled. Temporary
  ADB forwarding/reverse forwarding connected only this peer and were removed.
  This verifies transport through ADB, not real-Wi-Fi UDP discovery.
- Checked phone at 1080x1920/420 dpi, system font 1.0 and 1.3. Checked expanded
  split view at 2688x2016/420 dpi (1024x768 logical pixels). Restored the original
  1080x1920 override, 1.0 font scale and unchanged light system mode.
- Native captures: `android-chat-files-native-pending.png`,
  `android-chat-files-native-complete.png`,
  `android-chat-files-native-large-type.png`,
  `android-chat-files-native-tablet.png`.
- Synthetic layout captures: `android-widget-chat-file-progress.png`,
  `android-widget-chat-files-320.png`, `android-widget-chat-files-1024.png`,
  `chat-files-desktop-1440.png`, `chat-files-desktop-440.png`.
  Fixture names/progress are test data, not real users or measured LAN throughput.

Physical-phone IME behavior, real-Wi-Fi discovery, sustained background reception
and native Windows execution were not newly verified by this change.

## Preview APK

- `outputs/NearLink-0.3.0-android-preview.apk`, version `0.3.0+15`.
- SHA-256: `9A21CF6453C3FCE100B501701B856BFCE9BFB8F8FF70933D1C132B7E4CB4B83A`.
- `tool/build_android.ps1` passed; APK v2 signature verification passed.
- Existing local development signer. The same-named APK supersedes earlier
  preview builds, including the message-list-card build, and retains those fixes.
- Build reports the existing AGP/Kotlin migration warnings for future Flutter
  versions; this build completed with the pinned toolchain.

## Visual Review

`disposition: ship` for this local chat extension. Review performed inline in the
current session; no independent reviewer was spawned. No native design detector
ran. Existing system tokens and brand assets were preserved; no new shipping
bitmap assets were created.

### persistence

Pass. PRODUCT.md and existing DESIGN.md were checked. Android and desktop surface
briefs and docs record the final behavior and shared-history limitation.

### fidelity

| Element | Result | Evidence |
| --- | --- | --- |
| TYPE | match | Existing Android/system type and readable scaling retained. |
| MATERIAL | match | Flat Material file cards and existing Lucide/FileGlyph assets. |
| GROUND | match | Existing cool-white canvas, blue-tint outgoing, white incoming. |
| File action and progress | match | Native pending/completed cards and synthetic live-progress captures. |
| Responsive composition | match | Native phone/expanded captures plus narrow/large-text widget checks. |
| Chat continuity | match | Native send/receive stayed in chat; draft/queue/recipient tests passed. |

### ceiling

Reached for this extension: familiar file identity, quiet progress, readable
terminal status, 48 dp mobile actions and existing Android document selection.

### material_fixes

None remaining for this extension's captured states. Broader platform verification
limits are recorded above and are not represented as passed.

### keep

Keep the existing theme, true shared transfer state, explicit receiving decisions,
separate Send queue, and retained conversation drafts.
