# Incoming File Attention Verification

Build: NearLink 0.1.6+7, Windows x64 Release, 2026-11-07.

## Automated Checks

- `flutter test --no-pub`: 105 passed.
- `flutter analyze --no-pub`: no issues found.
- Release native build succeeded with warnings treated as errors.
- Regression tests cover two pending offers alongside unread messages, marking
  messages read without deciding either offer, tray menu and native callback
  routing by offer ID, accepted/rejected offer removal, and expired-ID feedback.

## Native Loopback Checks

- Isolated receiver on 127.0.0.1:45985, discovery and desktop toasts disabled.
- Generated local text file enters the native tray inbox above a message row.
- Mark-all-messages-read leaves the request pending, preserves the open panel,
  removes the message row, and hides the read-all icon.
- Clicking the file row restores the main window and expands that offer's files.
- An unanswered request expires at 90 seconds, clearing its attention.
- A separate generated request is accepted, transfers all 1,344 bytes, and clears
  attention. Sender and received file have matching SHA-256:
  `d7e06f6f5ca2d522e7a9db2b736d19db48035ec50e271fa962c7164ed31f9dd7`.
- Native result reports `taskbarOverlayApplied: true`. A background incoming
  request reports `taskbarFlashRequested: true`; after no attention remains it
  reports false. This establishes the native API path, not physical flashing
  pixels or another computer's Windows taskbar policy.
- The generated test receiver was stopped after verification; the separately
  installed application and its profile were not changed.

## Captures

- `file-attention-mixed.png`: native file and unread-message rows.
- `file-attention-only.png`: native request retained after marking messages read.
- `file-attention-opened-native.png`: corresponding expanded request in the app.
- `tray-file-opened-request.png`: widget regression with two requests, opening
  the second by exact identity.

All native captures were inspected at their actual size. The source and pixels
match incumbent DESIGN.md receiving green/mint, blue message controls, Chinese
system type and Lucide icons. This ordinary extension preserves DESIGN.md and
the design sidecar; it introduces no replacement design system or raster assets.

Fresh Impeccable finish reviewer disposition: `ship`. The reviewer inspected
all three native captures and the relevant source, found no material fixes,
and confirmed type, surface treatment, palette, file/message hierarchy, icon
scope, exact-request arrival and intentional preview ellipsis. The review does
not establish physical taskbar flashing or another computer's behavior.

## Limits

Physical tray/taskbar badge pixels, taskbar flashing cadence, multi-monitor DPI,
Windows taskbar badge restrictions, and this build on a separate computer have
not been visually verified. Existing desktop notification behavior is covered
by regression tests; toast delivery was disabled in this isolated native run.
