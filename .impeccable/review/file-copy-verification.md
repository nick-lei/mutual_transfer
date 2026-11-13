# Windows file card copy verification

Date: 2026-11-13. Version: `0.3.10+25`.

## Interaction and Appearance

Home transfer activity and History share a selectable file card. Single-click
focus uses the established blue tint and a 1 px blue stroke, retaining the 8 px
corners, 12 px gaps, card dimensions and metadata layout. Ctrl+C copies the local
file and Escape clears selection. The right-click menu selects its card and
shows a Lucide Copy icon, Chinese label and shortcut hint on a white elevated
surface. Existing floating feedback reports copy success and errors.

Sent records copy their existing source, including rejected transfers. Receives
require a completed saved file; unavailable files and unfinished receives disable
the context command. Search fields retain normal text copying. No multi-selection
or Android clipboard interaction is introduced.

All eight fixture captures were opened and reviewed:

- `file-copy-selected-0-1440.png` and `file-copy-selected-0-440.png`
- `file-copy-menu-0-1440.png` and `file-copy-menu-0-440.png`
- `file-copy-selected-3-1440.png` and `file-copy-selected-3-440.png`
- `file-copy-menu-3-1440.png` and `file-copy-menu-3-440.png`

These are scrolled-to-card views of the existing desktop layout at 1440 and 440
logical pixels, rendered with synthetic data and real temporary fixture files.
They confirm theme continuity, readable menu content and unchanged card geometry.
No new raster asset or separate visual system was introduced.

## Automated Verification

- Full `flutter test --no-pub`: 254 passed, 2 skipped. Default opt-in discovery
  and optional Android capture tests remain skipped.
- Five clipboard API tests cover Unicode paths, validation, bounded busy retries,
  persistent contention and native file disappearance.
- Five widget tests cover Home/History at 1440/440, received and sent originals,
  rejected sends, Ctrl+C, right-click Copy, Escape, search-field copy isolation,
  missing files and incomplete receives.
- `flutter analyze --no-pub`: no issues. `git diff --check`: passed.
- `tool/test_file_clipboard.ps1`: passed. Its native executable creates a private
  Windows window station and desktop, isolating its clipboard from the user's.
  CF_HDROP decodes two file objects with Chinese, spaces and an emoji in their
  names, uses wide paths and double termination, and sets Preferred DropEffect to
  copy. Files copied from these decoded paths retain their bytes and originals.
  Invalid paths and a competing clipboard owner leave the clipboard unchanged.

## Verification Boundary

The native test exercises the same C++ helper as the application, while widget
tests verify method-channel routing. This is not a manual Explorer, QQ or WeChat
paste test. The user's clipboard, running application and installation were not
replaced. Real LAN discovery was not run. Package checks are recorded separately
in `docs/PACKAGE_VERIFICATION_0.3.10.md`.
