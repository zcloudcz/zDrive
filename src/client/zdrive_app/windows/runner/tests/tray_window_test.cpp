#include "tray_window.h"
#include "resource.h"

#include <iostream>
#include <stdexcept>

namespace {
TrayWindow* active_tray = nullptr;

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  if (active_tray) {
    const auto result = active_tray->HandleMessage(message, wparam, lparam);
    if (result) return *result;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

HWND CreateTestWindow() {
  HWND window = CreateWindowExW(
      WS_EX_TOOLWINDOW, L"zDriveTrayTest", L"zDrive tray behavior test",
      WS_OVERLAPPEDWINDOW, -30000, -30000, 200, 100, nullptr, nullptr,
      GetModuleHandleW(nullptr), nullptr);
  Check(window != nullptr, "create isolated test window");
  return window;
}

void TestCloseRestoreAndExit() {
  HWND window = CreateTestWindow();
  TrayWindow tray(window);
  active_tray = &tray;
  Check(tray.Initialize(), "initialize tray");
  Check(GetMenu(window) == nullptr, "native menu bar is replaced by Flutter settings");

  ShowWindow(window, SW_SHOWNOACTIVATE);
  SendMessageW(window, WM_CLOSE, 0, 0);
  Check(IsWindow(window), "close must keep window and engine alive");
  Check(!IsWindowVisible(window), "close must hide window in tray");

  SendMessageW(window, TrayWindow::kCallbackMessage, 0,
               MAKELPARAM(NIN_SELECT, 1));
  Check(IsWindowVisible(window), "tray click restores window");
  SendMessageW(window, WM_CLOSE, 0, 0);
  SendMessageW(window, TrayWindow::kCallbackMessage, 0,
               MAKELPARAM(NIN_KEYSELECT, 1));
  Check(IsWindowVisible(window), "keyboard tray activation restores window");

  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = window;
  icon.uID = 1;
  Check(Shell_NotifyIconW(NIM_DELETE, &icon) != FALSE, "remove test tray icon");
  SendMessageW(window, RegisterWindowMessageW(L"TaskbarCreated"), 0, 0);
  Check(Shell_NotifyIconW(NIM_MODIFY, &icon) != FALSE,
        "Explorer restart restores tray icon");

  SendMessageW(window, WM_COMMAND, TrayWindow::kExitCommand, 0);
  Check(!IsWindow(window), "explicit Exit destroys window");
  active_tray = nullptr;
}

void TestSessionEnd() {
  HWND window = CreateTestWindow();
  TrayWindow tray(window);
  active_tray = &tray;
  Check(tray.Initialize(), "initialize shutdown test");
  Check(SendMessageW(window, WM_QUERYENDSESSION, 0, ENDSESSION_LOGOFF) == TRUE,
        "allow Windows session shutdown");
  SendMessageW(window, WM_ENDSESSION, FALSE, ENDSESSION_LOGOFF);
  Check(IsWindow(window), "cancelled shutdown keeps app running");
  SendMessageW(window, WM_ENDSESSION, TRUE, ENDSESSION_LOGOFF);
  Check(!IsWindow(window), "confirmed shutdown exits instead of hiding");
  active_tray = nullptr;
}

void TestIconCleanup() {
  HWND window = CreateTestWindow();
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = window;
  icon.uID = 1;
  {
    TrayWindow tray(window);
    Check(tray.Initialize(), "initialize cleanup test");
    Check(Shell_NotifyIconW(NIM_MODIFY, &icon) != FALSE, "test icon exists");
  }
  Check(Shell_NotifyIconW(NIM_MODIFY, &icon) == FALSE,
        "tray destructor removes icon");
  DestroyWindow(window);
}

void TestMissingIcon() {
  HWND window = CreateTestWindow();
  TrayWindow tray(window);
  active_tray = &tray;
  Check(tray.Initialize(), "initialization succeeds even without tray icon");
  SendMessageW(window, WM_CLOSE, 0, 0);
  Check(IsWindow(window) && IsWindowVisible(window),
        "failed tray creation keeps window accessible");
  ShowWindow(window, SW_HIDE);
  SendMessageW(window, RegisterWindowMessageW(L"TaskbarCreated"), 0, 0);
  Check(IsWindowVisible(window), "failed tray recovery restores hidden window");
  SendMessageW(window, WM_COMMAND, TrayWindow::kExitCommand, 0);
  Check(!IsWindow(window), "Exit remains available without tray icon");
  active_tray = nullptr;
}
}  // namespace

int main() {
  WNDCLASSW type{};
  type.lpfnWndProc = WindowProc;
  type.hInstance = GetModuleHandleW(nullptr);
  type.lpszClassName = L"zDriveTrayTest";
  if (!RegisterClassW(&type)) return 1;
  try {
    if (LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON))) {
      TestCloseRestoreAndExit();
      TestSessionEnd();
      TestIconCleanup();
    } else {
      TestMissingIcon();
    }
    std::cout << "Tray lifecycle tests passed.\n";
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
  return 0;
}
