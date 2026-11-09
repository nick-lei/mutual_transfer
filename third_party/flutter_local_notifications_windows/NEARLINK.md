# NearLink Compatibility Notes

Vendored from flutter_local_notifications_windows 4.0.0, published on pub.dev.
Upstream: https://github.com/MaikuB/flutter_local_notifications
License: MIT, preserved in LICENSE.

This copy uses C++17 with /await on MSVC 2019 for the project's Windows 10
19041 SDK. UTF conversion uses C++/WinRT instead of ATL, so the ATL workload
is not required. No changes to the public Dart notification API are needed.
Initialization and display errors are contained at the FFI boundary so a Windows
notification error is reported to Dart instead of terminating the application.

NearLink uses a small runner bridge for notification permission checks and
removal by app identity because upstream cancel(id) does not remove notifications
for unpackaged desktop applications. No MSIX installation is required.
Immediate toasts use the NearLink group, matching the runner's history-removal
call. Notification cleanup failures are logged without blocking app actions.
