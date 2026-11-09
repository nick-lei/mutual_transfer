# Device Remarks and LAN Groups: 0.2.0+9

## Delivered Scope

- Local-only device remarks, preserved across discovery and restart and used in
  device search, recipients, private/group message identity, transfer history,
  tray previews and desktop notifications. Original advertised names are retained.
- Real LAN groups with up to 32 devices, owner-managed names and members,
  local-first exit, dissolution, explicit rejoin after owner re-adds a device,
  persisted membership snapshots and retryable membership synchronization.
- Direct member message fanout, independent group drafts/read state, sender labels,
  recipient-specific outcomes, deduplication and retry only to failed recipients.
- Group files retain individual receiver confirmation and per-recipient transfer
  history. File sends use up to three simultaneous receiver sessions. The group
  details file tab is named "文件记录" to describe its local-history scope.
- Existing modern blue/cool-white/mint theme, Lucide icons, native tray attention,
  sounds and notification preferences are retained.

## Automated Evidence

- `flutter test --no-pub`: 120 passed.
- `flutter analyze --no-pub`: no issues.
- `flutter build windows --release --no-pub`: successful Windows x64 Release.
- Eight group-service tests use three independent services over loopback, temporary
  profiles and real HTTP/WebSocket/file traffic. They cover remark privacy and
  persistence, fanout and deduplication, owner-offline operation, failed-recipient
  retry, member removal and stale snapshots, dissolution, offline exit/restart,
  explicit rejoin, capability gating, name validation and individual file decisions.
- Widget tests cover group chat/details/editor/send-recipient at 1440, 720 and 440
  logical pixels, with 1.3 text scale at 440. Existing all-page/draft/IME/read-state
  tests remain passing. Remarks have rendered list/edit coverage.
- Platform-channel tests verify group identity and local-remark previews in tray
  payloads and desktop notification routing, without consuming unread on activation.

## Visual Evidence

All captures below are Flutter-rendered test fixtures with synthetic devices, not
physical desktop screenshots. Every image was opened and checked for valid content.

- `groups-chat-{1440,720,440}.png`
- `groups-details-{1440,720,440}.png`
- `groups-editor-{1440,720,440}.png`
- `groups-recipient-{1440,720,440}.png`
- `device-remarks.png`, `device-remark-editor.png`

A fresh Impeccable finish reviewer returned `ship` for this extension at the
supplied render/source scope. Two nonblocking observations were corrected in one
batch: creating a group from the send picker now selects it for the original send
task, and the file tab is labelled as records. The same reviewer scored both
`resolved`, inspecting the routing source and refreshed details renders at all
three widths. That verdict pass covers those two changes only.

`DESIGN.md` and `.impeccable/design.json` were preserved. Product truth, protocol,
README and the desktop surface brief were updated. No new raster asset was authored.
No HTML/CSS detector ran because this is native Flutter.

## Release Evidence

- Isolated Release smoke instance started with a temporary build profile, disabled
  screenshot hotkey, no discovery/notifications, and a dynamic TCP port.
- Its executable reports `0.2.0+9`; `/v1/info` returned `nearlink` with
  `streaming-sha256-v1` and `lan-groups-v1`. Only that verified test process was
  stopped, and no smoke process remained afterward.
- Packaged EXE and Dart `app.so` hashes match the final Release build.
- Installer compiled successfully from the checked package.
- `outputs/NearLink-0.2.0-windows-x64-Setup.exe`
- Setup SHA-256: `2E44FA28AE2EDE9FF892FDC38D6933CD0C1B38679F8A4C48D816C9EFC7A47625`
- `outputs/NearLink-0.2.0-windows-x64.zip`

## Verification Boundary

The user's installed running application was not replaced or stopped. Installer
installation/upgrade was not rerun because it would affect active applications;
this release verifies compilation, payload consistency and isolated runtime startup.
No physical multi-computer LAN, router/firewall, or actual Windows notification
delivery claim follows from the loopback and platform-channel tests.

Group members require compatible versions (0.2.0 or later). Messages do not have
an automatic offline delivery queue; failed recipients require retry. Membership
changes retry every 30 seconds and manually. A device that has not received a
removal/dissolution snapshot can retain stale membership until synchronization
recovers. Declared LAN identity is not cryptographic authentication. File records
are local and not a shared repository for later members to download from.
