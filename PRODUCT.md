# 邻传 NearLink

<!-- impeccable:product-schema 1 -->

## Platform

Windows desktop and an Android mobile adaptation, implemented in Flutter.
Android uses a separate native host and adaptive touch layouts over the shared LAN
service. See `.impeccable/surfaces/android.md` and `docs/ANDROID.md` for its scope
and verification boundaries. Other platforms are not packaged or verified.
Distributed as a per-user Windows x64 installer and a portable ZIP. The installer
offers Simplified Chinese, a directory choice, Start menu entries and an optional
desktop shortcut. Upgrade and uninstall preserve application data and received files.

## Users

The user confirmed that personal cross-device transfers and transfers between
colleagues are equally important, with quick file sending as the home page's
primary task. The product operates on a shared local network.

## Product Purpose

Send files, folders, and text between nearby devices without an account or cloud
storage. Users should understand where a file is going, whether the receiver has
accepted it, and where a received file is saved.

## Capabilities and Constraints

- Existing LAN discovery, manual IPv4 connection, streamed file transfers,
  receiving confirmation, SHA-256 integrity checks, and text messaging.
- Real device and transfer data only. Delivered messages do not mean read.
- Up to 1000 files per batch. Folder paths are preserved; empty folders and
  symbolic links are not sent.
- Failed file transfers retry from the beginning. There is no pause/resume,
  pairing, cloud relay, or encryption capability to advertise.
- Local-only device remarks (32 characters), used consistently in device search,
  send recipients, conversations, transfer history, tray and notifications. The
  advertised device name remains available for identification and never includes remarks.
- LAN groups of up to 32 devices including self, with owner-managed names and
  membership, leaving/dissolving, retained history, direct member message fanout,
  recipient-specific delivery status and retries. Group control uses a versioned
  capability; older clients still support direct chats/files but cannot join groups.
- Group files use the existing confirmed transfer flow, with up to three concurrent
  receivers and separate per-recipient outcomes. Group files in details are this
  device's local transfer history, not a shared cloud file repository.
- Chat attachments send directly in the selected single or group conversation.
  Native picker confirmation sends the selected files without navigating away or
  changing the separate Send queue. Text and local file transfers share a timeline
  with real progress, speed, explicit receiving decisions, cancellation, retry and
  completed-file actions. Group cards identify each member's result. File cards
  use local transfer history and share its retention and clearing behavior.
- Completed chat files can be forwarded from their local source/received path.
  Desktop two-pane chats support dragging a file card onto another conversation;
  Android tablets support long-press dragging. Target feedback distinguishes
  available and unavailable destinations. A forward icon provides an alternative:
  Android opens a full-page searchable recipient selector with explicit confirmation,
  while desktop uses a compact selector. Forwarding opens the destination chat
  with the existing progress and receiving-confirmation flow, preserving drafts
  and the separate Send queue. Missing files, offline destinations, active
  transfers and dropping back on the source conversation cannot start a forward.
  Viewing the recipient selector does not consume messages in the covered chat.
- Group membership updates retry every 30 seconds and manually; offline messages
  are not queued for automatic delivery. Local leaving persists even if the owner
  is offline. Removed/dissolved group history remains readable. Existing members
  can communicate while the owner is offline, subject to LAN reachability.
- Device identity, settings, and limited history are persisted by LanService.
- Windows and Android device/recipient lists prioritize online devices. Chat
  conversations prioritize current availability before recent messages/files;
  groups are available only when active with another member online. Availability
  changes reorder lists without changing the selected conversation or its draft.
- Transfer history keeps each file/recipient record independently visible, with
  its device, optional group, result and full local creation timestamp to the
  second. Active transfer speeds do not replace timestamps. These are record
  creation times, not completion times; no new timing data is inferred.
- Offline device cards on Windows and Android show the locally observed last
  online time, with a precise timestamp on hover/long press. Times survive restart;
  legacy records and unseen group members remain unknown until observed online.
- Windows and Android device pages offer previewed cleanup of unused offline
  devices, with an automatic settings backup before removal. Online, manually
  connected, remarked, chatting, transferring and group-related devices are
  protected. Cleanup preserves device identity, history and received files;
  removed devices can be discovered again when they return online.
- Structured local diagnostics with bounded rotation, search, level filters,
  detail copying and JSONL export in settings. No chat bodies or file contents.
- Negotiated streaming SHA-256 with Windows CNG acceleration, bounded file
  buffers and receiver backpressure. Matching sender/receiver digests and an
  authenticated commit precede publication; legacy SHA headers remain supported.
- Preserve the integrated custom Windows title bar and graceful shutdown.
- Manually collapsible sidebar with persisted preference. Configurable close to
  system tray or exit, tray restore/capture/exit actions, and opt-in Windows
  login startup into the tray. Reopening the same instance restores its window.
- Windows native file-request notifications while the app is in the background,
  minimized, or in the tray; foreground requests use an in-app review overlay
  above the page, with no reserved space or page reflow. Exposed content remains
  interactive, and the panel stays fixed while the page scrolls underneath.
  Notifications identify the sender and files, open the matching request, and
  offer accept/reject actions. Reminder and sound preferences are configurable
  in settings, subject to Windows notification and Do Not Disturb settings.
- Batch completion reminders for both sending and receiving. Foreground completion
  prompts use the existing theme and open transfer history; background native
  notifications open the same destination. Reminders require every file to complete
  integrity checks and publication. Group senders get one aggregate after every
  recipient settles, with separate completed, rejected, incomplete and cancelled
  member counts. Each recipient's outcome is independent; mixed results use an
  amber notice and never claim that all files were sent. Direct send/receive
  success notices still require the entire batch to complete.
  Successful retries create new reminders; old history is never replayed. Completion
  notices and sound have independent persisted settings, with sound burst throttling.
- Persisted local unread message counts shared by full/compact navigation,
  bottom navigation, conversations and a Windows tray inbox. The tray groups
  senders, counts and latest previews, opens a chosen conversation, and supports
  marking all read. Only a focused visible conversation consumes unread messages.
  Background message toasts update per sender; message sounds default on with
  independent switches and burst throttling. These are local read states, not
  remote read receipts.
- Pending incoming file requests also drive tray attention, with separate green
  file rows opening the exact request. Marking messages read never handles files.
  Windows taskbar overlays count pending requests plus unread messages; new
  background attention requests taskbar flashing. Handled, cancelled and expired
  requests clear their attention.
- Tray attention starts without hover: a persistent red dot accompanies a
  bright/dim logo flash until attention is cleared. Overflow inboxes retain
  wheel, keyboard and drag scrolling with a slim trackless thumb.
- Windows screenshot capture with a configurable global shortcut; local region
  selection, rectangle/ellipse/arrow/pen/text annotations, undo/redo, clipboard,
  PNG saving, and explicit staging into the existing send flow. No OCR or translation.

## Brand Commitments

Name: 邻传 / NearLink. Chinese-first UI. The user explicitly requests a modern,
youthful theme and a complete reconsideration of page content and layout.

## Product Principles

- Start with sending, not statistics.
- Make recipient selection explicit and keep conversations distinct.
- Show meaningful progress, recoverable errors, and where to find the result.
- Keep settings and technical connection details out of the everyday send flow.
- Work well at narrow window widths and increased text scale.

## Evidence on Hand

Existing Flutter application, lib/lan_service.dart, lib/models.dart, and service
tests. The current implementation is the authority for supported functionality.
Test fixtures and screenshots may use synthetic devices only in the test harness.
