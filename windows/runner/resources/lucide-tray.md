# Native Tray Icons

Source: `lucide_icons_flutter` 4.0.2, `assets/lucide.ttf` (MIT, see
`lucide-LICENSE`). This is the same icon library as the Flutter application.

`lucide-tray.ttf` contains only `monitor` (57629), `fileDown` (58136), and
`checkCheck` (58254).
It is embedded as a native resource so Flutter's icon tree shaker cannot remove
glyphs used only by the Win32 popup. Regenerate with the Flutter SDK tool:

```powershell
'58254 57629 58136' | & <flutter-sdk>/bin/cache/artifacts/engine/windows-x64/font-subset.exe windows/runner/resources/lucide-tray.ttf <lucide-package>/assets/lucide.ttf
```
