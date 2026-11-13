#include "file_clipboard.h"

#include <shellapi.h>
#include <shlobj.h>
#include <oleidl.h>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <thread>

namespace {
void Require(bool value, const char* message) {
  if (!value) {
    std::cerr << message << " (Windows error " << GetLastError() << ")\n";
    std::exit(1);
  }
}

std::string ReadFile(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}
}  // namespace

int main() {
  // A private window station gives this process its own clipboard.
  const HWINSTA original_station = GetProcessWindowStation();
  const HDESK original_desktop = GetThreadDesktop(GetCurrentThreadId());
  const HWINSTA station = CreateWindowStationW(nullptr, 0, WINSTA_ALL_ACCESS, nullptr);
  Require(station != nullptr && SetProcessWindowStation(station), "Could not isolate the clipboard");
  const HDESK desktop = CreateDesktopW(L"NearLinkClipboardTest", nullptr, nullptr, 0,
                                      GENERIC_ALL, nullptr);
  Require(desktop != nullptr && SetThreadDesktop(desktop), "Could not create a test desktop");
  const HWND owner = CreateWindowExW(0, L"STATIC", L"NearLink Clipboard Test", WS_POPUP,
                                    0, 0, 0, 0, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  Require(owner != nullptr, "Could not create the clipboard owner");

  const auto directory = std::filesystem::temp_directory_path() /
      (L"nearlink-file-clipboard-" + std::to_wstring(GetCurrentProcessId()));
  Require(std::filesystem::create_directory(directory), "Could not create test files");
  const auto first = directory / L"\u9879\u76ee \u6587\u4ef6.txt";
  const auto second = directory / L"image \U0001F4C4.bin";
  const std::string first_content("first\0file", 10);
  const std::string second_content("second\0file", 11);
  std::ofstream(first, std::ios::binary).write(first_content.data(), first_content.size());
  std::ofstream(second, std::ios::binary).write(second_content.data(), second_content.size());
  const std::vector<std::wstring> paths{first.wstring(), second.wstring()};
  Require(CopyFilesToClipboard(owner, paths) == FileClipboardResult::success,
          "Copying files failed");
  Require(OpenClipboard(owner) != FALSE, "Could not inspect file clipboard");
  const auto drop = static_cast<HDROP>(GetClipboardData(CF_HDROP));
  Require(drop != nullptr && DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0) == 2,
          "The clipboard did not contain two file objects");
  const auto header = static_cast<const DROPFILES*>(GlobalLock(drop));
  Require(header != nullptr && header->fWide, "File list is not Unicode");
  const auto data = reinterpret_cast<const wchar_t*>(
      reinterpret_cast<const BYTE*>(header) + header->pFiles);
  SIZE_T characters = 1;
  for (const auto& path : paths) characters += path.size() + 1;
  Require(data[characters - 1] == L'\0' && data[characters - 2] == L'\0',
          "File list lacks its double terminator");
  GlobalUnlock(drop);
  const auto preferred = GetClipboardData(RegisterClipboardFormatW(L"Preferred DropEffect"));
  const auto effect = static_cast<const DWORD*>(GlobalLock(preferred));
  Require(effect != nullptr && *effect == DROPEFFECT_COPY, "Clipboard effect was not copy");
  GlobalUnlock(preferred);
  Require(!IsClipboardFormatAvailable(CF_UNICODETEXT), "Files were encoded as text");
  std::vector<std::wstring> decoded;
  for (UINT index = 0; index < 2; ++index) {
    const UINT size = DragQueryFileW(drop, index, nullptr, 0);
    std::wstring path(size + 1, L'\0');
    Require(DragQueryFileW(drop, index, path.data(), size + 1) == size, "Could not read file path");
    path.resize(size);
    Require(path == paths[index], "Clipboard file path was changed");
    decoded.push_back(path);
  }
  CloseClipboard();

  const auto destination = directory / L"pasted";
  std::filesystem::create_directory(destination);
  for (const auto& path : decoded) {
    const std::filesystem::path source(path);
    Require(std::filesystem::copy_file(source, destination / source.filename()), "Paste copy failed");
  }
  Require(ReadFile(destination / first.filename()) == first_content &&
          ReadFile(destination / second.filename()) == second_content,
          "Pasted content differs from the source files");
  Require(std::filesystem::exists(first) && std::filesystem::exists(second), "Copy moved the original files");

  const DWORD sequence = GetClipboardSequenceNumber();
  Require(CopyFilesToClipboard(owner, {}) == FileClipboardResult::invalid_paths, "Empty paths were accepted");
  Require(CopyFilesToClipboard(owner, {L"relative.txt"}) == FileClipboardResult::invalid_paths,
          "Relative paths were accepted");
  Require(CopyFilesToClipboard(owner, {directory.wstring()}) == FileClipboardResult::file_unavailable,
          "A directory was accepted");
  Require(CopyFilesToClipboard(owner, {(directory / L"missing.txt").wstring()}) == FileClipboardResult::file_unavailable,
          "A missing file was accepted");
  std::wstring malformed = first.wstring();
  malformed.push_back(L'\0');
  malformed.append(L"extra");
  Require(CopyFilesToClipboard(owner, {malformed}) == FileClipboardResult::invalid_paths,
          "Embedded null was accepted");
  Require(GetClipboardSequenceNumber() == sequence, "Invalid input replaced the clipboard");
  Require(OpenClipboard(owner) != FALSE, "Could not hold the clipboard open");
  FileClipboardResult busy = FileClipboardResult::success;
  std::thread contender([&]() {
    Require(SetThreadDesktop(desktop) != FALSE, "Could not bind the competing thread");
    const HWND other_owner = CreateWindowExW(0, L"STATIC", L"Clipboard Contender", WS_POPUP,
        0, 0, 0, 0, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
    Require(other_owner != nullptr, "Could not create the competing clipboard owner");
    busy = CopyFilesToClipboard(other_owner, paths);
    DestroyWindow(other_owner);
  });
  contender.join();
  CloseClipboard();
  Require(busy == FileClipboardResult::clipboard_busy, "Clipboard contention was not reported");
  Require(GetClipboardSequenceNumber() == sequence, "Clipboard contention replaced its contents");

  OpenClipboard(owner);
  EmptyClipboard();
  CloseClipboard();
  std::filesystem::remove_all(directory);
  DestroyWindow(owner);
  Require(SetThreadDesktop(original_desktop) != FALSE, "Could not restore the desktop");
  CloseDesktop(desktop);
  Require(SetProcessWindowStation(original_station) != FALSE, "Could not restore the window station");
  CloseWindowStation(station);
  std::cout << "Native file clipboard verified in a private window station: Unicode file objects, copy effect, content integrity, invalid inputs and clipboard contention.\n";
  return 0;
}
