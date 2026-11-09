#ifndef RUNNER_SCREENSHOT_BRIDGE_H_
#define RUNNER_SCREENSHOT_BRIDGE_H_

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include <optional>

// Owns the OS hotkey and the temporary desktop-sized capture window state.
class ScreenshotBridge {
 public:
  ScreenshotBridge(HWND window, flutter::BinaryMessenger* messenger);
  ~ScreenshotBridge();
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                     LPARAM lparam);

 private:
  using Value = flutter::EncodableValue;
  void HandleCall(const flutter::MethodCall<Value>& call,
                  std::unique_ptr<flutter::MethodResult<Value>> result);
  void Restore(bool activate);
  void SetHotkeyRecording(bool recording);
  HWND window_;
  HWND hotkey_input_window_ = nullptr;
  HIMC hotkey_input_context_ = nullptr;
  HWND previous_foreground_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
  ULONG_PTR gdiplus_token_ = 0;
  int hotkey_id_ = 0;
  UINT modifiers_ = 0;
  UINT key_ = 0;
  bool capturing_ = false;
  bool overlay_ = false;
  bool was_visible_ = false;
  LONG_PTR style_ = 0;
  LONG_PTR ex_style_ = 0;
  WINDOWPLACEMENT placement_{};
  RECT desktop_{};
};

#endif
