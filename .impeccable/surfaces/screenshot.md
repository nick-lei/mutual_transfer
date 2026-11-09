# Screenshot editor

Mode: Operate. Scope: Windows global shortcut, screenshot selection/annotation,
and its settings. An extension of the existing NearLink design system.

## Task and layout

The default Ctrl + Alt + A shortcut and persistent title-bar scan icon both
hide NearLink by default, freeze the virtual desktop, and open region selection. A
persistent settings switch, “截图时隐藏邻传”, can keep the app in the captured
desktop at its existing visibility and position without raising a minimized window.
The app is hidden after pixels are frozen so editor rendering cannot enter the capture. The
user drags a rectangle; everything outside it is dimmed. Eight handles resize
the selection, and the selection tool can move its crop rectangle. Marks stay
attached to source pixels while adjusting the crop.

A compact floating white icon toolbar follows the selection, preferring space below
or above it and remaining within the screen. It includes select, rectangle,
ellipse, arrow, pen, text, undo/redo, save, cancel, stage, and copy. Secondary
controls contain six colors and three stroke widths or text sizes, shown only for
the relevant tool. Tooltips name each icon and keyboard shortcut. Blue marks the
active tool, green completes/copies, and red cancels. A separate dark dimensions
label follows the upper-left edge outside the selection and updates while dragging;
it moves just inside the selection when the screen top leaves no room.

Text is entered directly on the screenshot at its final color and size, inside a
dashed editing frame with corner handles. Click blank space or Ctrl+Enter to commit;
click existing text with the text tool to re-edit, and Escape to cancel the edit.
The top/left frame edges move text, and the right edge adjusts wrapping width.
Font and color changes update the active text without hiding the toolbar.
Chinese IME is supported. Text changes/deletions preserve layer order and undo/redo.
Saving, copying, or staging exports source pixels and marks only.
The mask, handles, and toolbar never appear in the PNG.

## Settings and state

The screenshot settings section sits between device/receive settings and
connection information. It displays the current chord in an inline recorder,
the enabled switch, conflict errors, a manual capture action, and capture visibility.
Click or focus the chord field to record; release all keys to save automatically
and leave recording. Modifier-only presses and incomplete/invalid chords appear
immediately in the field. A completed chord remains visible while keys are released.
The already registered global chord is echoed into the recorder instead of capturing;
the native event may arrive before or after key release. Windows IME composition is
temporarily detached from the focused view while recording and restored on exit;
switching away from the app ends recording. Escape or clicking outside ends recording. Editing preserves
the enabled switch. Status confirmations and annotation/shortcut instructions are
omitted; only actionable errors appear. No separate edit button or dialog is used.

The native hotkey registration is replaced only after the candidate succeeds.
File persistence errors roll back the registration where possible. Capture failures
restore the window; clipboard/save failures retain the editor so the user can retry.
The workspace and any open application dialog remain mounted behind the editor.

## Boundaries

All image processing is local. OCR and translation are explicitly excluded by
the user. Staging does not send to a peer. Global shortcuts need a running process;
this change does not introduce a system tray or background service.
