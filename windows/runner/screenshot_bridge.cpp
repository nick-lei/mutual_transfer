#include "screenshot_bridge.h"

#include <dwmapi.h>
#include <imm.h>
#include <objidl.h>
#include <algorithm>
// Older Windows SDK GDI+ headers expect unqualified min/max even with NOMINMAX.
namespace Gdiplus { using std::min; using std::max; }
#pragma warning(push)
#pragma warning(disable : 4458)
#include <gdiplus.h>
#pragma warning(pop)
#include <flutter/standard_method_codec.h>
#include <cstring>
#include <vector>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
// GDI+'s built-in lossless PNG encoder.
const CLSID kPngEncoder = {0x557cf406, 0x1a04, 0x11d3,
                          {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};

int ReadInt(const Map& args, const char* name) {
  auto it = args.find(Value(name));
  return it == args.end() || !std::holds_alternative<int32_t>(it->second)
             ? 0 : std::get<int32_t>(it->second);
}

bool CapturePng(const RECT& desktop, std::vector<uint8_t>* bytes) {
  const int width = desktop.right - desktop.left;
  const int height = desktop.bottom - desktop.top;
  HDC screen = GetDC(nullptr);
  if (!screen) return false;
  HDC memory = CreateCompatibleDC(screen);
  HBITMAP bitmap = CreateCompatibleBitmap(screen, width, height);
  bool success = false;
  if (memory && bitmap) {
    auto previous = SelectObject(memory, bitmap);
    const BOOL copied = BitBlt(memory, 0, 0, width, height, screen,
                               desktop.left, desktop.top, SRCCOPY | CAPTUREBLT);
    SelectObject(memory, previous);
    if (copied) {
      Gdiplus::Bitmap image(bitmap, nullptr);
      IStream* stream = nullptr;
      if (SUCCEEDED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
        if (image.Save(stream, &kPngEncoder, nullptr) == Gdiplus::Ok) {
          STATSTG stat{};
          HGLOBAL handle = nullptr;
          if (SUCCEEDED(stream->Stat(&stat, STATFLAG_NONAME)) &&
              stat.cbSize.QuadPart > 0 && stat.cbSize.QuadPart <= 256 * 1024 * 1024 &&
              SUCCEEDED(GetHGlobalFromStream(stream, &handle))) {
            auto data = static_cast<const uint8_t*>(GlobalLock(handle));
            if (data) {
              bytes->assign(data, data + static_cast<size_t>(stat.cbSize.QuadPart));
              GlobalUnlock(handle);
              success = true;
            }
          }
        }
        stream->Release();
      }
    }
  }
  if (bitmap) DeleteObject(bitmap);
  if (memory) DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  return success;
}

bool CopyPng(HWND owner, const std::vector<uint8_t>& bytes) {
  if (bytes.empty() || bytes.size() > 256 * 1024 * 1024) return false;
  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) return false;
  ULONG written = 0;
  const HRESULT write_result = stream->Write(bytes.data(),
      static_cast<ULONG>(bytes.size()), &written);
  LARGE_INTEGER zero{};
  stream->Seek(zero, STREAM_SEEK_SET, nullptr);
  bool success = false;
  if (SUCCEEDED(write_result) && written == bytes.size()) {
    Gdiplus::Bitmap image(stream);
    const UINT width = image.GetWidth();
    const UINT height = image.GetHeight();
    if (image.GetLastStatus() == Gdiplus::Ok && width && height &&
        static_cast<uint64_t>(width) * height <= 64000000) {
      const SIZE_T stride = static_cast<SIZE_T>(width) * 4;
      HGLOBAL dib = GlobalAlloc(GMEM_MOVEABLE,
          sizeof(BITMAPINFOHEADER) + stride * height);
      auto header = static_cast<BITMAPINFOHEADER*>(GlobalLock(dib));
      if (header) {
        *header = {};
        header->biSize = sizeof(BITMAPINFOHEADER);
        header->biWidth = static_cast<LONG>(width);
        header->biHeight = static_cast<LONG>(height);
        header->biPlanes = 1;
        header->biBitCount = 32;
        header->biCompression = BI_RGB;
        Gdiplus::Rect rect(0, 0, static_cast<INT>(width), static_cast<INT>(height));
        Gdiplus::BitmapData pixels{};
        if (image.LockBits(&rect, Gdiplus::ImageLockModeRead,
                           PixelFormat32bppARGB, &pixels) == Gdiplus::Ok) {
          auto target = reinterpret_cast<uint8_t*>(header + 1);
          for (UINT y = 0; y < height; ++y) {
            auto source = static_cast<uint8_t*>(pixels.Scan0) +
                          static_cast<ptrdiff_t>(y) * pixels.Stride;
            std::memcpy(target + (height - y - 1) * stride, source, stride);
          }
          image.UnlockBits(&pixels);
          GlobalUnlock(dib);
          if (OpenClipboard(owner)) {
            if (EmptyClipboard() && SetClipboardData(CF_DIB, dib)) {
              dib = nullptr;  // Clipboard now owns this allocation.
              success = true;
              const UINT png_format = RegisterClipboardFormat(L"PNG");
              HGLOBAL png = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
              void* png_data = GlobalLock(png);
              if (png_data) {
                std::memcpy(png_data, bytes.data(), bytes.size());
                GlobalUnlock(png);
                if (png_format && SetClipboardData(png_format, png)) png = nullptr;
              }
              if (png) GlobalFree(png);
            }
            CloseClipboard();
          }
        } else {
          GlobalUnlock(dib);
        }
      }
      if (dib) GlobalFree(dib);
    }
  }
  stream->Release();
  return success;
}
}  // namespace

ScreenshotBridge::ScreenshotBridge(HWND window,
    flutter::BinaryMessenger* messenger) : window_(window) {
  Gdiplus::GdiplusStartupInput input;
  Gdiplus::GdiplusStartup(&gdiplus_token_, &input, nullptr);
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "nearlink/screenshot", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleCall(call, std::move(result));
  });
}

ScreenshotBridge::~ScreenshotBridge() {
  SetHotkeyRecording(false);
  if (hotkey_id_) UnregisterHotKey(window_, hotkey_id_);
  channel_->SetMethodCallHandler(nullptr);
  if (gdiplus_token_) Gdiplus::GdiplusShutdown(gdiplus_token_);
}

void ScreenshotBridge::HandleCall(const flutter::MethodCall<Value>& call,
    std::unique_ptr<flutter::MethodResult<Value>> result) {
  const auto& method = call.method_name();
  if (method == "setHotkeyRecording") {
    const auto* recording = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
    if (!recording) { result->Error("arguments", "快捷键录入状态无效"); return; }
    SetHotkeyRecording(*recording);
    result->Success();
  } else if (method == "registerHotkey") {
    const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    if (!args) { result->Error("arguments", "快捷键参数无效"); return; }
    UINT modifiers = static_cast<UINT>(ReadInt(*args, "modifiers"));
    UINT key = static_cast<UINT>(ReadInt(*args, "key"));
    if (key == 0) {
      if (hotkey_id_) UnregisterHotKey(window_, hotkey_id_);
      hotkey_id_ = 0; key_ = 0; modifiers_ = 0;
      result->Success(); return;
    }
    const bool valid_key = (key >= 'A' && key <= 'Z') ||
                          (key >= '0' && key <= '9') || (key >= VK_F1 && key <= VK_F24);
    if (!valid_key || (modifiers & (MOD_CONTROL | MOD_ALT)) == 0 ||
        (modifiers & ~(MOD_CONTROL | MOD_ALT | MOD_SHIFT)) != 0) {
      result->Error("arguments", "请使用 Ctrl 或 Alt 搭配字母、数字或功能键"); return;
    }
    if (hotkey_id_ && key_ == key && modifiers_ == modifiers) {
      result->Success(); return;
    }
    const int next_id = hotkey_id_ == 0x4e01 ? 0x4e02 : 0x4e01;
    if (!RegisterHotKey(window_, next_id, modifiers | MOD_NOREPEAT, key)) {
      result->Error("hotkey_conflict", "快捷键已被其他程序占用，请换一组"); return;
    }
    if (hotkey_id_) UnregisterHotKey(window_, hotkey_id_);
    hotkey_id_ = next_id; key_ = key; modifiers_ = modifiers;
    result->Success();
  } else if (method == "beginCapture") {
    if (capturing_) { result->Error("busy", "截图已在进行中"); return; }
    placement_ = {}; placement_.length = sizeof(placement_);
    if (!GetWindowPlacement(window_, &placement_)) {
      result->Error("window", "无法读取窗口状态"); return;
    }
    style_ = GetWindowLongPtr(window_, GWL_STYLE);
    ex_style_ = GetWindowLongPtr(window_, GWL_EXSTYLE);
    previous_foreground_ = GetForegroundWindow();
    was_visible_ = IsWindowVisible(window_) != FALSE;
    capturing_ = true;
    const auto* hide_window = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
    if (!hide_window || *hide_window) ShowWindow(window_, SW_HIDE);
    DwmFlush();
    result->Success();
  } else if (method == "captureDesktop") {
    if (!capturing_ || overlay_) { result->Error("state", "截图状态无效"); return; }
    desktop_.left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    desktop_.top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    const int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    const int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    desktop_.right = desktop_.left + width;
    desktop_.bottom = desktop_.top + height;
    if (width <= 0 || height <= 0 || width > 16384 || height > 16384 ||
        static_cast<int64_t>(width) * height > 64000000) {
      result->Error("screen_size", "当前桌面尺寸过大，请减少屏幕分辨率后重试"); return;
    }
    std::vector<uint8_t> bytes;
    if (!gdiplus_token_ || !CapturePng(desktop_, &bytes)) {
      result->Error("capture", "无法截取当前桌面，请重试"); return;
    }
    // Freeze the visible app first, then hide it before Flutter paints the editor.
    ShowWindow(window_, SW_HIDE);
    result->Success(Value(std::move(bytes)));
  } else if (method == "showOverlay") {
    if (!capturing_) { result->Error("state", "截图状态无效"); return; }
    overlay_ = true;
    SetWindowLongPtr(window_, GWL_STYLE, WS_POPUP | WS_CLIPCHILDREN);
    SetWindowLongPtr(window_, GWL_EXSTYLE, ex_style_ & ~WS_EX_WINDOWEDGE);
    SetWindowPos(window_, HWND_TOPMOST, desktop_.left, desktop_.top,
        desktop_.right - desktop_.left, desktop_.bottom - desktop_.top,
        SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    SetForegroundWindow(window_);
    result->Success();
  } else if (method == "setOverlayTopmost") {
    const auto* topmost = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
    if (overlay_ && topmost) {
      SetWindowPos(window_, *topmost ? HWND_TOPMOST : HWND_NOTOPMOST,
          0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
    result->Success();
  } else if (method == "restoreWindow") {
    const auto* activate = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
    Restore(activate && *activate);
    result->Success();
  } else if (method == "copyImage") {
    const auto* bytes = call.arguments()
        ? std::get_if<std::vector<uint8_t>>(call.arguments()) : nullptr;
    if (!bytes || !CopyPng(window_, *bytes)) {
      result->Error("clipboard", "剪贴板暂时不可用，请重试或另存为文件"); return;
    }
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void ScreenshotBridge::SetHotkeyRecording(bool recording) {
  if (!recording) {
    if (hotkey_input_window_ && IsWindow(hotkey_input_window_)) {
      ImmAssociateContext(hotkey_input_window_, hotkey_input_context_);
    }
    hotkey_input_window_ = nullptr;
    hotkey_input_context_ = nullptr;
    return;
  }
  if (hotkey_input_window_) return;
  HWND target = GetFocus();
  if (!target || (target != window_ && !IsChild(window_, target))) {
    target = GetWindow(window_, GW_CHILD);
  }
  if (!target) target = window_;
  // A shortcut recorder needs raw letters, not an IME composition session.
  HIMC context = ImmGetContext(target);
  if (context) {
    ImmNotifyIME(context, NI_COMPOSITIONSTR, CPS_CANCEL, 0);
    ImmReleaseContext(target, context);
  }
  hotkey_input_window_ = target;
  hotkey_input_context_ = ImmAssociateContext(target, nullptr);
}

void ScreenshotBridge::Restore(bool activate) {
  if (!capturing_) return;
  ShowWindow(window_, SW_HIDE);
  overlay_ = false;
  capturing_ = false;
  SetWindowLongPtr(window_, GWL_STYLE, style_);
  SetWindowLongPtr(window_, GWL_EXSTYLE, ex_style_);
  SetWindowPos(window_, (ex_style_ & WS_EX_TOPMOST) ? HWND_TOPMOST : HWND_NOTOPMOST,
      0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  SetWindowPlacement(window_, &placement_);
  if (activate) {
    ShowWindow(window_, placement_.showCmd == SW_SHOWMAXIMIZED ? SW_SHOWMAXIMIZED : SW_RESTORE);
    SetForegroundWindow(window_);
  } else {
    if (!was_visible_) ShowWindow(window_, SW_HIDE);
    if (previous_foreground_ && IsWindow(previous_foreground_))
      SetForegroundWindow(previous_foreground_);
  }
}

std::optional<LRESULT> ScreenshotBridge::HandleMessage(UINT message,
    WPARAM wparam, LPARAM lparam) {
  if (message == WM_HOTKEY && static_cast<int>(wparam) == hotkey_id_) {
    if (!capturing_) channel_->InvokeMethod("captureRequested", nullptr);
    return 0;
  }
  if (capturing_ && message == WM_CLOSE) {
    channel_->InvokeMethod("cancelRequested", nullptr);
    return 0;
  }
  if (!overlay_) return std::nullopt;
  if (message == WM_NCCALCSIZE) return 0;
  if (message == WM_NCHITTEST) return HTCLIENT;
  if (message == WM_GETMINMAXINFO) {
    auto info = reinterpret_cast<MINMAXINFO*>(lparam);
    info->ptMinTrackSize = {1, 1};
    info->ptMaxTrackSize = {desktop_.right - desktop_.left,
                            desktop_.bottom - desktop_.top};
    return 0;
  }
  // The virtual desktop rectangle is deliberate; do not apply one monitor's
  // suggested bounds when crossing monitors with different DPI settings.
  if (message == WM_DPICHANGED) return 0;
  return std::nullopt;
}
