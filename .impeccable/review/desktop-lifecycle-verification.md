# Desktop lifecycle verification - 2026-11-06

Scope: persisted sidebar collapse, configurable close behavior, Windows tray
actions and opt-in login startup. Existing receive confirmation and screenshot
preferences remain in effect.

## Automated and rendered checks

- Full Flutter suite: 48 tests pass. Coverage includes preference persistence,
  startup registration failure, corrupt settings, unavailable tray fallback,
  close-to-tray without service shutdown, single cleanup for repeated exit,
  tray-menu routing and cancellation of an active screenshot before closing.
- Workspace tests exercise collapse/expand, both close choices and the startup
  switch at 1200, 720 and 440 logical px, including 130% text scale at 440.
- Reviewed `desktop-collapsed.png` and the lifecycle settings captures at these
  widths. The dropdown stacks under its label when narrow; no text or controls
  overlap. Icon navigation retains tooltips and the active-page state.
- Static analysis has no issues. Scoped layout detector has no findings.
- Windows Release build succeeds. Generated Windows plugin registration includes
  TrayManagerPlugin, and the package includes its DLL and the tray ICO asset.
- Packaged executable and `data/app.so` SHA-256 hashes match the Release build.

## Windows portable app checks

- Sidebar collapse and expansion work, with the collapsed choice restored after
  restarting the app.
- Clicking the close caption button in tray mode removes the visible window;
  `GET /v1/info` still returns HTTP 200. Launching the executable again restores
  the same window and process, without creating a second portable instance.
- Changing the close dropdown to Exit persists immediately. Clicking Close then
  removes the portable process and releases its HTTP endpoint.
- The startup switch writes a quoted executable path plus `--autostart` into the
  current user's NearLink Run entry; switching it off removes that entry.
- Launching with `--autostart` leaves no visible main window while the HTTP
  endpoint responds. A normal launch restores that existing process.
- While started in the tray, Alt+A opens the screenshot overlay over Explorer.
  Escape cancels and leaves the main window hidden. Existing screenshot settings
  remain Alt+A, enabled, and hide-window-on-capture disabled.
- Final app state: Settings open; sidebar expanded; Close to Tray selected;
  startup disabled, as before verification. No files or messages were sent.

Verdict: pass for the requested implementation and checks above. The startup
registration and startup code path were tested without rebooting Windows.
Security software displayed its own startup approval notice; it was not acted
on. Native tray-menu mouse interaction was not automated; its restore/capture/
exit dispatch is covered by controller tests. Multi-device background transfers
and operating-system session shutdown were outside this verification scope.

## Close-behavior radio refinement - 2026-11-07

The close-behavior dropdown is replaced by two visible, mutually exclusive radio
options: "收起到任务托盘" and "退出邻传". Clicking either label selects its option.
The existing controller still owns loading, immediate persistence and errors.

The existing lifecycle workspace test passes at 1200, 720 and 440 logical px,
including 130% text at 440. It checks that both options are present, the saved
initial selection is shown, and selecting Exit updates the group and controller.
Reviewed all three refreshed lifecycle captures: options sit beside the setting
label on desktop, below it at medium widths, and vertically on the narrow layout.
No overlap or clipped labels. A transparent Material ancestor preserves native
hover, focus and click feedback inside the existing Surface.

Static analysis has no issues. Windows Release build succeeds. Tray, startup,
networking and screenshot implementations are unchanged by this refinement.

The updated portable app was launched and reviewed on Windows. It restored the
saved Exit selection, then clicking the Tray option's text selected it and wrote
`closeToTray: true` immediately. Both options remain visible and exclusive.
The final app is open on Settings with Tray selected, startup off, the sidebar
expanded, and the existing Alt+A / capture-hide-off preferences preserved.
Packaged executable and `data/app.so` hashes match the Release output. The
portable directory and ZIP have both been refreshed. Verdict: pass.
