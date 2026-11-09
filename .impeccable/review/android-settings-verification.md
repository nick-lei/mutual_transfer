# Android Settings Verification

Date: 2026-11-09. Scope: refine Android Settings to match the existing NearLink
Send and Messages theme. The running Windows application was not stopped or
replaced. No Windows package was built for this Android-only refinement.

## Result

- Local-device identity and the four settings entries use flat white rows with
  8 dp corners on the existing cool-white canvas. Page insets remain 16 dp;
  entries have 8 dp gaps and blue/mint icon tiles with Lucide symbols.
- The whole identity row opens the existing name editor. Long names allow two
  lines and ellipsis. Brand/version information is a compact horizontal footer.
- Receiving, Notifications, Connection and Diagnostics use the same row styling.
  Related notification/sound switches share white groups and inset dividers.
  Subpages have an explicit Lucide back action and keep native system Back.
- Existing setting values, defaults, saving, permissions and background-reception
  behavior are preserved. The application-private storage explanation remains.

## Automated Checks

- `flutter analyze --no-pub`: no issues found on the final source.
- `flutter test --no-pub --dart-define=CAPTURE_ANDROID_UI=true
  test/android_workspace_test.dart`: 25 passed, with no warnings in the final run.
- Extended the existing layout-capture test for Settings and all four subpages,
  including a synthetic long device name at 320x640 with 1.3x text and 1024x768.
  These are layout fixtures, not native device or real-user evidence.
- The full shared test suite was not rerun for this scoped style change. Earlier
  chat-file testing remains recorded in chat-files-verification.md.

## Native Android

Android 14 on LDPlayer 14, serial `127.0.0.1:5555`. The new APK was installed using
`adb install -r` and launched successfully with existing data preserved.

- Opened Settings and each of its four subpages. Opened the device-name editor
  and cancelled, preserving the real device name. Scrolled Notifications to the
  transfer-completion switches. Existing switches were not changed.
- Phone: 1080x1920 and 1920x1080, 420 dpi. Checked 1.0 and 1.3 font scale.
- Tablet size classes: 2688x2016 and 2016x2688, 420 dpi. Wide view uses the existing
  navigation rail; narrower view keeps the existing bottom navigation.
- Reviewed native captures for alignment, wrapping and reachable controls.
  No Flutter error-level logcat output was present after the walkthrough.
- Restored 1080x1920, font scale 1.0 and the existing light system mode.

Native captures:

- `android-settings-native-before.png`, `android-settings-native-after.png`
- `android-settings-native-receiving.png`
- `android-settings-native-notifications.png`
- `android-settings-native-notifications-bottom.png`
- `android-settings-native-connection.png`
- `android-settings-native-diagnostics.png`
- `android-settings-native-large-type.png`
- `android-settings-native-landscape.png`
- `android-settings-native-tablet.png`
- `android-settings-native-tablet-portrait.png`

This verification concerns settings presentation and navigation. Real-phone
hardware, TalkBack, system notification delivery and sustained background
reception were not newly tested. Previous networking evidence and limits remain
in chat-files-verification.md and android-verification.md.

## Preview APK

- `outputs/NearLink-0.3.0-android-preview.apk`, version `0.3.0+15`.
- SHA-256: `ECAC99A662A69D52C57A80BB39F996679F73DFBC8DE698C16B7882019D011E47`.
- `tool/build_android.ps1` passed; APK v2 signature verification passed.
- The same local development signer supports covering the currently installed
  local preview. The same-named APK supersedes the chat-file build and retains
  the previous splash, message cards and chat-file implementation.
- Existing AGP/Kotlin migration warnings remain; the pinned build completed.

## Visual Review

`disposition: ship` for this settings refinement. Review was performed inline;
no independent reviewer or native design detector ran. No new shipping assets
or design-system tokens were required.

### persistence

Pass. The Android surface brief and Android documentation record the final
presentation. PRODUCT.md and DESIGN.md retain the existing product and theme.

### fidelity

| Element | Result | Evidence |
| --- | --- | --- |
| TYPE | match | Existing system typography; native 1.3x text and long-name fixtures. |
| MATERIAL | match | Flat white 8 dp rows/groups matching existing conversation cards. |
| GROUND | match | Existing cool-white canvas with blue and mint icon treatments. |
| Hierarchy | match | Device identity, four entries, compact brand/version footer. |
| Navigation | match | Four native subpages, name editor and system Back walkthrough. |
| Responsive layout | match | Native phone/tablet portrait and landscape captures. |

### ceiling

Reached for this scoped refinement: consistent entry hierarchy, compact brand
presence, clear grouping and preserved Android controls and touch targets.

### material_fixes

None remaining in the inspected settings states. Platform checks not performed
are identified above and are not presented as passed.

### keep

Keep the current NearLink palette, existing settings behavior, separate detail
pages, storage explanation and platform-specific controls.
