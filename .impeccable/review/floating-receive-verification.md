# Floating Receive Prompt Verification

Date: 2026-11-07
Release: 0.2.3+12

## Scope

User feedback on the previous white strip requested a floating appearance.
The prompt now has exposed canvas on all sides, a centered 1120 px maximum
width, 16 px corners and a soft downward shadow (ink at 12%, blur 28, offset 0/8).
It remains in the page layout so expansion does not cover controls. Existing
content, theme colors, disclosure, list scrolling and confirmation remain intact.

## Validation

- `flutter test --no-pub`: 127 tests passed.
- `flutter analyze --no-pub`: no issues found.
- Capture run selecting `incoming review`: 3 tests passed. Existing tests now
  also check gaps from the window edges/title bar and render real soft shadows,
  restoring the painting debug variable before the test invariant check.
- Opened all six current captures under this directory:
  `incoming-floating-collapsed-1440.png`, `incoming-floating-expanded-1440.png`,
  `incoming-floating-collapsed-720.png`, `incoming-floating-expanded-720.png`,
  `incoming-floating-collapsed-440.png`, `incoming-floating-expanded-440.png`.
  Viewports: 1440x920, 720x760 and 440x640, with text scale 1.3 at 440.
- `incoming-floating-preview.png` is an unretouched crop of the final collapsed
  1440 capture at x=208, y=64, width=1232, height=152, preserving the perimeter
  canvas and shadow for presentation.
- Fresh independent Impeccable review included the user's current screenshot:
  disposition `ship`, no material findings. The review's nonblocking design-doc
  wording observation was corrected with a local-shadow exception link; existing
  system tokens and .impeccable/design.json were preserved.
- Windows Release build, portable packaging and Inno Setup compilation passed.
- Release and packaged EXE Product/File versions: `0.2.3+12`. Packaged EXE and
  `data/app.so` SHA-256 match the final Release build.

## Outputs

- `outputs/NearLink-0.2.3-windows-x64-Setup.exe`
  SHA-256: `54903DDBB6F42EA7925BE03879FEABA0956ABFFE6F146A05DB90D89D2578558D`
- `outputs/NearLink-0.2.3-windows-x64.zip`
  SHA-256: `562128B343DDA463FD7A4F4AC9F8F240C7BB1165A427F6083A288291E57AEFB6`

## Evidence Limits

Captures use Flutter widget fixtures and synthetic files, not a physical Windows
window. Native DPI, focus and hover were not independently exercised. At the
minimum window size the expanded prompt reduces visible page space; the file
list is bounded and the page remains scrollable. The new package was not installed
or launched, and the existing running application was not replaced.
