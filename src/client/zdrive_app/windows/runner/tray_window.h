#ifndef RUNNER_TRAY_WINDOW_H_
#define RUNNER_TRAY_WINDOW_H_

#include <windows.h>
#include <shellapi.h>

#include <optional>

class TrayWindow {
 public:
  static constexpr UINT kCallbackMessage = WM_APP + 1;
  static constexpr UINT kOpenCommand = 0xA001;
  static constexpr UINT kExitCommand = 0xA002;

  explicit TrayWindow(HWND window);
  ~TrayWindow();
  TrayWindow(const TrayWindow&) = delete;
  TrayWindow& operator=(const TrayWindow&) = delete;

  bool Initialize();
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

 private:
  bool AddIcon();
  void Restore();
  void ShowMenu();

  HWND window_;
  NOTIFYICONDATAW icon_{};
  UINT taskbar_created_ = 0;
  bool icon_added_ = false;
};

#endif  // RUNNER_TRAY_WINDOW_H_
