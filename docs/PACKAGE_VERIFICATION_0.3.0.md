# NearLink 0.3.0 Package Verification

Built on 2026-11-09 from the current project source. Application version:
`0.3.0+15`. Installer display version: `0.3.0`.

## Artifacts

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.0-windows-x64-Setup.exe | 13732916 | 62651597F1E340139D84753D9EFE978818C3FD937889889EBA752AE7D34E44B6 |
| NearLink-0.3.0-windows-x64.zip | 16314582 | BFB3A78387DB21EF332338ACF215FB76C7DAF3EC8FC5E5C186378C80A5E824D9 |
| NearLink-0.3.0-android-preview.apk | 55464860 | ECAC99A662A69D52C57A80BB39F996679F73DFBC8DE698C16B7882019D011E47 |

The same values are available in `outputs/NearLink-0.3.0-SHA256SUMS.txt`.

## Build And Validation

- `flutter build windows --release --no-pub`: passed.
- `tool/package_windows.ps1 -Version 0.3.0`: passed.
- All 26 non-PDB Windows Release files matched the packaged directory by SHA-256.
- All 44 packaged files matched their ZIP entries by SHA-256. The package also
  includes the Visual C++ runtime, documentation, brand assets and licenses.
- `tool/build_installer.ps1 -Version 0.3.0`: passed with Inno Setup 7.1.1.
  The builder checked required files, runtime libraries, version and Release hashes.
- Windows application ProductVersion and FileVersion are `0.3.0+15`.
  Installer ProductVersion is `0.3.0` and FileVersion is `0.3.0.0`.
- `tool/build_android.ps1`: passed with the existing pinned Android toolchain.
- APK v2 signature verification passed, using the existing local development
  signer. Manifest confirms package `app.nearlink.mutual_transfer`, version code
  15, version name 0.3.0, minimum API 26 and target API 36. Included native ABIs:
  arm64-v8a, armeabi-v7a and x86_64.
- The Android rebuild has the same hash as the settings-refinement build.
  Existing AGP/Kotlin future-migration warnings did not prevent this build.

## Scope

The Windows installer has no publisher code signature. It was compiled but not
executed for this packaging request. No Windows instance was stopped, replaced
or installed over; the three pre-existing processes were present afterwards.
`tool/verify_installer.ps1` was not run. This is build and package-integrity
evidence, not a new native Windows or second-computer installation test.

No production source changed during packaging. The Windows installation guide
was updated to the current artifact names before packaging. Earlier Android
Settings layout, native walkthrough and test evidence remains in
`../.impeccable/review/android-settings-verification.md`; shared chat-file
behavior and prior full-suite coverage are recorded in
`../.impeccable/review/chat-files-verification.md`.
