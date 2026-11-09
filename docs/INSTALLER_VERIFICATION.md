# Windows Installer Verification

Verified on 2026-11-07 on the local Windows x64 development computer.

## Artifact

- Installer: `outputs/NearLink-0.1.0-windows-x64-Setup.exe`
- Size: 13,533,682 bytes (12.91 MiB)
- SHA-256: `4EAA6888AD27F2C529EFED1DD3D2F3AE29739D4761FD4F19214A70179F4B652F`
- Built with official Inno Setup 7.1.1 from the latest Flutter Windows Release payload.
- The application installer does not have a publisher code signature.

## Automated Checks

`tool/verify_installer.ps1` passed all 25 integration checks. The machine-readable
result and install/uninstall logs are under `build/installer-verification/`.

Coverage includes per-user registration, a Unicode installation path containing
spaces, all installed payload hashes, desktop and Start menu shortcuts, upgrade,
running-application protection, startup migration, uninstall cleanup, portable
startup ownership, and preservation of existing configuration/history files.

## Visible Wizard And Runtime

- Opened the actual Setup executable and checked the Simplified Chinese language
  selection, welcome page, destination page, and desktop shortcut option.
- Text and controls rendered without clipping; the approved app icon appeared in
  the installer title bar and language dialog.
- Installed into `build/installer-verification/runtime install`, launched its
  `mutual_transfer.exe`, and confirmed the main application screen rendered.
- Opened `Local\NearLink.InstallationGuard` while the installed app was running,
  confirming the actual Release executable holds the installation guard.
- Closed the app normally and uninstalled the test copy successfully. An initial
  uninstall attempt while shutdown was still finishing was correctly blocked by
  the guard; retry after release succeeded.
- Confirmed the test uninstall registration was removed. Relaunched the updated
  portable copy and restored the original close-to-tray setting through the UI.
- Confirmed the original collapsed sidebar, disabled startup, enabled Alt+A
  screenshot shortcut, and disabled hide-window-on-capture preference.

## Scope

This verifies local installation and launch. It does not establish behavior on a
second Windows computer, Windows download reputation, or real-device LAN
transfer performance. User configuration, logs, history, and received files are
kept outside the managed installation payload.
