#include "flutter_window.h"

#include <optional>
#include <exception>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.UI.Notifications.h>
#include <mmsystem.h>

#include "flutter/generated_plugin_registrant.h"
#include "file_clipboard.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  lifecycle_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "nearlink/lifecycle",
      &flutter::StandardMethodCodec::GetInstance());
  tray_inbox_ = std::make_unique<TrayInbox>(GetHandle(), [this](const std::string& id, bool file) {
    lifecycle_channel_->InvokeMethod(file ? "openIncomingOffer" : "openConversation",
        std::make_unique<flutter::EncodableValue>(id));
  }, [this]() { lifecycle_channel_->InvokeMethod("markMessagesRead", nullptr); });
  lifecycle_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "copyFilesToClipboard") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      const auto paths = args ? args->find(flutter::EncodableValue("paths"))
                              : flutter::EncodableMap::const_iterator{};
      if (!args || paths == args->end() ||
          !std::holds_alternative<flutter::EncodableList>(paths->second)) {
        result->Error("invalid_paths", "File paths are required");
        return;
      }
      std::vector<std::wstring> files;
      try {
        for (const auto& value : std::get<flutter::EncodableList>(paths->second)) {
          const auto* path = std::get_if<std::string>(&value);
          if (!path || path->find('\0') != std::string::npos) {
            result->Error("invalid_paths", "File paths must be valid strings");
            return;
          }
          files.emplace_back(winrt::to_hstring(*path).c_str());
        }
        switch (CopyFilesToClipboard(GetHandle(), files)) {
          case FileClipboardResult::success:
            result->Success();
            break;
          case FileClipboardResult::invalid_paths:
            result->Error("invalid_paths", "File paths are invalid");
            break;
          case FileClipboardResult::file_unavailable:
            result->Error("file_unavailable", "The file is unavailable");
            break;
          case FileClipboardResult::clipboard_busy:
            result->Error("clipboard_busy", "The clipboard is busy");
            break;
          default:
            result->Error("clipboard_error", "Could not copy files");
        }
      } catch (const std::exception&) {
        result->Error("invalid_paths", "File paths are invalid");
      } catch (const winrt::hresult_error&) {
        result->Error("invalid_paths", "File paths are invalid");
      }
      return;
    }
    if (call.method_name() == "playMessageSound") {
      if (!PlaySoundW(L"SystemNotification", nullptr, SND_ALIAS | SND_ASYNC | SND_NODEFAULT)) {
        result->Error("sound_unavailable", "Windows notification sound is unavailable");
      } else {
        result->Success();
      }
      return;
    }
    if (call.method_name() == "showTrayInbox") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      bool inspectable = false;
      if (args) {
        const auto flag = args->find(flutter::EncodableValue("inspectable"));
        inspectable = flag != args->end() && std::holds_alternative<bool>(flag->second) && std::get<bool>(flag->second);
      }
      result->Success(flutter::EncodableValue(tray_inbox_->Show(true, inspectable)));
      return;
    }
    if (call.method_name() == "updateTrayInbox") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args) {
        const auto entries = args->find(flutter::EncodableValue("entries"));
        if (entries != args->end() && std::holds_alternative<flutter::EncodableList>(entries->second)) {
          result->Success(flutter::EncodableValue(tray_inbox_->Update(std::get<flutter::EncodableList>(entries->second))));
          return;
        }
      }
      result->Error("invalid_arguments", "Unread conversation list is required");
      return;
    }
    if (call.method_name() != "notificationsAllowed" &&
        call.method_name() != "clearNotification") {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!args) {
      result->Error("invalid_arguments", "Notification identity is required");
      return;
    }
    const auto identity = args->find(flutter::EncodableValue("appId"));
    if (identity == args->end() || !std::holds_alternative<std::string>(identity->second)) {
      result->Error("invalid_arguments", "Notification identity is required");
      return;
    }
    try {
      using winrt::Windows::UI::Notifications::ToastNotificationManager;
      using winrt::Windows::UI::Notifications::NotificationSetting;
      const auto app_id = winrt::to_hstring(std::get<std::string>(identity->second));
      if (call.method_name() == "notificationsAllowed") {
        const auto setting = ToastNotificationManager::CreateToastNotifier(app_id).Setting();
        result->Success(flutter::EncodableValue(setting == NotificationSetting::Enabled));
      } else {
        const auto tag = args->find(flutter::EncodableValue("tag"));
        if (tag != args->end() && std::holds_alternative<std::string>(tag->second)) {
          ToastNotificationManager::History().Remove(
              winrt::to_hstring(std::get<std::string>(tag->second)), L"NearLink", app_id);
        } else {
          ToastNotificationManager::History().Clear(app_id);
        }
        result->Success();
      }
    } catch (const winrt::hresult_error& error) {
      if (call.method_name() == "notificationsAllowed" &&
          error.code() == HRESULT_FROM_WIN32(ERROR_NOT_FOUND)) {
        // Windows may not create an app's notification setting until its first toast.
        result->Success(flutter::EncodableValue(true));
        return;
      }
      result->Error("windows_notification_error", winrt::to_string(error.message()));
    }
  });
  screenshot_bridge_ = std::make_unique<ScreenshotBridge>(
      GetHandle(), flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Dart controls visibility so a login launch can remain in the system tray.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  tray_inbox_ = nullptr;
  lifecycle_channel_ = nullptr;
  screenshot_bridge_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  static const UINT show_message = RegisterWindowMessage(L"NearLink.ShowMainWindow");
  static const UINT exit_message = RegisterWindowMessage(L"NearLink.ExitForUpdate");
  if (message == exit_message) {
    if (lifecycle_channel_) lifecycle_channel_->InvokeMethod("exitForUpdate", nullptr);
    return 0;
  }
  if (message == show_message) {
    ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
    SetForegroundWindow(hwnd);
    return 0;
  }
  if (screenshot_bridge_) {
    auto result = screenshot_bridge_->HandleMessage(message, wparam, lparam);
    if (result) return *result;
  }
  if (tray_inbox_) {
    auto result = tray_inbox_->HandleMessage(message, wparam, lparam);
    if (result) return *result;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
