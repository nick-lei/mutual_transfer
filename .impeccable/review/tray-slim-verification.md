# Slim Tray And Proactive Attention Verification

Build: NearLink 0.1.7+8, Windows x64 Release, 2026-11-07.

The native tray_manager plugin includes NIF_ICON when setting its tooltip. A
tooltip change therefore restored its cached ordinary icon after native badge
painting. DesktopController now finishes tooltip/menu updates before applying
native attention. A regression simulates the plugin's overwrite and verifies
the final icon after first message, later message and clearing all unread state.

## Validation

- `flutter test --no-pub`: 106 passed.
- `flutter analyze --no-pub`: no issues.
- Windows Release build passed with native warnings treated as errors.
- Native C++ integration tests compile the production tray_inbox.cpp and Runner.rc
  using the existing MSVC 2019 toolchain. They pass before-hover attention startup,
  fully opaque red-dot pixels in both distinct bright/dim HICONs, timer frame
  switching, phase preservation and stopping/restoring the normal icon.
- The same tests pass wheel scrolling, partial wheel-delta accumulation, thumb
  drag to the bottom, drag cancellation, keyboard End navigation, six-row
  overflow sizing and absent scrollbar for a short list.
- Native Shell_NotifyIcon reports success and the application diagnostics report
  trayBlinking true with unread attention before any mouse hover.

## Render Evidence

`tray-slim-harness/` contains top, bottom, keyboard-selected and short-list PNGs,
plus the decoded bright/dim HICON PNGs. The panel files are captured by sending
WM_PRINT to real native controls; WM_PRINTCLIENT uses the same PaintSurface
routine as WM_PAINT. These are production Win32 renders in an integration test
fixture, not live desktop screenshots. All six images were opened and inspected.
Scrollbar geometry is 4 px idle, 6 px hover/drag, in a 12 px hit strip, scaled by DPI.
No track or arrows are painted. All other existing design tokens are preserved.

Fresh Impeccable finish review: `ship`, limited to production Win32 painting,
source behavior and native fixture evidence. The reviewer inspected all six
captures, found no material fixes, and confirmed type, material, ground,
scrollbar hierarchy, header action and tray attention. Physical shell animation
is explicitly outside this verdict. DESIGN.md and its sidecar are preserved.

To run the native integration check, configure `tool/native_tray_test` with CMake
using Visual Studio 16 2019 and x64, build Release, then run
`build/native-tray-test/Release/nearlink_tray_test.exe <absolute-output-directory>`.

## Limits

Computer Use desktop captures were black and activation failed with
`GetCursorPos: access denied`, including after the user reported recovery and
the helper was reconnected. No physical shell-icon animation or live pointer
drag is claimed. The invalid black capture was removed. DPI variations,
Explorer restart and resume need future physical desktop verification; their
restoration paths are implemented. The real installed application and profile
were not replaced, stopped or changed during verification.
