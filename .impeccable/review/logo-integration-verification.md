# NearLink Logo Integration - 2026-11-07

User-approved scope: apply the delivered modern, minimal N logo to the program.

## Implementation

The shared Brand widget uses the approved 256 px PNG at fixed 36 x 36 logical
dimensions. The title bar, compact shell and About area therefore share one
image. The compact variant supplies a semantic brand label. The native EXE and
tray manager both use the approved nine-resolution ICO at the existing Windows
resource path. The icon synchronization script now copies that approved export.
DESIGN.md, the design sidecar and desktop surface brief describe this integration.

## Checks

- Existing full Flutter suite: 48 tests passed. Static analysis: no issues.
- The workspace fixture now awaits image decoding before capture. All nine
  workspace tests passed again, refreshing screenshots at 1440, 1000, 720 and
  440 logical px, plus collapsed navigation and 130% text settings checks.
- An independent reviewer inspected desktop-send.png, desktop-settings.png,
  desktop-collapsed.png, width-440-send.png, lifecycle-settings-1200.png and
  windows-executable-icon.png. Verdict: ship; no material integration findings.
  Native Flutter was reviewed directly; no HTML/CSS detector was used.
- Windows Release build succeeded. Windows extracted the correct new N icon
  from the built executable. Source, approved and packaged ICO hashes match.
- The refreshed portable executable, app.so, Flutter PNG and tray ICO hashes
  match their Release/source counterparts. The portable ZIP was regenerated.
- The new portable app was launched on Windows. Its compact shell and About
  area visibly display the new N. No tray initialization error appeared in
  Settings. The OS notification-area pixels were not separately captured.

The app was returned to quick send with the user's existing collapsed sidebar.
Close-to-tray was restored after exiting the old version for packaging. Startup
remains off; Alt+A remains enabled, and capture-hide-window remains off. No live
files or messages were sent as part of logo verification.
