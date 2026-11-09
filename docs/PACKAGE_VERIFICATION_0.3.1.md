# NearLink 0.3.1 Endpoint Fix And Package Verification

Date: 2026-11-09. Application version: `0.3.1+16`.

## Incident Evidence

The physical phone identified by the user is named `2407FRK8EC`. The selected
Android entry in the earlier screenshot was `2509FPN0BC`.

Live UDP capture on this computer observed Android identity
`08ccac87b4e4fbacbd997545a6ad2fe8` advertising name `2509FPN0BC` and port 45878
from source address `192.168.3.60`. This is the computer's own WLAN address,
where the existing Windows application listens on TCP 45878.

ADB inspection of the running LDPlayer instance (`127.0.0.1:5555`) confirmed its
Android interface address is `172.16.1.15`. A temporary ADB forward queried its
`/v1/info` and returned the exact same Android identity and name as the UDP packet.
The Windows `/v1/info` returned a different identity,
`895a5ca3c6d38c71ec74688a71e1051a`. Thus this incident is a NAT return-address
collision, not the phone and computer sharing an installation identity.

## Changes

- A discovered/inbound endpoint pointing at this service's own listener is not
  allowed to replace a previously known non-local endpoint. A new peer with only
  this invalid return endpoint remains offline for file sending.
- File batches, new outgoing chat connections and group HTTP requests query
  `/v1/info` and match the selected peer's ID before sending their contents.
  Mismatch marks the affected endpoint offline, records `peer_endpoint_mismatch`
  and explains whether it points to this device or another device.
- An active file batch retains its verified endpoint for upload and cancellation.
- Known outgoing WebSocket connections reject a conflicting hello identity.
- Android's model name now acts as a default. It no longer overrides the user's
  saved name on every launch. The existing explicit desktop `initialName`
  override keeps its behavior.

These identity checks prevent accidental misrouting; they are not cryptographic
authentication or NAT traversal. Emulator access still requires a reachable
bridged endpoint or explicit port forwarding and manual connection.

## Verification

- Reproduced the old self-send failure in an isolated regression test before the
  endpoint fix: a peer with a different ID but this service's endpoint returned
  the misleading old self-send error.
- Focused service/group suite: 40 passed.
- Full `flutter test --no-pub`: 174 passed, 1 skipped. The skipped case captures
  Android layout fixtures only when its capture define is enabled.
- Six new service regressions cover NAT endpoint overwrite, new invalid local
  routes, local/mismatched target identities, endpoint changes during an active
  file batch and Android name persistence.
- `flutter analyze --no-pub`: no issues found.
- Windows Release, portable ZIP and Inno Setup installer builds passed. All 26
  non-PDB Release files match the packaged directory; all 44 packaged files match
  their ZIP entries by SHA-256. Application binary version is `0.3.1+16`.
- Android Release build and APK v2 signature verification passed. Manifest
  versionName is 0.3.1 and versionCode is 16, retaining the local development signer.
- Covered the installed emulator using `adb install -r`, changed its device name
  through the app to `LDPlayer-Android`, restarted only the Android application,
  and confirmed the name persists while the ID remains unchanged. Capture:
  `../.impeccable/review/android-endpoint-name-persisted.png`.
- Temporary ADB inspection forwards were removed. No forwards or reverses remain.

No Windows process was stopped or replaced, and the Windows installer was not
executed. The actual physical phone's IP/discovery and a new native bidirectional
transfer were not verified in this incident. Earlier native transfer evidence
remains separate in `../.impeccable/review/chat-files-verification.md`.

## Artifacts

| Artifact in outputs/ | Bytes | SHA-256 |
| --- | ---: | --- |
| NearLink-0.3.1-windows-x64-Setup.exe | 13736873 | DCA0D12EE8982B0C888D668E4FF26BD2EC56CE0EF1A586AD666834B135DD3F68 |
| NearLink-0.3.1-windows-x64.zip | 16318218 | F27BA0AD1B84FDF0ADA87FE60A430A590570EA16849D3ABA447CF578B9066A83 |
| NearLink-0.3.1-android-preview.apk | 55464860 | 149D17A3E993D629DBB41D6560EF8202002E98626CF17E86574D664A6959390E |

Checksums are also in `outputs/NearLink-0.3.1-SHA256SUMS.txt`. The Windows installer
has no publisher code signature. Existing Android AGP/Kotlin future-migration
warnings did not prevent this build.
