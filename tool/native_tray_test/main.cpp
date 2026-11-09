#include "tray_inbox.h"
#include "resource.h"
#include <commctrl.h>
#include <shellapi.h>
#include <windowsx.h>
#include <algorithm>
namespace Gdiplus { using std::min; using std::max; }
#pragma warning(push)
#pragma warning(disable : 4458)
#include <gdiplus.h>
#pragma warning(pop)
#include <filesystem>
#include <iostream>
#include <stdexcept>

namespace {
void Check(bool condition, const char* description) {
  if (!condition) throw std::runtime_error(description);
  std::cout << "PASS " << description << std::endl;
}

CLSID PngEncoder() {
  UINT count = 0, size = 0;
  Gdiplus::GetImageEncodersSize(&count, &size);
  std::vector<BYTE> bytes(size);
  auto* encoders = reinterpret_cast<Gdiplus::ImageCodecInfo*>(bytes.data());
  Gdiplus::GetImageEncoders(count, size, encoders);
  for (UINT index = 0; index < count; ++index) {
    if (wcscmp(encoders[index].MimeType, L"image/png") == 0) return encoders[index].Clsid;
  }
  throw std::runtime_error("PNG encoder missing");
}

std::vector<DWORD> IconPixels(HICON icon) {
  ICONINFO info{};
  Check(GetIconInfo(icon, &info) != FALSE, "attention icon can be decoded");
  std::vector<DWORD> pixels(32 * 32);
  BITMAPINFO bitmap{};
  bitmap.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap.bmiHeader.biWidth = 32;
  bitmap.bmiHeader.biHeight = -32;
  bitmap.bmiHeader.biPlanes = 1;
  bitmap.bmiHeader.biBitCount = 32;
  HDC dc = CreateCompatibleDC(nullptr);
  Check(GetDIBits(dc, info.hbmColor, 0, 32, pixels.data(), &bitmap, DIB_RGB_COLORS) == 32, "icon pixel data is complete");
  DeleteDC(dc);
  DeleteObject(info.hbmColor);
  DeleteObject(info.hbmMask);
  return pixels;
}
}

struct TrayInboxTest {
  static void Capture(TrayInbox& inbox, const std::filesystem::path& path) {
    RECT bounds{};
    GetClientRect(inbox.window_, &bounds);
    Gdiplus::Bitmap bitmap(bounds.right, bounds.bottom, PixelFormat32bppARGB);
    Gdiplus::Graphics graphics(&bitmap);
    graphics.Clear(Gdiplus::Color(255, 255, 255, 255));
    const auto dc = graphics.GetHDC();
    SendMessage(inbox.window_, WM_PRINT, reinterpret_cast<WPARAM>(dc), PRF_CLIENT | PRF_CHILDREN | PRF_ERASEBKGND);
    graphics.ReleaseHDC(dc);
    const auto encoder = PngEncoder();
    Check(bitmap.Save(path.c_str(), &encoder) == Gdiplus::Ok, "native panel render saved");
  }

  static void Run(HWND owner, const std::filesystem::path& output) {
    TrayInbox inbox(owner, [](const std::string&, bool) {}, [] {});
    flutter::EncodableList entries;
    for (int index = 0; index < 8; ++index) {
      entries.emplace_back(flutter::EncodableMap{
        {flutter::EncodableValue("type"), flutter::EncodableValue("message")},
        {flutter::EncodableValue("peerId"), flutter::EncodableValue(std::to_string(index))},
        {flutter::EncodableValue("name"), flutter::EncodableValue(index == 0 ? "设计工作站 · 产品与研发协作设备" : "协作设备 " + std::to_string(index + 1))},
        {flutter::EncodableValue("count"), flutter::EncodableValue(index == 0 ? 105 : 3)},
        {flutter::EncodableValue("preview"), flutter::EncodableValue("这是一段较长的消息预览，用于检查未读数字和文字间距。")},
      });
    }
    inbox.Update(entries);
    Check(inbox.tray_icon_applied_ && inbox.tray_blinking_, "unread attention starts before any hover");
    Check((GetWindowLongPtr(inbox.list_, GWL_STYLE) & WS_VSCROLL) == 0, "wide native scrollbar is removed");
    Check(inbox.Show(false, true), "native inbox opens for rendering");
    Check(inbox.VisibleRows() == 6, "overflow viewport holds six stable rows");
    auto bright = IconPixels(inbox.unread_icon_), dimmed = IconPixels(inbox.dimmed_icon_);
    Check(bright[8 * 32 + 24] == 0xFFB83D4E && dimmed[8 * 32 + 24] == 0xFFB83D4E, "red dot remains opaque in both blink frames");
    Check(bright != dimmed, "attention logo has distinct bright and dim frames");
    const auto encoder = PngEncoder();
    Gdiplus::Bitmap bright_bitmap(32, 32, 32 * 4, PixelFormat32bppPARGB, reinterpret_cast<BYTE*>(bright.data()));
    Gdiplus::Bitmap dimmed_bitmap(32, 32, 32 * 4, PixelFormat32bppPARGB, reinterpret_cast<BYTE*>(dimmed.data()));
    bright_bitmap.Save((output / "tray-icon-bright.png").c_str(), &encoder);
    dimmed_bitmap.Save((output / "tray-icon-dimmed.png").c_str(), &encoder);
    Capture(inbox, output / "tray-slim-native-top.png");
    SendMessage(inbox.list_, WM_MOUSEWHEEL, MAKEWPARAM(0, -WHEEL_DELTA), 0);
    Check(SendMessage(inbox.list_, LB_GETTOPINDEX, 0, 0) > 0, "mouse wheel scrolls without a native scrollbar");
    inbox.ScrollTo(0);
    SendMessage(inbox.list_, WM_MOUSEWHEEL, static_cast<WPARAM>(0xFFC4u) << 16, 0);
    Check(SendMessage(inbox.list_, LB_GETTOPINDEX, 0, 0) == 0, "partial wheel delta is retained");
    SendMessage(inbox.list_, WM_MOUSEWHEEL, static_cast<WPARAM>(0xFFC4u) << 16, 0);
    Check(SendMessage(inbox.list_, LB_GETTOPINDEX, 0, 0) > 0, "high resolution wheel deltas accumulate");
    inbox.ScrollTo(0);
    const auto thumb = inbox.ScrollThumb(), track = inbox.ScrollTrack();
    const int x = (thumb.left + thumb.right) / 2, y = thumb.top + 8;
    inbox.OnMessage(WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(x, y));
    inbox.OnMessage(WM_MOUSEMOVE, MK_LBUTTON, MAKELPARAM(x, track.bottom));
    inbox.OnMessage(WM_LBUTTONUP, 0, MAKELPARAM(x, track.bottom));
    Check(!inbox.scroll_dragging_ && SendMessage(inbox.list_, LB_GETTOPINDEX, 0, 0) == 2, "thumb drag reaches final rows and releases capture");
    Capture(inbox, output / "tray-slim-native-bottom.png");
    const auto bottom_thumb = inbox.ScrollThumb();
    inbox.OnMessage(WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(x, bottom_thumb.top + 8));
    inbox.OnMessage(WM_CANCELMODE, 0, 0);
    Check(!inbox.scroll_dragging_, "cancelled thumb drag releases its interaction state");
    SendMessage(inbox.list_, WM_KEYDOWN, VK_HOME, 0);
    SendMessage(inbox.list_, WM_KEYDOWN, VK_END, 0);
    Check(SendMessage(inbox.list_, LB_GETCURSEL, 0, 0) == 7, "keyboard End selects final conversation");
    Capture(inbox, output / "tray-slim-native-keyboard.png");
    inbox.HandleMessage(WM_TIMER, 0x4E4C, 0);
    Check(inbox.blink_dimmed_ && inbox.tray_icon_applied_, "timer applies a dimmed attention frame without hovering");
    inbox.Update(entries);
    Check(inbox.blink_dimmed_ && inbox.tray_blinking_, "new inbox snapshots preserve the blink phase");
    inbox.Update({});
    Check(!inbox.tray_blinking_ && inbox.tray_icon_applied_, "clearing attention restores the normal tray icon");
    entries.resize(2);
    inbox.Update(entries);
    inbox.Show(false, true);
    const auto no_scroll = inbox.ScrollTrack();
    Check(IsRectEmpty(&no_scroll) != FALSE, "short inbox has no scrollbar or track");
    Capture(inbox, output / "tray-slim-native-short.png");
  }
};

int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 64;
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_STANDARD_CLASSES};
  InitCommonControlsEx(&controls);
  const HWND owner = CreateWindowW(L"STATIC", L"NearLink native tray test", WS_OVERLAPPEDWINDOW, 0, 0, 360, 528, nullptr, nullptr, GetModuleHandle(nullptr), nullptr);
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = owner;
  icon.uID = 1;
  icon.uFlags = NIF_ICON;
  icon.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  Shell_NotifyIconW(NIM_ADD, &icon);
  int result = 0;
  try {
    std::filesystem::create_directories(argv[1]);
    TrayInboxTest::Run(owner, argv[1]);
  } catch (const std::exception& error) {
    std::cerr << "FAIL " << error.what() << std::endl;
    result = 1;
  }
  Shell_NotifyIconW(NIM_DELETE, &icon);
  DestroyWindow(owner);
  CoUninitialize();
  return result;
}
