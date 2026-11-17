# Macndroid

A native macOS app (SwiftUI) for moving files between your Mac and Android phones and tablets, over USB or Wi‑Fi.

## Features

- Detects connected Android devices automatically and shows model, Android version, connection type and free storage
- Finder-style file browser with breadcrumb path bar, back/forward/up, sortable columns, filter, and a hidden-files toggle
- **Upload**: drag files or folders from Finder onto the window, or use the Upload button (⌘U)
- **Download** selected files or folders to any Mac folder (⌘D); double-click a file to open it on the Mac
- New folder, rename, and delete on the device
- Transfer queue with live progress, speed, cancel, and Show in Finder
- Install APKs (More › Install APK…)
- Quick links to Download, DCIM, Pictures, Movies, Music, and Documents
- Wi‑Fi: pair or connect via Android 11+ Wireless debugging, or right-click a USB device and choose **Switch to Wi‑Fi**

## Requirements

- macOS 14 or later
- Android Platform Tools (`adb`). The app looks in `~/Library/Android/sdk/platform-tools`, Homebrew (`brew install android-platform-tools`), `$ANDROID_HOME`, and inside the app bundle.
- **USB debugging** turned on for the Android device (Settings › About phone › tap Build number 7 times, then Developer options › USB debugging)

## Build & run

```bash
./scripts/build-app.sh          # creates build/Macndroid.app
open build/Macndroid.app
```

To make an app that works on Macs without the Android SDK, bundle adb into it:

```bash
BUNDLE_ADB=1 ./scripts/build-app.sh
```

For development, `swift run` launches it straight from the source tree. Only the Xcode Command Line Tools are needed. To edit the code in Xcode, open `Package.swift`.

## Project layout

```
Sources/Macndroid/
  ADB/ADBClient.swift        Locates and runs adb (async, cancellable)
  Models/                    Device, RemoteFile, TransferItem
  ViewModels/AppModel.swift  Device polling, Wi‑Fi, transfer queue
  ViewModels/BrowserModel.swift  Folder listing and file operations
  Views/                     SwiftUI UI (sidebar, browser, transfers, panels)
scripts/build-app.sh         Builds and ad-hoc signs the .app bundle
scripts/make-icon.swift      Generates the app icon
```

## Notes

- The app isn't sandboxed because it runs the `adb` binary, so it can't go on the Mac App Store as-is. Distribute it directly; for other Macs, sign it with a Developer ID and notarize it.
- Files whose names already exist at the destination are overwritten.
- MTP mode (works without USB debugging) isn't implemented yet. It would need `libmtp`.
