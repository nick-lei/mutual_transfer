# Android Splash Logo Fix

Date: 2026-11-09 (Asia/Shanghai). NearLink 0.3.0+15.

## Problem and Change

The Android 12+ launch theme reused the low-resolution launcher mipmap directly.
The system enlarged and clipped this legacy icon, losing the brand's rounded
background and cutting into the white/mint strokes. The reported appearance was
reproduced on Android 14 LDPlayer before changing the resources.

`drawable/splash_logo.xml` now provides a dedicated vector using the existing
brand SVG geometry and colors. Its 288 dp square viewport has 80 dp padding around
the 128-unit source mark. The full mark remains inside the splash safe area.
Both API 31 light and night themes explicitly reference this drawable with a
transparent icon background. Android 8-11 launch backgrounds use the same centered
resource. Launch and normal-window backgrounds share the app's #F5F7FC canvas.
No artificial launch delay, Dart/page-layout changes or app-data clearing was used.

## Verification

- `tool/build_android.ps1` passed; assembleRelease completed in 154.7 seconds.
- The APK installed over the existing preview with `adb install -r` and launched.
- `apksigner verify --verbose` passed: APK Signature Scheme v2, one local
  development signer.
- AAPT's compiled resource table confirms default, night, v31 and night-v31
  launch themes, and both API 31 variants reference the dedicated splash vector.
- The optimized APK stores that vector as `res/j1.xml`; AAPT XML inspection
  confirms the viewport, translation and complete three-path brand geometry.
- Native Android 14 cold-start screenshots show the complete centered logo in
  both system light and night modes. The normal send screen loads afterward.
- The sampled AndroidRuntime/Flutter log contains no fatal exception or Flutter
  error. System night mode was restored to its original `no` value; font scale
  remains 1.0. No Windows NearLink process was stopped or updated.
- This is an Android-resource-only fix. Dart/widget tests were not rerun;
  Android resource compilation, installed cold starts and visual checks cover
  the changed behavior. Android 8-11 and the user's physical phone were not run.

Screenshots in this directory:

- `android-splash-before.png`: reproduced clipped legacy icon, during exit fade.
- `android-splash-fixed-light.png`: complete logo in a native light-mode launch.
- `android-splash-fixed-night.png`: complete logo with system night mode enabled;
  the app retains its established light canvas.
- `android-splash-comparison.png`: resized native before/after screenshots.

Raw capture sequences remain under `build/android-verification/splash-before`,
`splash-after-light` and `splash-after-night`. They are emulator evidence, not
physical-phone screenshots.

## Installable Artifact

Path: `outputs/NearLink-0.3.0-android-preview.apk`

Size: 55,415,440 bytes. Version: 0.3.0+15. Local development signing certificate.

SHA-256: `5b65a868052a3b2ef1ebf377b62be47f78b3bb07a1c2f6fa1ecf92cee8e140e5`

This artifact supersedes the APK hash in the 2026-11-08 mobile polish record.
