#ifndef RUNNER_TRAY_INBOX_H_
#define RUNNER_TRAY_INBOX_H_

#include <windows.h>
#include <flutter/encodable_value.h>
#include <functional>
#include <optional>
#include <string>
#include <vector>

class TrayInbox {
 public:
  TrayInbox(HWND owner, std::function<void(const std::string&, bool)> open,
            std::function<void()> read_all);
  ~TrayInbox();
  flutter::EncodableMap Update(const flutter::EncodableList& entries);
  bool Show(bool activate, bool inspectable = false);
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  friend struct TrayInboxTest;
  struct Entry {
    std::string id;
    std::wstring name, preview;
    int count;
    bool file = false;
  };
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK ListProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam,
                                   UINT_PTR id, DWORD_PTR data);
  static LRESULT CALLBACK ActionProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam,
                                     UINT_PTR id, DWORD_PTR data);
  LRESULT OnMessage(UINT message, WPARAM wparam, LPARAM lparam);
  void OpenSelected();
  void PaintRow(const DRAWITEMSTRUCT& item);
  void PaintAction(const DRAWITEMSTRUCT& item);
  void PaintSurface(HDC dc);
  void UpdateIcon(bool dimmed);
  RECT ScrollTrack() const;
  RECT ScrollThumb() const;
  int VisibleRows() const;
  void ScrollTo(int top);
  void PaintScrollBar(HDC dc);
  void UpdateTaskbar(bool new_attention);
  void StopFlashing();
  int PendingRequests() const;
  int MessageCount() const;
  void Hide();
  int Scale(int value) const;
  HWND owner_, window_ = nullptr, list_ = nullptr, read_all_ = nullptr, tooltip_ = nullptr;
  HWND focused_control_ = nullptr;
  HFONT font_ = nullptr, title_font_ = nullptr, badge_font_ = nullptr, icon_font_ = nullptr;
  HANDLE lucide_resource_ = nullptr;
  ULONG_PTR gdiplus_token_ = 0;
  HICON icon_ = nullptr, unread_icon_ = nullptr, dimmed_icon_ = nullptr;
  UINT dpi_ = 96;
  bool blink_dimmed_ = false, pointer_near_ = false;
  bool tray_icon_applied_ = false, tray_blinking_ = false;
  bool scroll_hovered_ = false, scroll_dragging_ = false;
  int scroll_drag_offset_ = 0;
  int wheel_delta_ = 0;
  bool action_hovered_ = false, keyboard_focus_ = false;
  bool inspectable_ = false;
  bool taskbar_overlay_applied_ = false, taskbar_flashing_ = false;
  int hovered_row_ = -1;
  POINT last_pointer_{-1, -1};
  ULONGLONG outside_since_ = 0;
  std::vector<Entry> entries_;
  std::function<void(const std::string&, bool)> open_;
  std::function<void()> read_all_callback_;
};

#endif
