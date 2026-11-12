# NearLink Android

Platform: Android. Mode: Operate. Inherit the blue, cool-white and mint identity,
brand assets and semantic colors in DESIGN.md. This is a native adaptation of the
existing product, not a replacement world. Mobile users send files between their
phone and computer, and exchange files/messages with colleagues on the same LAN.

## Direction Contract

THESIS: Select files, select a named device, send. Keep the complete send decision
within a compact phone workflow and retain visible progress and received results.
OWN-WORLD: Existing NearLink blue actions, cool-white workspace, mint receiving
identity, dark readable text and Lucide icons. Android system typography and
Material 3 components translate the desktop theme to touch. Minimum 48 dp targets.
STORY: Pick files or media, choose a device/group, send; open, export or share
received files. Messages use a conversation list and a dedicated chat view.
FIRST VIEWPORT: Native top app bar, compact file staging tool, nearby recipients,
recent activity, and five-destination navigation. Selected files reveal a fixed
send action above navigation. Expanded widths use a rail and split chat layout.
FORM: A working mobile utility, with safe-area/IME handling, system Back, long
press actions, native sheets, permission recovery and application lifecycle state.

## Quality Bar

The incumbent NearLink desktop theme is the visual reference. Android Material 3
navigation, sheets, system Back and 48 dp touch targets are the platform reference.
Task completion is the bar: all selected files stay individually manageable;
text-only sharing lands in its conversation; incoming decisions remain reachable
without scrolling the file list and reflect expired requests. Layout fixtures
cover 320 dp with 1.3x text, 390 dp phones, landscape and 1024 dp tablets. Widget
captures are preliminary layout evidence. Android 14 LDPlayer validation now covers
installation, native notification permission/actions, document picking/export,
system text sharing, multi-line hardware input and bidirectional file integrity.
Real phone IME resizing, same-Wi-Fi discovery and sustained background reception
remain required checks. See ../review/android-polish-verification.md for current
evidence and limits; ../review/android-verification.md retains the initial adaptation.

## Pages and Flows

Device, recipient and conversation lists prioritize online destinations. Shared
conversation sorting uses availability before recent message/file time, and a
group requires another online member to rank with online devices. Live presence
updates retain the selected conversation and text draft. Group member details
also put online members first without changing stored membership order.

- Send: compact file/media picker, a selected-file summary opening the complete
  removable queue, and staged shared text, recipient
  selection, explicit send command, current/recent progress. No desktop drag copy.
- Messages: individual white conversation cards matching the send-recipient
  cards, with 8 dp corners and spacing. The user requested this shared card style
  on 2026-11-09. A selected split-view conversation uses the existing blue tint.
  Recent timestamps, unread counts,
  long-press device remarks, groups,
  independent drafts and full chat. Keyboard keeps the composer reachable. System
  Back returns from the chat to its list before returning to the send destination.
  Chat attachments send directly to the captured conversation after confirming
  the native multi-file picker, without opening Send or changing its staged files.
  Text and local transfer records share a chronological timeline. File cards use
  white for incoming and blue tint for outgoing, 8 dp corners, file identity,
  readable status, real byte progress and speed, and tooltip-labelled actions.
  Incoming cards can accept/reject their entire batch; active cards can cancel,
  failed outgoing cards can retry, and completed files can open. Received files
  retain Android export/share actions. Group cards name each recipient/sender and
  show separate results. Previews and recency include files; drafts take priority.
  File cards follow local transfer-history retention and clear with those records.
- Devices: searchable compact rows grouped by online/offline state, with original
  identity, remark, online state,
  sending, messaging and long-press actions. Manual IP remains a discovery fallback.
- History: preserve the original individual file cards, spacing and four filters
  (all, active, received, failed). The user explicitly chose this layout over the
  batch expansion redesign on 2026-11-08. Each file stays directly visible with
  device/group identity and its full local creation timestamp to the second,
  right-aligned on the same metadata row as file size,
  which remains visible alongside active transfer speeds. This is record
  creation time, not completion time. Cards retain
  progress, retry and received file open/share/export commands. Files are initially stored in app-private storage;
  export uses the Android system document picker with no broad storage permission.
- Settings: local device name and summary entries opening dedicated subpages for
  receiving files, opt-in background reception,
  independent notices/sounds, connection information, diagnostics and version.
  The device identity and four entries use the same flat white, 8 dp-corner row
  treatment as Send and Messages, with 16 dp page insets, 8 dp entry gaps and
  blue/mint icon tiles. The device name allows two lines; the whole identity row
  opens editing. Detail pages retain this treatment, group related switches with
  inset dividers, and use the existing Lucide back/copy actions. A compact inline
  brand/version footer replaces the large stacked logo. Native phone/tablet,
  portrait/landscape and 1.3x-type evidence is in
  ../review/android-settings-verification.md.
  Windows title-bar, tray, startup and global screenshot controls do not appear.

Incoming requests use a compact overlay and a review bottom sheet with file details
and explicit per-request decisions. Exposed content stays interactive. Notifications
and their actions use Android channels. Background reception is an opt-in connected
device foreground service with a persistent notification and stop action; it does
not claim immunity to Android/OEM process termination. Network discovery holds a
multicast lock, and active transfers use a bounded native wake lock. No boot startup.

Android launch supplies app-private paths and the device model to the shared LAN
service. Existing wire protocol, integrity, groups, history and local remarks remain
shared. System shares stage data for explicit sending; no incoming share is sent
automatically. Existing Windows behavior and system design files are preserved.
