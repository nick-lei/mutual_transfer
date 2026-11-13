#include "file_clipboard.h"

#include <shellapi.h>
#include <shlobj.h>
#include <oleidl.h>

#include <algorithm>
#include <filesystem>
#include <memory>

FileClipboardResult CopyFilesToClipboard(
    HWND owner, const std::vector<std::wstring>& paths) {
  if (paths.empty() || paths.size() > 1000) {
    return FileClipboardResult::invalid_paths;
  }
  SIZE_T characters = 1;
  for (const auto& path : paths) {
    if (path.empty() || path.size() > 32767 ||
        path.find(L'\0') != std::wstring::npos ||
        !std::filesystem::path(path).is_absolute()) {
      return FileClipboardResult::invalid_paths;
    }
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY)) {
      return FileClipboardResult::file_unavailable;
    }
    characters += path.size() + 1;
  }

  using Memory = std::unique_ptr<void, decltype(&GlobalFree)>;
  Memory drop(GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT,
                         sizeof(DROPFILES) + characters * sizeof(wchar_t)),
              GlobalFree);
  Memory effect(GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD)), GlobalFree);
  if (!drop || !effect) return FileClipboardResult::clipboard_error;
  auto* header = static_cast<DROPFILES*>(GlobalLock(drop.get()));
  if (!header) return FileClipboardResult::clipboard_error;
  header->pFiles = sizeof(DROPFILES);
  header->fWide = TRUE;
  auto* destination = reinterpret_cast<wchar_t*>(header + 1);
  for (const auto& path : paths) {
    std::copy(path.begin(), path.end(), destination);
    destination += path.size() + 1;
  }
  GlobalUnlock(drop.get());
  auto* preferred = static_cast<DWORD*>(GlobalLock(effect.get()));
  if (!preferred) return FileClipboardResult::clipboard_error;
  *preferred = DROPEFFECT_COPY;
  GlobalUnlock(effect.get());
  const UINT effect_format = RegisterClipboardFormatW(L"Preferred DropEffect");
  if (!effect_format) return FileClipboardResult::clipboard_error;

  // Validate and allocate everything before replacing the user's clipboard.
  if (!OpenClipboard(owner)) return FileClipboardResult::clipboard_busy;
  bool success = false;
  if (EmptyClipboard() && SetClipboardData(CF_HDROP, drop.get())) {
    drop.release();  // Windows now owns the file list.
    if (SetClipboardData(effect_format, effect.get())) {
      effect.release();
      success = true;
    }
  }
  CloseClipboard();
  return success ? FileClipboardResult::success
                 : FileClipboardResult::clipboard_error;
}
