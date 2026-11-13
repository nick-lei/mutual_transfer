#ifndef RUNNER_FILE_CLIPBOARD_H_
#define RUNNER_FILE_CLIPBOARD_H_

#include <windows.h>

#include <string>
#include <vector>

enum class FileClipboardResult {
  success,
  invalid_paths,
  file_unavailable,
  clipboard_busy,
  clipboard_error,
};

FileClipboardResult CopyFilesToClipboard(
    HWND owner, const std::vector<std::wstring>& paths);

#endif  // RUNNER_FILE_CLIPBOARD_H_
