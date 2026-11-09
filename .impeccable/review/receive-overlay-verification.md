# Incoming Receive Overlay Verification

Date: 2026-11-07
Release: 0.2.5+14

## Scope

The user requested that the incoming-file prompt float directly above the main
content rather than occupy a dedicated region and push the page downward.
The workspace now uses a Stack: the page fills the available body, and the
incoming prompt is a top-positioned sibling. It has no layout slot, reserved
band or modal barrier. The page scrolls underneath the pinned prompt; visible
content outside it remains interactive. Expanded details retain their independent
bounded file list. Title bar, sidebar and bottom navigation remain outside it.

This refinement preserves existing colors, typography, 16 px corners, shadow,
metadata, and explicit per-request accept/reject/disclosure actions. The panel
intentionally covers underlying headings and part of the page while expanded.
PRODUCT.md, README.md and the surface brief describe the new behavior; DESIGN.md
and its design sidecar retain the incumbent system.

## Validation

- `flutter test --no-pub`: 139 tests passed.
- `flutter analyze --no-pub`: no issues found.
- Focused capture run selecting `incoming review`: 3 tests passed.
- Home regression checks compare the exact DropTarget rectangle and scroll
  viewport dimension before arrival, while collapsed, while expanded and after
  handling the final request. They remain identical.
- Wheel input below the panel scrolls the page while the prompt rectangle stays
  fixed. The expanded file list scrolls independently, and accepting/rejecting
  one request leaves the next request undecided.
- Two new chat tests at 1440 and 440 px compare composer geometry, then type and
  send a message while an incoming request remains pending.
- Opened all six current fixture images in this directory:
  `incoming-overlay-collapsed-1440.png`, `incoming-overlay-expanded-1440.png`,
  `incoming-overlay-collapsed-720.png`, `incoming-overlay-expanded-720.png`,
  `incoming-overlay-collapsed-440.png`, `incoming-overlay-expanded-440.png`.
  Viewports are 1440x920, 720x760 and 440x640, with 1.3 text scale at 440.
  Captures enable real soft-shadow painting and restore the debug setting.
- Fresh independent Impeccable review inspected all six images and the user's
  feedback screenshot `codex-clipboard-538e9361-f168-4862-a37c-4338be38f6f3.png`.
  Disposition: `ship`; all five contract sections returned, no material fixes.
  This is a precisely scoped incumbent-world refinement, with no new direction
  roll, approved comp or separate quality card. No HTML/CSS detector applies to
  the native Flutter implementation.
- Windows Release build, portable packaging and Inno Setup compilation passed.
  Release and packaged EXE Product/File versions both equal `0.2.5+14`.
  Packaged EXE and `data/app.so` SHA-256 match the final Release build.

## Outputs

- `outputs/NearLink-0.2.5-windows-x64-Setup.exe`
  SHA-256: `C0F5CB5C09DFDBD56A66A3467EBAB9C21E4F82998944AE5FD6A80E0C9363514A`
- `outputs/NearLink-0.2.5-windows-x64.zip`
  SHA-256: `73CECFA7B6E035A2DECBEA5F6555BE301C3DED486FC31C411F77AB5E6DC60BC9`

## Evidence Limits

Images are Flutter widget fixtures with synthetic files and devices. They verify
layout and rendering; they do not establish physical Windows focus, native DPI,
notification delivery or behavior between separate machines. Package verification
does not install or launch this release or stop the user's existing application.
