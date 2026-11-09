# Conversation Device Remark Entry Verification

Date: 2026-11-07
Release: 0.2.1+10

## Scope

The messages conversation list exposes a device-row secondary-click menu with a
Lucide pencil and the existing Chinese remark action. Selecting it opens the
existing persisted remark editor. Offline devices are supported. Secondary click
preserves the selected conversation, its draft and unread counts. Escape dismisses
the menu. Group rows retain their separate group-name workflow.

## Validation

- `flutter test --no-pub`: 124 tests passed.
- `flutter analyze --no-pub`: no issues found.
- Capture run selecting conversation tests: 7 tests passed.
- Opened and checked `conversation-context-menu-1440.png`,
  `conversation-context-menu-720.png` and `conversation-context-menu-440.png`.
  These are current Flutter widget fixture renders at 920 logical pixels high;
  the 440-wide case uses text scale 1.3. Menu content is complete at all widths.
- Fresh independent Impeccable finish review: `ship`, no material findings.
- Incumbent DESIGN.md tokens and .impeccable/design.json were preserved. The
  surface brief documents the interaction and state-preservation contract.
- `flutter build windows --release --no-pub`: succeeded.
- Portable packaging and Inno Setup installer compilation: succeeded.
- Both Release and packaged executable versions: `0.2.1+10`. SHA-256 checks of
  the packaged executable and `data/app.so` match the final Release build.

## Outputs

- Installer: `outputs/NearLink-0.2.1-windows-x64-Setup.exe`
  SHA-256: `44D84038356D8B86A81256EDA86494E17F5C3A8C3F2FCEF493F2F3250D7DA652`
- Portable: `outputs/NearLink-0.2.1-windows-x64.zip`
  SHA-256: `F626E2C1459E1D4B7B073ACE648D345D2C624BFD50A20A440458B0C252BF0840`

## Evidence Limits

UI evidence uses synthetic widget fixtures, not physical Windows mouse input.
Multi-monitor/DPI popup placement was not exercised on real hardware. The new
installer was compiled and its payload verified, but not installed or launched
during this patch. The existing installed running application was not changed.
