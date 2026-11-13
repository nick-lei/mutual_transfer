# NearLink desktop redesign

Mode: Operate. Scope: the complete Windows Flutter application shell and its
send, devices, messages, history, settings, and receiving-confirmation surfaces.

## Direction contract

THESIS: Quick sending leads. File selection and a named recipient share one
workspace; progress follows the action. Persistent navigation is familiar and
technical detail belongs in settings.

OWN-WORLD: Clear blue actions on a cool white canvas, a softly tinted shell,
dark readable text, restrained mint for success, and 12–16 px corners. One
Chinese-capable system font, generous clickable controls, consistent Lucide icons.
The approved brand mark is the open N formed by two rounded terminals. The
shared 36 px Brand image, Windows application icon and tray icon use the same
blue-background, white-and-mint artwork from assets/brand.

STORY: Choose what to send, choose who receives it, send, and understand the
outcome. Devices lead naturally into a dedicated conversation or a prepared send.

FIRST VIEWPORT: A 208 px sidebar and an integrated 64 px title bar frame the
workspace. The home has a large file drop/staging area and an adjacent recipient
list; current/recent transfers follow below. No permanent inspector or empty
metric strip. Narrow layouts stack the send/recipient areas and use a nav rail
or bottom navigation. The signature interaction is selecting a receiver and
seeing that named destination reflected in the final send action.

The title bar also exposes a tooltip-labelled sidebar toggle outside its drag
regions. Users can choose the full 208 px sidebar or 76 px icon rail; the choice
persists. Without an explicit choice, the existing width-based defaults apply.
Below 640 px, bottom navigation replaces the sidebar.

FORM: Task-first desktop workspace, modern and youthful as explicitly requested.
User confirmed personal and colleague use together. Impeccable Operate guidance
governs structure; Taste v2 contributes hierarchy, clear fields, and anti-template
composition, adapted to the explicitly requested desktop scope.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Motion: the drop area uses a 180 ms background transition and respects disabled
animations. Material controls retain framework state feedback; no decorative
entrance sequence.
Accessibility: readable 13–15 px body text, text labels for status, tooltips for
icon-only controls, keyboard activation, and responsive large-text checks.


## Five-page implementation plan and shipped composition

This plan describes the implemented native Flutter pages, not separate web routes.
All device, message and transfer content is provided by LanService. Synthetic
preview data belongs only in the test harness.

| Page | First task and content order | Actions and states | Responsive composition |
| --- | --- | --- | --- |
| 发送文件 | Page heading; file drop/staging area; explicit recipient; send summary; four current/recent transfers in independent cards matching History | Add files/folder, remove queued files, pick recipient, named send action, open received files; empty and busy states | At content width 660+, staging and recipient are adjacent with 20 gap; recipient width 280, or 350 above content width 1000. Below 660 they stack. Send footer stacks below 560. Transfer cards have 8 px corners and 12 px gaps on the page canvas, without a shared white container. |
| 附近设备 | Search and availability filter; device cards; this device | Connect manually, prepare a send, open a conversation; offline and no-match states | Card grid has 1/2/3 columns at content widths below 650 / 650+ / 1000+, with 16 gaps. |
| 即时消息 | Dedicated conversation list; selected conversation; chronological messages; composer | Unread badges, delivery/failure text, retry, send text; offline and empty states; sending recipient and conversation selection remain distinct | At available width 760+ show a 260-wide conversation list and adjacent conversation; below it use list/detail with a back action. |
| 传输记录 | Search; status and direction filters; independent file/recipient cards grouped by full calendar date | Device/group, full local creation timestamp to the second, separate progress/speed, status, cancel, retry, open received file and confirmed history cleanup | White 8 px cards with 12 px gaps; no shared day container. Below 600 px of card width, status and actions move beneath metadata. Filters wrap; content scrolls. Active tasks survive cleanup and received files remain. |
| 设置 | Device and receive settings; connection information; about | Edit device name and receiving directory, save/revert draft, open directory, copy local address; validation, busy and saved feedback | Name field max width 540. Selectable receiving path and tooltip-labelled edit/open icons share one field; below 320 scaled logical px the icons move below the path. Receive-confirmation information follows, then a divided, right-aligned save/revert footer. Connection rows stack below content width 520. |

## Shared flows and verification boundary

Home activity and History share selectable file cards. Single-click selection
uses the existing blue tint and a 1 px blue outline without resizing the card;
Ctrl+C copies the local file through the Windows file clipboard, and Escape
clears selection. A right-click selects the card and opens a white menu with a
Lucide Copy icon, Copy label and shortcut hint. Sent records use their original
local source (including rejected sends); receives require a completed saved
file. Missing files and unfinished receives disable the menu command. Existing
toast feedback reports success/failure. Copy bindings are scoped to card focus,
preserving ordinary copying in search and other text fields. Selection is single,
and Android retains its existing touch interactions.

Device and recipient lists put online destinations before offline ones. The
conversation list sorts by actual availability before message/file recency;
active groups require another online member to join the online portion. Group
details put online members first while retaining their original order within
each state. Presence updates reorder rows without changing the chosen chat,
drafts, unread state or stored membership order. Forward selectors and group
editors retain their existing online-first behavior.

Chat attachment controls now send directly in the selected conversation, using
the native multi-file picker. They preserve text drafts and the independent Send
queue. Text and local transfers share the chronological timeline; incoming white
or canvas cards and outgoing blue-tint cards show identity, size, real byte
progress/speed, status, batch accept/reject, cancellation, retry and file opening.
Group file cards identify each member separately. Conversation previews and
recency include files. Cards use the same records as History and share its local
retention/clearing behavior. This extension preserves the global visual system.

The shared receiving banner opens explicit offer review with sender, file count,
size and filenames before acceptance. Network notices remain visible above page
content. Manual connect is a dialog; its address source is 设置 → 连接信息.
The receiving prompt is a centered white floating panel, capped at 1120 px,
with 16 px corners and a soft downward shadow (ink at 12%, blur 28, offset 0/8).
It has 24/16 px outer horizontal margins, 16 px top and 8 px bottom spacing;
inner horizontal padding is 20/16 px. It is positioned above the page in a Stack,
outside the page's layout flow: arrival, expansion and dismissal never change
page geometry, available viewport height or scroll offset. It remains pinned
while the page scrolls underneath. There is no reserved notification band and
no full-window input barrier; exposed page regions remain interactive. The
panel can cover underlying content until the request is handled or collapsed.
A 40 px mint file-down icon anchors sender, count/size, pending-request count
and optional group source. Primary blue accept and secondary reject actions sit
beside a tooltip-labelled disclosure icon; at narrow widths or increased text
scale the actions move to a right-aligned second row. Expanded file rows use
13 px names, aligned sizes, separators and a 4 px scroll thumb in a bounded
list. A folder icon and ellipsized saving path form the footer; full paths are
available on hover. Confirmation remains explicit and targets only the shown
request. This refinement reuses existing tokens and does not replace DESIGN.md.
The title bar retains window drag, double-click maximize/restore, system menu and
window controls. Widths below 900 use the compact rail; below 640 use five-tab
bottom navigation. The live native implementation and Flutter tests are the
behavioral authority. HTML/CSS in the design sidecar is only a token preview.
The protocol migration and visual work do not prove real multi-machine file or message
transfer; the limitations remain in docs/PROTOCOL.md.

Settings includes a separate "启动与关闭" section: two mutually exclusive radio
options for closing to the tray or exiting, and an opt-in login-startup switch.
These settings save immediately, independently of the device-name/directory form.
Both radio labels are clickable. The options move below their label at narrow
widths or increased text scale, then wrap vertically as needed. Startup launches into
the tray; native tray initialization failure keeps a visible, escapable window.

Settings now includes local diagnostics between connection information and about.
View, folder and export are tooltip-labelled Lucide icon actions. The dedicated
log viewer uses a viewport-constrained 1000 x 720 tool dialog, a search field,
level menu, refresh/export/close icons and expandable list rows. Search and level
controls stack below 500 logical px; the settings actions stack below 440.
Recent entries are limited to 500 and update live. Loading, empty, no-match,
read-error and disk-write-error states use existing theme colors and typography.

Desktop notifications extend the existing settings surface after screenshot
settings. Two switches control file-request reminders and sound; test, refresh
and Windows-settings actions use tooltip-labelled Lucide icons. Larger text and
narrow widths wrap supporting copy without displacing switches. Permission and
save failures use readable status text. Background file requests use Windows
toasts with sender, count, size, filename and accept/reject actions; foreground
requests retain the receiving overlay. Opening a toast expands that exact offer.
The notification settings extension received a finish-review disposition of ship
at 800 and 320 logical pixels with 1.5 text scale. This review does not establish
physical Windows toast delivery on another computer.

Message attention extends this same world with danger-red numeric badges on
full/compact navigation, bottom navigation and conversation rows (99+ cap).
Badges remain visible for the selected conversation while the app is unfocused.
One persisted service-owned read state feeds all surfaces; foreground viewing
clears only that conversation. The native Windows tray inbox is 360 logical
pixels wide with 76-pixel sender rows, system-font names, red counts and latest
message previews. A white, softly rounded surface, blue-tinted row states and
Lucide monitor avatars follow the main application's existing theme. The header
contains the unread total and a chrome-free Lucide double-check action with a
tooltip and accessible name for marking all read; there is no footer button.
Mouse hover and keyboard focus use distinct states, and Tab reaches the action.
It scrolls after six rows, follows the tray monitor work area,
appears on hover or click, and supports mouse selection, arrows/Enter, Escape,
and marking all read. A persistent top-right red dot and 700 ms bright/dim logo
frames start immediately on attention, independently of client-area animation.
Tooltip updates precede the native attention frame so tray_manager cannot
overwrite its badge. Explorer restart and resume restore the current frame.
Overflow uses a trackless 4 px thumb, widening to 6 px on hover/drag within a
12 px hit area, with native listbox wheel/keyboard navigation and thumb dragging.
No overflow means no scrollbar or reserved gutter. Settings add independent message desktop-notification
and message-sound switches, with sound on by the user's explicit choice, plus
a tooltip-labelled sound-preview icon. The existing design tokens are retained.

Pending incoming file requests share the same tray surface, preceding message
rows with the existing receiving mint/green palette and Lucide file-down icon.
Each row names the sender, shows a file-count badge, and previews the first
filename and total size. File-only headers show the request count and omit the
read-all icon; mixed headers distinguish pending requests from unread messages.
The header double-check action is named "全部消息标为已读" and never decides files.
Mouse and keyboard activation restore the main window and expand that exact
pending request. Expired IDs report that the request is no longer available.
Handling, cancellation and expiry remove file attention. A Windows taskbar
numeric overlay counts pending requests plus unread messages (99+ cap); new
background attention requests native flashing, stopped on main-window activation.
Tray red-dot attention persists while either kind remains. Existing DESIGN.md
tokens and provenance are preserved; this is a behavior extension of the native
tray rather than a replacement visual system.

## Device Remarks and LAN Groups

This extension preserves DESIGN.md and its sidecar unchanged. Local 32-character
remarks are primary display names; the original device identity stays secondary
on device cards, recipient rows and private chat headers. Pencil actions use the
existing Lucide system and protected name-edit dialog. Search matches both names.
Device conversation rows also expose the same remark editor through a themed
right-click menu at the pointer. Offline devices are supported. Secondary click
does not select the conversation, consume unread, or alter the current draft;
Escape dismisses the menu. Group rows keep their group-name workflow.

The messages heading has one tooltip-labelled create-group action across widths.
Groups share the conversation list, independent drafts and unread counts, using
the existing mint/green palette and a Lucide users avatar. Incoming group messages
show the sender's local remark. Outgoing delivery counts open per-member results;
the compact retry icon targets failed recipients. No new navigation destination.

Create/edit uses a 480-wide, viewport-bounded, maximum 640-high dialog: group name,
device/remark search, checkbox member list, count including self, save footer.
Unsupported and offline new members are disabled with concrete status. Busy and
failure states stay in the dialog. Group details uses a 520-wide matching tool
dialog with member/file tabs; private-message, edit and close actions use icons.
Exit/dissolve remains a named destructive command with confirmation. Leaving is
local-first; re-adding requires the former member to explicitly rejoin. Inactive
groups retain readable history and disable the composer. Pending membership sync
is visible with a refresh action. Group file history is local to this device.

The home recipient panel gains a group picker and a clearly named selected group;
each receiver still confirms files. Network capabilities require compatible peers,
up to 32 members, direct fanout and per-recipient results, with no cloud/offline queue.
Verification uses current Flutter-rendered fixture captures at 1440, 720 and 440
logical pixels (1.3 text scale at 440), loopback networking, and platform-channel
notification tests; it does not establish physical multi-machine behavior.

## Transfer Completion Extension

Completion is a batch event: every file must be successfully committed before a
receiver or direct sender is notified. A group sender gets one aggregate after
every recipient succeeds. Partial failure, cancellation and rejection remain in
history without a misleading success prompt. Retries are new batches; reading
history or restarting the app never creates completion events.

Foreground uses a six-second white floating snackbar, green Lucide circle-check,
14 px semibold result and 12 px muted summary. The summary includes the local
peer name, file count and logical batch size, and group recipient count when
applicable. Two tooltip-labelled Lucide icon actions open history and dismiss the
prompt. Width is 560 on wide windows and constrained by the viewport on narrow
windows, above the bottom navigation. Colors, type and controls use the incumbent
system; DESIGN.md and its sidecar remain unchanged.

Background, minimized and tray states use Windows native notifications with the
same result and a history action. Independent completion-notice and completion-
sound switches sit between file-request and message controls in desktop settings.
Sound can also play in the foreground and is throttled to one per two seconds.
New installs enable both switches; upgrades initially inherit existing file notice
and sound preferences. Windows notification permissions and Do Not Disturb apply.

Current verification captures cover both directions at 1440x760 and 440x760
(1.3 text scale at 440), plus settings at 800x600 and 320x720 with 1.5 text scale.
These are Flutter fixtures, not physical Windows notification delivery evidence.
