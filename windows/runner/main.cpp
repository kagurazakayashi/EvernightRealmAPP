#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// 品牌顯示名依系統 UI 語言選擇（四語言對照見規格 §1.1；無匹配時回退英文）。
// 字形一律以通用字元名稱寫死，原始檔編碼與 /utf-8 與否都不影響結果。
// 已知限制：只跟系統 UI 語言，不跟應用內的手工語言切換（STEP-049）。
const wchar_t* BrandWindowTitle() {
  switch (::GetUserDefaultUILanguage()) {
    case 0x0804:  // zh-CN：长夜幻境
    case 0x1004:  // zh-SG（同用简体字形）
      return L"\u957F\u591C\u5E7B\u5883";
    case 0x0404:  // zh-TW：長夜幻境
    case 0x0C04:  // zh-HK
    case 0x1404:  // zh-MO
    case 0x0411:  // ja-JP：長夜幻境
      return L"\u9577\u591C\u5E7B\u5883";
    default:  // en-US 及其他語言
      return L"EvernightRealm";
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(BrandWindowTitle(), origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
