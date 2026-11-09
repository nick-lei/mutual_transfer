# NearLink Brand Assets

Approved open-N logo, integrated on 2026-11-07. Two rounded neighboring terminals
form the N, with a central gap suggesting a device handoff.

- `app-icon.svg`: font-independent vector source for the approved app icon.
- `app-icon.png`: 256 px transparent PNG used by Flutter's shared `Brand` widget.
- `app-icon.ico`: Windows icon with 16, 20, 24, 32, 40, 48, 64, 128 and 256 px images.

The PNG and ICO are exports of the original vector geometry in
`outputs/nearlink-logo/brand.json`, rendered by `export.mjs`. The PNG contains
embedded source provenance. The complete logo kit, additional variants and
reproduction instructions are in `outputs/nearlink-logo`.

Run `tool/generate_icon.ps1` after replacing the approved ICO export. It copies
this icon to `windows/runner/resources/app_icon.ico`, which both the native
Windows executable and the runtime tray manager use.
