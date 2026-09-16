#include "tray_window.h"

#include "resource.h"

TrayWindow::TrayWindow(HWND window) : window_(window) {}

TrayWindow::~TrayWindow() {
  if (icon_added_) {
    Shell_NotifyIconW(NIM_DELETE, &icon_);
  }
}

bool TrayWindow::Initialize() {
  HMENU menu = CreateMenu();
  HMENU actions = CreatePopupMenu();
  if (!menu || !actions) {
    if (menu) DestroyMenu(menu);
    if (actions) DestroyMenu(actions);
    return false;
  }
  if (!AppendMenuW(actions, MF_STRING, kExitCommand, L"&Ukon\u010dit") ||
      !AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(actions),
                   L"&Menu")) {
    DestroyMenu(actions);
    DestroyMenu(menu);
    return false;
  }
  if (!SetMenu(window_, menu)) {
    DestroyMenu(menu);
    return false;
  }
  DrawMenuBar(window_);

  taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");
  icon_.cbSize = sizeof(icon_);
  icon_.hWnd = window_;
  icon_.uID = 1;
  icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  icon_.uCallbackMessage = kCallbackMessage;
  icon_.hIcon = LoadIconW(GetModuleHandleW(nullptr),
                         MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(icon_.szTip, L"zDrive");
  AddIcon();
  return true;
}

bool TrayWindow::AddIcon() {
  icon_added_ = icon_.hIcon && Shell_NotifyIconW(NIM_ADD, &icon_);
  if (icon_added_) {
    icon_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &icon_);
  }
  return icon_added_;
}

void TrayWindow::Restore() {
  ShowWindow(window_, IsIconic(window_) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window_);
}

void TrayWindow::ShowMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING, kOpenCommand, L"&Otev\u0159\u00edt zDrive");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kExitCommand, L"&Ukon\u010dit");
  SetMenuDefaultItem(menu, kOpenCommand, FALSE);
  POINT position{};
  GetCursorPos(&position);
  SetForegroundWindow(window_);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY,
      position.x, position.y, 0, window_, nullptr);
  DestroyMenu(menu);
  PostMessageW(window_, WM_NULL, 0, 0);
  if (command) PostMessageW(window_, WM_COMMAND, command, 0);
}

std::optional<LRESULT> TrayWindow::HandleMessage(UINT message, WPARAM wparam,
                                                LPARAM lparam) {
  if (taskbar_created_ && message == taskbar_created_) {
    icon_added_ = false;
    if (!AddIcon()) Restore();
    return 0;
  }
  switch (message) {
    case WM_CLOSE:
      if (icon_added_ || AddIcon()) {
        ShowWindow(window_, SW_HIDE);
      } else {
        Restore();
      }
      return 0;
    case WM_COMMAND:
      if (HIWORD(wparam) != 0 || lparam != 0) break;
      if (LOWORD(wparam) == kOpenCommand) {
        Restore();
        return 0;
      }
      if (LOWORD(wparam) == kExitCommand) {
        DestroyWindow(window_);
        return 0;
      }
      break;
    case kCallbackMessage:
      switch (LOWORD(lparam)) {
        case NIN_SELECT:
        case NIN_KEYSELECT:
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          Restore();
          break;
        case WM_CONTEXTMENU:
        case WM_RBUTTONUP:
          ShowMenu();
          break;
      }
      return 0;
    case WM_QUERYENDSESSION:
      return TRUE;
    case WM_ENDSESSION:
      if (wparam) DestroyWindow(window_);
      return 0;
  }
  return std::nullopt;
}
