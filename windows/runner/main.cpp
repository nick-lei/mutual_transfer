#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <functional>
#include <memory>

#include "flutter_window.h"
#include "utils.h"

namespace {
struct WindowSearch {
  const wchar_t* property;
  HWND window = nullptr;
};

BOOL CALLBACK FindInstanceWindow(HWND window, LPARAM parameter) {
  auto* search = reinterpret_cast<WindowSearch*>(parameter);
  if (GetProp(window, search->property)) {
    search->window = window;
    return FALSE;
  }
  return TRUE;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  auto arguments = GetCommandLineArguments();
  std::string data_directory;
  bool autostart = false;
  for (const auto& argument : arguments) {
    if (argument.rfind("--data-dir=", 0) == 0) data_directory = argument.substr(11);
    if (argument == "--autostart") autostart = true;
  }
  const std::wstring instance_name = L"Local\\NearLink." +
      std::to_wstring(std::hash<std::string>{}(data_directory));
  HANDLE instance_lock = CreateMutex(nullptr, FALSE, instance_name.c_str());
  if (instance_lock && GetLastError() == ERROR_ALREADY_EXISTS) {
    if (!autostart) {
      WindowSearch search{instance_name.c_str()};
      for (int attempt = 0; attempt < 100 && !search.window; ++attempt) {
        EnumWindows(FindInstanceWindow, reinterpret_cast<LPARAM>(&search));
        if (!search.window) Sleep(50);
      }
      if (search.window) {
        DWORD process_id = 0;
        GetWindowThreadProcessId(search.window, &process_id);
        AllowSetForegroundWindow(process_id);
        PostMessage(search.window, RegisterWindowMessage(L"NearLink.ShowMainWindow"), 0, 0);
      }
    }
    CloseHandle(instance_lock);
    return EXIT_SUCCESS;
  }
  // Setup and uninstall wait until all NearLink profiles have exited.
  const std::unique_ptr<void, decltype(&::CloseHandle)> installation_guard(
      ::CreateMutex(nullptr, FALSE, L"Local\\NearLink.InstallationGuard"),
      ::CloseHandle);
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1440, 920);
  if (!window.Create(L"NearLink", origin, size)) {
    if (instance_lock) CloseHandle(instance_lock);
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  SetProp(window.GetHandle(), instance_name.c_str(), reinterpret_cast<HANDLE>(1));
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_lock) CloseHandle(instance_lock);
  return EXIT_SUCCESS;
}
