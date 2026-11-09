#include "tray_inbox.h"

#include <commctrl.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <windowsx.h>
#include <algorithm>
#include <objidl.h>
// Older Windows SDK GDI+ headers expect unqualified min/max with NOMINMAX.
namespace Gdiplus { using std::min; using std::max; }
#pragma warning(push)
#pragma warning(disable : 4458)
#include <gdiplus.h>
#pragma warning(pop)
#include <utility>
#include "resource.h"

namespace {
constexpr UINT_PTR kAlertTimer = 0x4E4C;
constexpr UINT_PTR kHoverTimer = 0x4E4D;
constexpr UINT_PTR kIconRestoreTimer = 0x4E4E;
constexpr UINT_PTR kDismissTimer = 1;
constexpr COLORREF kInk = RGB(23, 35, 58);
constexpr COLORREF kMuted = RGB(98, 113, 138);
constexpr COLORREF kRed = RGB(184, 61, 78);
constexpr COLORREF kBlue = RGB(36, 99, 235);
constexpr COLORREF kBlueTint = RGB(234, 240, 255);
constexpr COLORREF kLine = RGB(224, 231, 242);
constexpr COLORREF kGreen = RGB(20, 125, 90);
constexpr COLORREF kMint = RGB(231, 246, 239);
constexpr COLORREF kSelectedMuted = RGB(83, 97, 122);
constexpr int kRowHeight = 76;
// Lucide 4.0.2 glyphs, shared with the Flutter application's icon family.
constexpr wchar_t kMonitor[] = L"\xE11D";
constexpr wchar_t kCheckCheck[] = L"\xE38E";
constexpr wchar_t kFileDown[] = L"\xE318";

std::wstring Wide(const std::string& value) {
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), length);
  return result;
}

void Fill(HDC dc, const RECT& rect, COLORREF color) {
  HBRUSH brush = CreateSolidBrush(color);
  FillRect(dc, &rect, brush);
  DeleteObject(brush);
}

void Text(HDC dc, const std::wstring& value, RECT rect, COLORREF color) {
  SetTextColor(dc, color);
  SetBkMode(dc, TRANSPARENT);
  DrawTextW(dc, value.c_str(), static_cast<int>(value.size()), &rect,
            DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
}

void Rounded(HDC dc, const RECT& rect, int radius, COLORREF fill,
             std::optional<COLORREF> outline = std::nullopt) {
  Gdiplus::Graphics graphics(dc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  const auto x = static_cast<Gdiplus::REAL>(rect.left) + 0.5f;
  const auto y = static_cast<Gdiplus::REAL>(rect.top) + 0.5f;
  const auto width = static_cast<Gdiplus::REAL>(rect.right - rect.left) - 1;
  const auto height = static_cast<Gdiplus::REAL>(rect.bottom - rect.top) - 1;
  const auto diameter = static_cast<Gdiplus::REAL>(radius * 2);
  Gdiplus::GraphicsPath path;
  path.AddArc(x, y, diameter, diameter, 180, 90);
  path.AddArc(x + width - diameter, y, diameter, diameter, 270, 90);
  path.AddArc(x + width - diameter, y + height - diameter, diameter, diameter, 0, 90);
  path.AddArc(x, y + height - diameter, diameter, diameter, 90, 90);
  path.CloseFigure();
  auto color = [](COLORREF value) { return Gdiplus::Color(255, GetRValue(value), GetGValue(value), GetBValue(value)); };
  Gdiplus::SolidBrush brush(color(fill));
  graphics.FillPath(&brush, &path);
  if (outline) {
    Gdiplus::Pen pen(color(*outline), 1);
    graphics.DrawPath(&pen, &path);
  }
}

void Glyph(HDC dc, HFONT font, const wchar_t* value, RECT rect, COLORREF color) {
  const auto previous = SelectObject(dc, font);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, color);
  DrawTextW(dc, value, -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
  SelectObject(dc, previous);
}
}

TrayInbox::TrayInbox(HWND owner, std::function<void(const std::string&, bool)> open,
                     std::function<void()> read_all)
    : owner_(owner), open_(std::move(open)), read_all_callback_(std::move(read_all)) {
  const auto instance = GetModuleHandle(nullptr);
  Gdiplus::GdiplusStartupInput gdiplus_input;
  Gdiplus::GdiplusStartup(&gdiplus_token_, &gdiplus_input, nullptr);
  const auto font_resource = FindResourceW(instance, MAKEINTRESOURCEW(IDR_LUCIDE_TRAY), RT_RCDATA);
  if (font_resource) {
    const auto resource = LoadResource(instance, font_resource);
    DWORD font_count = 0;
    lucide_resource_ = AddFontMemResourceEx(LockResource(resource), SizeofResource(instance, font_resource), nullptr, &font_count);
  }
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = L"NearLink.TrayInbox";
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH));
  RegisterClassW(&window_class);
  window_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
      window_class.lpszClassName, L"邻传通知", WS_POPUP | WS_CLIPCHILDREN,
      0, 0, 360, 200, nullptr, nullptr, instance, this);
  list_ = CreateWindowExW(0, L"LISTBOX", L"待处理文件与未读会话",
      WS_CHILD | WS_VISIBLE | WS_TABSTOP | LBS_OWNERDRAWFIXED |
      LBS_HASSTRINGS | LBS_NOINTEGRALHEIGHT | LBS_NOTIFY,
      0, 0, 0, 0, window_, reinterpret_cast<HMENU>(100), instance, nullptr);
  SetWindowSubclass(list_, ListProc, 1, reinterpret_cast<DWORD_PTR>(this));
  read_all_ = CreateWindowExW(0, L"BUTTON", L"全部消息标为已读",
      WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
      0, 0, 0, 0, window_, reinterpret_cast<HMENU>(101), instance, nullptr);
  SetWindowSubclass(read_all_, ActionProc, 1, reinterpret_cast<DWORD_PTR>(this));
  tooltip_ = CreateWindowExW(WS_EX_TOPMOST, TOOLTIPS_CLASSW, nullptr, WS_POPUP | TTS_ALWAYSTIP | TTS_NOPREFIX,
      CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, window_, nullptr, instance, nullptr);
  TOOLINFOW tool{sizeof(tool)};
  tool.uFlags = TTF_IDISHWND | TTF_SUBCLASS;
  tool.hwnd = window_;
  tool.uId = reinterpret_cast<UINT_PTR>(read_all_);
  tool.lpszText = const_cast<wchar_t*>(L"全部消息标为已读");
  SendMessageW(tooltip_, TTM_ADDTOOLW, 0, reinterpret_cast<LPARAM>(&tool));
  SendMessage(tooltip_, TTM_SETDELAYTIME, TTDT_INITIAL, 450);
  icon_ = static_cast<HICON>(LoadImageW(instance, MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON, 32, 32, 0));

  // The tray manager owns its base icon. Keep our badge resources independent.
  HDC screen = GetDC(nullptr);
  HDC memory = CreateCompatibleDC(screen);
  BITMAPINFO bitmap{};
  bitmap.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap.bmiHeader.biWidth = 32;
  bitmap.bmiHeader.biHeight = -32;
  bitmap.bmiHeader.biPlanes = 1;
  bitmap.bmiHeader.biBitCount = 32;
  void* pixels = nullptr;
  HBITMAP color = CreateDIBSection(screen, &bitmap, DIB_RGB_COLORS, &pixels, nullptr, 0);
  HGDIOBJ previous = SelectObject(memory, color);
  ZeroMemory(pixels, 32 * 32 * 4);
  DrawIconEx(memory, 0, 0, icon_, 32, 32, 0, nullptr, DI_NORMAL);
  auto* rgba = static_cast<DWORD*>(pixels);
  const DWORD mask_pixels[32]{};
  HBITMAP mask = CreateBitmap(32, 32, 1, 1, mask_pixels);
  ICONINFO info{TRUE, 0, 0, mask, color};
  for (int frame = 0; frame < 2; ++frame) {
    for (int y = 0; y < 32; ++y) {
      for (int x = 0; x < 32; ++x) {
        auto& pixel = rgba[y * 32 + x];
        if (frame == 1) {
          DWORD faded = 0;
          for (int shift = 0; shift < 32; shift += 8) faded |= (((pixel >> shift) & 255) * 35 / 100) << shift;
          pixel = faded;
        }
        const int distance = (x - 24) * (x - 24) + (y - 8) * (y - 8);
        if (distance <= 64) pixel = distance <= 36 ? 0xFFB83D4E : 0xFFFFFFFF;
      }
    }
    if (frame == 0) unread_icon_ = CreateIconIndirect(&info);
    else dimmed_icon_ = CreateIconIndirect(&info);
  }
  SelectObject(memory, previous);
  DeleteObject(mask);
  DeleteObject(color);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
}

TrayInbox::~TrayInbox() {
  entries_.clear();
  UpdateTaskbar(false);
  KillTimer(owner_, kAlertTimer);
  KillTimer(owner_, kHoverTimer);
  KillTimer(owner_, kIconRestoreTimer);
  if (window_) DestroyWindow(window_);
  if (font_) DeleteObject(font_);
  if (title_font_) DeleteObject(title_font_);
  if (badge_font_) DeleteObject(badge_font_);
  if (icon_font_) DeleteObject(icon_font_);
  if (lucide_resource_) RemoveFontMemResourceEx(lucide_resource_);
  if (icon_) DestroyIcon(icon_);
  if (unread_icon_) DestroyIcon(unread_icon_);
  if (dimmed_icon_) DestroyIcon(dimmed_icon_);
  if (gdiplus_token_) Gdiplus::GdiplusShutdown(gdiplus_token_);
}

int TrayInbox::Scale(int value) const { return MulDiv(value, dpi_, 96); }

flutter::EncodableMap TrayInbox::Update(const flutter::EncodableList& entries) {
  const auto previous_entries = entries_;
  const int previous_top = static_cast<int>(SendMessage(list_, LB_GETTOPINDEX, 0, 0));
  std::string selected_id;
  const auto selected = SendMessage(list_, LB_GETCURSEL, 0, 0);
  if (selected >= 0 && static_cast<size_t>(selected) < entries_.size()) selected_id = entries_[selected].id;
  entries_.clear();
  hovered_row_ = -1;
  SendMessage(list_, LB_RESETCONTENT, 0, 0);
  for (const auto& value : entries) {
    const auto* data = std::get_if<flutter::EncodableMap>(&value);
    if (!data) continue;
    auto string = [&](const char* key) {
      const auto found = data->find(flutter::EncodableValue(key));
      return found != data->end() && std::holds_alternative<std::string>(found->second)
          ? std::get<std::string>(found->second) : std::string();
    };
    const auto count = data->find(flutter::EncodableValue("count"));
    if (count == data->end() || !std::holds_alternative<int32_t>(count->second)) continue;
    const bool file = string("type") == "file";
    Entry entry{string(file ? "offerId" : "peerId"), Wide(string("name")), Wide(string("preview")),
        std::get<int32_t>(count->second), file};
    if (entry.count <= 0 || entry.id.empty()) continue;
    const auto accessible = entry.name + L"，" + std::to_wstring(entry.count) +
        (file ? L" 个文件待接收，" : L" 条未读消息，") + entry.preview;
    SendMessageW(list_, LB_ADDSTRING, 0, reinterpret_cast<LPARAM>(accessible.c_str()));
    entries_.push_back(std::move(entry));
  }
  for (size_t index = 0; index < entries_.size(); ++index) {
    if (entries_[index].id == selected_id) SendMessage(list_, LB_SETCURSEL, index, 0);
  }
  SendMessage(list_, LB_SETTOPINDEX, previous_top, 0);
  const bool new_attention = std::any_of(entries_.begin(), entries_.end(), [&](const auto& entry) {
    const auto previous = std::find_if(previous_entries.begin(), previous_entries.end(), [&](const auto& old) {
      return old.id == entry.id && old.file == entry.file;
    });
    return previous == previous_entries.end() || entry.count > previous->count;
  });
  UpdateTaskbar(new_attention);
  const bool has_messages = MessageCount() > 0;
  if (!has_messages && GetFocus() == read_all_) SetFocus(list_);
  if (!has_messages && focused_control_ == read_all_) focused_control_ = list_;
  EnableWindow(read_all_, has_messages);
  ShowWindow(read_all_, has_messages ? SW_SHOWNA : SW_HIDE);
  if (entries_.empty()) {
    KillTimer(owner_, kAlertTimer);
    tray_blinking_ = false;
    Hide();
    UpdateIcon(false);
  } else {
    UpdateIcon(previous_entries.empty() ? false : blink_dimmed_);
    if (!tray_blinking_) tray_blinking_ = SetTimer(owner_, kAlertTimer, 700, nullptr) != 0;
    if (IsWindowVisible(window_)) Show(GetForegroundWindow() == window_, inspectable_);
  }
  return {
    {flutter::EncodableValue("trayIconApplied"), flutter::EncodableValue(tray_icon_applied_)},
    {flutter::EncodableValue("trayBlinking"), flutter::EncodableValue(tray_blinking_)},
    {flutter::EncodableValue("taskbarOverlayApplied"), flutter::EncodableValue(taskbar_overlay_applied_)},
    {flutter::EncodableValue("taskbarFlashRequested"), flutter::EncodableValue(taskbar_flashing_)},
  };
}

int TrayInbox::PendingRequests() const {
  return static_cast<int>(std::count_if(entries_.begin(), entries_.end(), [](const auto& entry) { return entry.file; }));
}

int TrayInbox::MessageCount() const {
  int total = 0;
  for (const auto& entry : entries_) if (!entry.file) total += entry.count;
  return total;
}

void TrayInbox::StopFlashing() {
  FLASHWINFO flash{sizeof(flash), owner_, FLASHW_STOP, 0, 0};
  FlashWindowEx(&flash);
  taskbar_flashing_ = false;
}

void TrayInbox::UpdateTaskbar(bool new_attention) {
  const int pending = PendingRequests(), unread = MessageCount();
  const int total = pending + unread;
  if (total == 0 || GetForegroundWindow() == owner_) StopFlashing();
  else if (new_attention) {
    FLASHWINFO flash{sizeof(flash), owner_, FLASHW_TRAY | FLASHW_TIMERNOFG, 0, 0};
    FlashWindowEx(&flash);
    taskbar_flashing_ = true;
  }
  HICON overlay = nullptr;
  if (total > 0) {
    Gdiplus::Bitmap bitmap(32, 32, PixelFormat32bppARGB);
    Gdiplus::Graphics graphics(&bitmap);
    graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
    Gdiplus::Color badge_color;
    badge_color.SetFromCOLORREF(kRed);
    Gdiplus::SolidBrush badge(badge_color);
    graphics.FillEllipse(&badge, 1, 1, 30, 30);
    Gdiplus::Font font(L"Segoe UI", total > 99 ? 13.0f : 18.0f, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    Gdiplus::SolidBrush white(Gdiplus::Color(255, 255, 255, 255));
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    const auto text = total > 99 ? L"99+" : std::to_wstring(total);
    graphics.DrawString(text.c_str(), -1, &font, Gdiplus::RectF(0, 0, 32, 32), &format, &white);
    bitmap.GetHICON(&overlay);
  }
  ITaskbarList3* taskbar = nullptr;
  taskbar_overlay_applied_ = false;
  if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar)))) {
    const auto description = L"邻传：" + std::to_wstring(pending) + L" 个待接收请求，" + std::to_wstring(unread) + L" 条未读消息";
    if (SUCCEEDED(taskbar->HrInit()) && (total == 0 || overlay)) {
      taskbar_overlay_applied_ = SUCCEEDED(taskbar->SetOverlayIcon(owner_, overlay, description.c_str()));
    }
    taskbar->Release();
  }
  if (overlay) DestroyIcon(overlay);
}

void TrayInbox::UpdateIcon(bool dimmed) {
  blink_dimmed_ = dimmed;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = owner_;
  data.uID = 1;
  data.uFlags = NIF_ICON;
  data.hIcon = entries_.empty() ? icon_ : (dimmed ? dimmed_icon_ : unread_icon_);
  tray_icon_applied_ = Shell_NotifyIconW(NIM_MODIFY, &data) != FALSE;
}

int TrayInbox::VisibleRows() const {
  RECT bounds{};
  GetClientRect(list_, &bounds);
  return std::max(1, static_cast<int>(bounds.bottom) / Scale(kRowHeight));
}

RECT TrayInbox::ScrollTrack() const {
  RECT bounds{};
  GetClientRect(window_, &bounds);
  if (static_cast<int>(entries_.size()) <= VisibleRows()) return {};
  return {bounds.right - Scale(20), Scale(66), bounds.right - Scale(8), bounds.bottom - Scale(10)};
}

RECT TrayInbox::ScrollThumb() const {
  auto track = ScrollTrack();
  if (IsRectEmpty(&track)) return {};
  const int height = track.bottom - track.top;
  const int count = static_cast<int>(entries_.size()), visible = VisibleRows();
  const int thumb_height = std::min(height, std::max(Scale(32), height * visible / count));
  const int top = static_cast<int>(SendMessage(list_, LB_GETTOPINDEX, 0, 0));
  track.top += MulDiv(height - thumb_height, top, count - visible);
  track.bottom = track.top + thumb_height;
  return track;
}

void TrayInbox::ScrollTo(int top) {
  const int maximum = std::max(0, static_cast<int>(entries_.size()) - VisibleRows());
  SendMessage(list_, LB_SETTOPINDEX, std::clamp(top, 0, maximum), 0);
  hovered_row_ = -1;
  InvalidateRect(list_, nullptr, FALSE);
  InvalidateRect(window_, nullptr, FALSE);
}

void TrayInbox::PaintScrollBar(HDC dc) {
  auto thumb = ScrollThumb();
  if (IsRectEmpty(&thumb)) return;
  const int width = Scale(scroll_hovered_ || scroll_dragging_ ? 6 : 4);
  const int center = (thumb.left + thumb.right) / 2;
  thumb.left = center - width / 2;
  thumb.right = thumb.left + width;
  Rounded(dc, thumb, width / 2, scroll_hovered_ || scroll_dragging_ ? kMuted : RGB(135, 150, 175));
}

bool TrayInbox::Show(bool activate, bool inspectable) {
  if (entries_.empty() || !window_) return false;
  // Standalone verification keeps the panel targetable while tools change focus.
  inspectable_ = inspectable;
  const auto style = GetWindowLongPtr(window_, GWL_EXSTYLE) & ~(WS_EX_TOOLWINDOW | WS_EX_APPWINDOW);
  SetWindowLongPtr(window_, GWL_EXSTYLE, style | (inspectable_ ? WS_EX_APPWINDOW : WS_EX_TOOLWINDOW));
  POINT cursor{};
  GetCursorPos(&cursor);
  NOTIFYICONIDENTIFIER identity{};
  identity.cbSize = sizeof(identity);
  identity.hWnd = owner_;
  identity.uID = 1;
  RECT anchor{};
  if (FAILED(Shell_NotifyIconGetRect(&identity, &anchor))) {
    anchor = {cursor.x, cursor.y, cursor.x + 1, cursor.y + 1};
  }
  MONITORINFO monitor{sizeof(monitor)};
  GetMonitorInfo(MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST), &monitor);
  const int left = monitor.rcWork.left, top = monitor.rcWork.top;
  const int right = monitor.rcWork.right, bottom = monitor.rcWork.bottom;
  SetWindowPos(window_, nullptr, anchor.left, anchor.top, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER);
  dpi_ = GetDpiForWindow(window_);
  if (font_) DeleteObject(font_);
  if (title_font_) DeleteObject(title_font_);
  if (badge_font_) DeleteObject(badge_font_);
  if (icon_font_) DeleteObject(icon_font_);
  font_ = CreateFontW(-Scale(13), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
      DEFAULT_PITCH, L"Microsoft YaHei UI");
  title_font_ = CreateFontW(-Scale(14), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
      DEFAULT_PITCH, L"Microsoft YaHei UI");
  badge_font_ = CreateFontW(-Scale(12), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
      DEFAULT_PITCH, L"Segoe UI");
  icon_font_ = CreateFontW(-Scale(22), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
      DEFAULT_PITCH, L"Lucide");
  SendMessage(list_, WM_SETFONT, reinterpret_cast<WPARAM>(font_), TRUE);
  SendMessage(read_all_, WM_SETFONT, reinterpret_cast<WPARAM>(font_), TRUE);
  const int width = std::min(Scale(360), right - left);
  const int list_height = std::min(Scale(kRowHeight) * static_cast<int>(entries_.size()),
      std::min(Scale(kRowHeight * 6), bottom - top - Scale(96)));
  const int height = list_height + Scale(72);
  const int x = std::clamp(static_cast<int>(anchor.right) - width, left, right - width);
  int y = anchor.top - height - Scale(8);
  if (y < monitor.rcWork.top) y = anchor.bottom + Scale(8);
  y = std::clamp(y, top, bottom - height);
  SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
  SetWindowRgn(window_, CreateRoundRectRgn(0, 0, width + 1, height + 1, Scale(24), Scale(24)), TRUE);
  SendMessage(list_, LB_SETITEMHEIGHT, 0, Scale(kRowHeight));
  const bool overflow = list_height < Scale(kRowHeight) * static_cast<int>(entries_.size());
  MoveWindow(list_, Scale(8), Scale(64), width - Scale(overflow ? 28 : 16), list_height, TRUE);
  MoveWindow(read_all_, width - Scale(52), Scale(10), Scale(40), Scale(40), TRUE);
  InvalidateRect(window_, nullptr, TRUE);
  ShowWindow(window_, activate ? SW_SHOW : SW_SHOWNOACTIVATE);
  if (activate) {
    SetForegroundWindow(window_);
    if (SendMessage(list_, LB_GETCURSEL, 0, 0) < 0) SendMessage(list_, LB_SETCURSEL, 0, 0);
    if (GetFocus() != read_all_) SetFocus(list_);
  }
  outside_since_ = 0;
  if (!inspectable_) SetTimer(window_, kDismissTimer, 100, nullptr);
  return IsWindowVisible(window_) != FALSE;
}

void TrayInbox::Hide() {
  scroll_dragging_ = false;
  scroll_hovered_ = false;
  if (GetCapture() == window_) ReleaseCapture();
  ShowWindow(window_, SW_HIDE);
  KillTimer(window_, kDismissTimer);
  pointer_near_ = false;
  hovered_row_ = -1;
  action_hovered_ = false;
  keyboard_focus_ = false;
  last_pointer_ = {-1, -1};
}

std::optional<LRESULT> TrayInbox::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  static const UINT taskbar_created = RegisterWindowMessageW(L"TaskbarButtonCreated");
  static const UINT explorer_created = RegisterWindowMessageW(L"TaskbarCreated");
  if (message == taskbar_created) UpdateTaskbar(false);
  if (message == explorer_created || (message == WM_POWERBROADCAST &&
      (wparam == PBT_APMRESUMEAUTOMATIC || wparam == PBT_APMRESUMESUSPEND))) {
    // Let tray_manager recreate the shell icon before restoring our status frame.
    SetTimer(owner_, kIconRestoreTimer, 150, nullptr);
  }
  if (message == WM_TIMER && wparam == kIconRestoreTimer) {
    KillTimer(owner_, kIconRestoreTimer);
    UpdateIcon(blink_dimmed_);
    UpdateTaskbar(false);
    return 0;
  }
  if (message == WM_ACTIVATE && LOWORD(wparam) != WA_INACTIVE) StopFlashing();
  if (message == WM_TIMER && wparam == kAlertTimer) {
    UpdateIcon(!blink_dimmed_);
    return 0;
  }
  if (message == WM_TIMER && wparam == kHoverTimer) {
    KillTimer(owner_, kHoverTimer);
    POINT cursor{};
    GetCursorPos(&cursor);
    NOTIFYICONIDENTIFIER identity{};
    identity.cbSize = sizeof(identity); identity.hWnd = owner_; identity.uID = 1;
    RECT rect{};
    if (SUCCEEDED(Shell_NotifyIconGetRect(&identity, &rect)) && PtInRect(&rect, cursor)) Show(false);
    else pointer_near_ = false;
    return 0;
  }
  // tray_manager uses WM_USER + 1 and icon identifier 1 on Windows.
  if (message != WM_USER + 1 || wparam != 1) return std::nullopt;
  if (lparam == WM_MOUSEMOVE && !entries_.empty()) {
    if (!pointer_near_) {
      pointer_near_ = true;
      SetTimer(owner_, kHoverTimer, 300, nullptr);
    }
  } else if (lparam == WM_LBUTTONUP && !entries_.empty()) {
    Show(true);
    return 0;
  } else if (lparam == WM_RBUTTONUP) {
    Hide();
  }
  return std::nullopt;
}

void TrayInbox::OpenSelected() {
  const auto selected = SendMessage(list_, LB_GETCURSEL, 0, 0);
  if (selected < 0 || static_cast<size_t>(selected) >= entries_.size()) return;
  const auto id = entries_[selected].id;
  const bool file = entries_[selected].file;
  Hide();
  open_(id, file);
}

void TrayInbox::PaintRow(const DRAWITEMSTRUCT& item) {
  if (item.itemID >= entries_.size()) return;
  const auto& entry = entries_[item.itemID];
  const auto accent = entry.file ? kGreen : kBlue;
  const auto tint = entry.file ? kMint : kBlueTint;
  const bool selected = hovered_row_ >= 0 ? item.itemID == static_cast<UINT>(hovered_row_)
      : (item.itemState & ODS_SELECTED) != 0;
  Fill(item.hDC, item.rcItem, RGB(255, 255, 255));
  RECT surface = item.rcItem;
  InflateRect(&surface, 0, -Scale(2));
  if (selected) Rounded(item.hDC, surface, Scale(12), tint);
  if (keyboard_focus_ && (item.itemState & ODS_FOCUS)) {
    Rounded(item.hDC, surface, Scale(12), tint, accent);
  }
  HGDIOBJ previous_font = SelectObject(item.hDC, title_font_);
  const int top = item.rcItem.top;
  RECT avatar{Scale(12), top + Scale(18), Scale(52), top + Scale(58)};
  Rounded(item.hDC, avatar, Scale(12), selected ? accent : tint);
  Glyph(item.hDC, icon_font_, entry.file ? kFileDown : kMonitor, avatar, selected ? RGB(255, 255, 255) : accent);
  const auto count = entry.count > 99 ? L"99+" : std::to_wstring(entry.count);
  SelectObject(item.hDC, badge_font_);
  SIZE count_size{};
  GetTextExtentPoint32W(item.hDC, count.c_str(), static_cast<int>(count.size()), &count_size);
  const int badge_width = std::max(Scale(20), static_cast<int>(count_size.cx) + Scale(12));
  RECT badge{item.rcItem.right - Scale(12) - badge_width, top + Scale(28),
      item.rcItem.right - Scale(12), top + Scale(48)};
  SelectObject(item.hDC, title_font_);
  Text(item.hDC, entry.name, {Scale(64), top + Scale(14), badge.left - Scale(12), top + Scale(36)}, kInk);
  SelectObject(item.hDC, font_);
  Text(item.hDC, entry.preview, {Scale(64), top + Scale(39), badge.left - Scale(12), top + Scale(61)},
       selected ? (entry.file ? kGreen : kSelectedMuted) : kMuted);
  Rounded(item.hDC, badge, Scale(10), entry.file ? kGreen : kRed);
  SelectObject(item.hDC, badge_font_);
  SetTextColor(item.hDC, RGB(255, 255, 255));
  DrawTextW(item.hDC, count.c_str(), -1, &badge, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SelectObject(item.hDC, previous_font);
}

void TrayInbox::PaintAction(const DRAWITEMSTRUCT& item) {
  Fill(item.hDC, item.rcItem, RGB(255, 255, 255));
  RECT bounds = item.rcItem;
  InflateRect(&bounds, -Scale(2), -Scale(2));
  const bool focused = keyboard_focus_ && (item.itemState & ODS_FOCUS);
  const bool pressed = (item.itemState & ODS_SELECTED) != 0;
  if (focused || action_hovered_ || pressed) {
    Rounded(item.hDC, bounds, Scale(8), kBlueTint, focused ? std::optional<COLORREF>(kBlue) : std::nullopt);
  }
  Glyph(item.hDC, icon_font_, kCheckCheck, bounds, kBlue);
}

LRESULT CALLBACK TrayInbox::ListProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam,
                                    UINT_PTR, DWORD_PTR data) {
  auto* self = reinterpret_cast<TrayInbox*>(data);
  if (message == WM_MOUSEWHEEL) {
    self->wheel_delta_ += GET_WHEEL_DELTA_WPARAM(wparam);
    const int steps = self->wheel_delta_ / WHEEL_DELTA;
    self->wheel_delta_ %= WHEEL_DELTA;
    UINT lines = 3;
    SystemParametersInfo(SPI_GETWHEELSCROLLLINES, 0, &lines, 0);
    const int rows = lines == WHEEL_PAGESCROLL ? self->VisibleRows()
        : static_cast<int>(std::min(lines, static_cast<UINT>(self->entries_.size())));
    const int top = static_cast<int>(SendMessage(window, LB_GETTOPINDEX, 0, 0));
    self->ScrollTo(top - steps * rows);
    return 0;
  }
  if (message == WM_SETFOCUS) self->focused_control_ = window;
  if (message == WM_MOUSEMOVE) {
    const POINT pointer{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    if (pointer.x != self->last_pointer_.x || pointer.y != self->last_pointer_.y) {
      self->last_pointer_ = pointer;
      const bool was_keyboard = self->keyboard_focus_;
      self->keyboard_focus_ = false;
      const auto hit = SendMessage(window, LB_ITEMFROMPOINT, 0, lparam);
      const int hovered = HIWORD(hit) ? -1 : LOWORD(hit);
      if (hovered != self->hovered_row_ || was_keyboard) {
        self->hovered_row_ = hovered;
        InvalidateRect(window, nullptr, FALSE);
      }
    }
    TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0};
    TrackMouseEvent(&track);
  }
  if (message == WM_MOUSELEAVE) {
    self->hovered_row_ = -1;
    self->last_pointer_ = {-1, -1};
    InvalidateRect(window, nullptr, FALSE);
  }
  if (message == WM_SETCURSOR && LOWORD(lparam) == HTCLIENT) { SetCursor(LoadCursor(nullptr, IDC_HAND)); return TRUE; }
  if (message == WM_KEYDOWN) {
    self->keyboard_focus_ = true;
    self->hovered_row_ = -1;
    InvalidateRect(window, nullptr, FALSE);
    if (wparam == VK_TAB) {
      if (IsWindowVisible(self->read_all_)) SetFocus(self->read_all_);
      return 0;
    }
  }
  if (message == WM_LBUTTONUP) {
    const auto result = DefSubclassProc(window, message, wparam, lparam);
    self->OpenSelected();
    return result;
  }
  if (message == WM_KEYDOWN && wparam == VK_RETURN) { self->OpenSelected(); return 0; }
  if (message == WM_KEYDOWN && wparam == VK_ESCAPE) { self->Hide(); return 0; }
  const auto result = DefSubclassProc(window, message, wparam, lparam);
  if (message == WM_MOUSEWHEEL || message == WM_VSCROLL || message == WM_KEYDOWN || message == LB_SETTOPINDEX) {
    InvalidateRect(self->window_, nullptr, FALSE);
  }
  return result;
}

LRESULT CALLBACK TrayInbox::ActionProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam,
                                      UINT_PTR, DWORD_PTR data) {
  auto* self = reinterpret_cast<TrayInbox*>(data);
  if (message == WM_SETFOCUS) self->focused_control_ = window;
  if (message == WM_MOUSEMOVE) {
    const POINT pointer{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    if (pointer.x != self->last_pointer_.x || pointer.y != self->last_pointer_.y) {
      self->last_pointer_ = pointer;
      self->keyboard_focus_ = false;
    }
    self->action_hovered_ = true;
    TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0};
    TrackMouseEvent(&track);
    InvalidateRect(window, nullptr, FALSE);
  }
  if (message == WM_MOUSELEAVE) {
    self->action_hovered_ = false;
    self->last_pointer_ = {-1, -1};
    InvalidateRect(window, nullptr, FALSE);
  }
  if (message == WM_SETFOCUS || message == WM_KILLFOCUS) InvalidateRect(window, nullptr, FALSE);
  if (message == WM_SETCURSOR) { SetCursor(LoadCursor(nullptr, IDC_HAND)); return TRUE; }
  if (message == WM_KEYDOWN) {
    self->keyboard_focus_ = true;
    if (wparam == VK_TAB) { SetFocus(self->list_); return 0; }
    if (wparam == VK_ESCAPE) { self->Hide(); return 0; }
    if (wparam == VK_RETURN) { SendMessage(window, BM_CLICK, 0, 0); return 0; }
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

LRESULT CALLBACK TrayInbox::WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<TrayInbox*>(GetWindowLongPtr(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<TrayInbox*>(reinterpret_cast<CREATESTRUCT*>(lparam)->lpCreateParams);
    self->window_ = window;
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  return self ? self->OnMessage(message, wparam, lparam) : DefWindowProc(window, message, wparam, lparam);
}

void TrayInbox::PaintSurface(HDC dc) {
  RECT bounds{};
  GetClientRect(window_, &bounds);
  Fill(dc, bounds, RGB(255, 255, 255));
  Rounded(dc, bounds, Scale(12), RGB(255, 255, 255), kLine);
  HGDIOBJ previous = SelectObject(dc, title_font_);
  const int pending = PendingRequests(), unread = MessageCount();
  if (pending > 0) {
    Text(dc, unread > 0 ? L"消息与文件" : L"待接收文件",
        {Scale(20), Scale(10), bounds.right - Scale(60), Scale(32)}, kInk);
    SelectObject(dc, font_);
    const auto summary = std::to_wstring(pending) + L" 个文件请求待处理" +
        (unread > 0 ? L" · " + std::to_wstring(unread) + L" 条未读" : L"");
    Text(dc, summary, {Scale(20), Scale(33), bounds.right - Scale(60), Scale(52)}, kMuted);
  } else {
    Text(dc, L"未读消息", {Scale(20), Scale(12), bounds.right - Scale(100), Scale(48)}, kInk);
    SelectObject(dc, font_);
    Text(dc, std::to_wstring(unread), {Scale(94), Scale(12), bounds.right - Scale(60), Scale(48)}, kMuted);
  }
  Fill(dc, {Scale(20), Scale(56), bounds.right - Scale(20), Scale(56) + 1}, kLine);
  PaintScrollBar(dc);
  SelectObject(dc, previous);
}

LRESULT TrayInbox::OnMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(window_, &paint);
      PaintSurface(dc);
      EndPaint(window_, &paint);
      return 0;
    }
    case WM_PRINTCLIENT:
      PaintSurface(reinterpret_cast<HDC>(wparam));
      return 0;
    case WM_DRAWITEM:
      if (wparam == 100) { PaintRow(*reinterpret_cast<DRAWITEMSTRUCT*>(lparam)); return TRUE; }
      if (wparam == 101) { PaintAction(*reinterpret_cast<DRAWITEMSTRUCT*>(lparam)); return TRUE; }
      break;
    case WM_MEASUREITEM:
      reinterpret_cast<MEASUREITEMSTRUCT*>(lparam)->itemHeight = Scale(kRowHeight);
      return TRUE;
    case WM_ERASEBKGND: return 1;
    case WM_MOUSEMOVE: {
      const POINT pointer{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      const auto track = ScrollTrack();
      const bool hovered = PtInRect(&track, pointer) != FALSE;
      if (scroll_hovered_ != hovered) {
        scroll_hovered_ = hovered;
        InvalidateRect(window_, nullptr, FALSE);
      }
      if (scroll_dragging_) {
        const auto thumb = ScrollThumb();
        const int travel = (track.bottom - track.top) - (thumb.bottom - thumb.top);
        const int maximum = static_cast<int>(entries_.size()) - VisibleRows();
        if (travel > 0) ScrollTo(MulDiv(pointer.y - track.top - scroll_drag_offset_, maximum, travel));
      }
      TRACKMOUSEEVENT track_mouse{sizeof(track_mouse), TME_LEAVE, window_, 0};
      TrackMouseEvent(&track_mouse);
      return 0;
    }
    case WM_MOUSELEAVE:
      scroll_hovered_ = false;
      InvalidateRect(window_, nullptr, FALSE);
      return 0;
    case WM_LBUTTONDOWN: {
      const POINT pointer{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      const auto track = ScrollTrack(), thumb = ScrollThumb();
      if (!PtInRect(&track, pointer)) break;
      SetFocus(list_);
      if (PtInRect(&thumb, pointer)) {
        scroll_drag_offset_ = pointer.y - thumb.top;
        scroll_dragging_ = true;
        SetCapture(window_);
        InvalidateRect(window_, nullptr, FALSE);
      } else {
        const int top = static_cast<int>(SendMessage(list_, LB_GETTOPINDEX, 0, 0));
        ScrollTo(top + (pointer.y < thumb.top ? -VisibleRows() : VisibleRows()));
      }
      return 0;
    }
    case WM_LBUTTONUP:
      if (scroll_dragging_) {
        ReleaseCapture();
        return 0;
      }
      break;
    case WM_CAPTURECHANGED:
      scroll_dragging_ = false;
      InvalidateRect(window_, nullptr, FALSE);
      return 0;
    case WM_CANCELMODE:
      if (GetCapture() == window_) ReleaseCapture();
      scroll_dragging_ = false;
      return 0;
    case WM_MOUSEWHEEL:
      SendMessage(list_, message, wparam, lparam);
      return 0;
    case WM_COMMAND:
      if (LOWORD(wparam) == 101 && HIWORD(wparam) == BN_CLICKED && MessageCount() > 0) {
        if (PendingRequests() == 0) Hide();
        read_all_callback_();
        return 0;
      }
      break;
    case WM_ACTIVATE:
      if (LOWORD(wparam) == WA_INACTIVE && !inspectable_) Hide();
      break;
    case WM_SETFOCUS:
      if (list_) SetFocus(focused_control_ ? focused_control_ : list_);
      return 0;
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) { Hide(); return 0; }
      break;
    case WM_TIMER: {
      POINT cursor{};
      RECT bounds{};
      GetCursorPos(&cursor);
      GetWindowRect(window_, &bounds);
      InflateRect(&bounds, Scale(12), Scale(12));
      NOTIFYICONIDENTIFIER identity{};
      identity.cbSize = sizeof(identity); identity.hWnd = owner_; identity.uID = 1;
      RECT tray{};
      Shell_NotifyIconGetRect(&identity, &tray);
      const bool inside = PtInRect(&bounds, cursor) || PtInRect(&tray, cursor);
      if (inside || scroll_dragging_ || GetForegroundWindow() == window_) outside_since_ = 0;
      else if (!outside_since_) outside_since_ = GetTickCount64();
      else if (GetTickCount64() - outside_since_ > 650) Hide();
      return 0;
    }
    case WM_CLOSE: Hide(); return 0;
  }
  return DefWindowProc(window_, message, wparam, lparam);
}
