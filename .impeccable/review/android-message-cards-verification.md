# Android Conversation Cards

Date: 2026-11-09 (Asia/Shanghai). NearLink 0.3.0+15.

## Change

The user requested that the Android message list match the send-recipient cards.
Each conversation now has a white Material surface, 8 dp corners and 8 dp spacing.
The list shares the send page's 16 dp outer inset and 12 dp card content inset.
Existing avatars, names, previews, timestamps and unread badges remain visible.
In expanded split view, the selected conversation uses the existing blue tint
and active device avatar. Online/offline icons are 18 dp and centered when no
message timestamp is present. Tap opens chat and long press opens device actions.

This is confined to the Android conversation list. The established transfer
history and the dedicated splash logo fix remain in the APK.

## Verification

- `flutter analyze --no-pub`: no issues found.
- `flutter test --no-pub --dart-define=CAPTURE_ANDROID_UI=true
  test/android_workspace_test.dart`: 17 passed. Existing interaction coverage
  includes long-press remarks, chat Back, unread retention, 320x640 with 1.3x
  text, 780x390 landscape and 1024x768 tablet layouts.
- Widget captures were inspected for phone conversation cards and tablet layout.
- `tool/build_android.ps1` passed (assembleRelease: 74.0 seconds).
- APK Signature Scheme v2 verification passed with the existing development signer.
- Installed over the current preview and launched on Android 14 LDPlayer,
  1080x1920 at 420 dpi. The existing conversation list displayed independent cards.
- An isolated sender with discovery disabled delivered two new test messages.
  Native UI semantics showed two unread messages on the conversation and on the
  navigation destination. The sender's existing history contains four total sent
  messages; its verification returned `delivered: true`.
- Native long press exposed the remark entry; tapping opened the conversation,
  consumed its unread count and returned to the card list with the back control.
- Native 1.3x font scaling retained separate card content, time and unread badge.
  Font scale was restored to 1.0, and the temporary forward tcp:64752 was removed.

Screenshots: `android-message-cards-before.png`, `android-message-cards-native.png`,
`android-message-cards-unread.png`, `android-message-cards-large-type.png` and
`android-message-cards-comparison.png`. These are native emulator captures with
generated verification messages. `android-widget-messages.png` and
`android-widget-tablet.png` use synthetic widget fixtures, not native device data.
The user's physical phone was not connected or tested during this change.

## Artifact

Path: `outputs/NearLink-0.3.0-android-preview.apk`

Version: 0.3.0+15. Size: 55,415,440 bytes. Local development signing certificate.

SHA-256: `b3ff27ad34cb96272301484a36b8bad53d125cf67231e9a5f6a5d3c1cb3b29fa`

This APK supersedes the earlier splash-verification artifact hash.
