# StudyFlow Planner

**English** · [ไทย](README.th.md)

Organize classes, assignments, and events by semester. See all seven days at a glance, track upcoming deadlines, and share just the parts of your planner you choose. Start planning right away and use a sync code when you want to access the same planner on another device.

![StudyFlow Planner on macOS](shots/StudyFlow-Timetable.png)

## What's new in 1.1.0

- Choose Soft Honey or White / Lilac in Settings.
- Add subjects, assignments, and events from pop-up forms. Open a class on the timetable to view or edit it.
- The web and Windows apps include Noto Sans Thai for Thai and English text. The web app caches the font for offline use.

## Download and install

Open **Releases** on GitHub and choose the file for your device.

| Platform | Download | How to open |
| --- | --- | --- |
| macOS 14 or later · Apple Silicon and Intel | `StudyFlow-macOS-Universal.zip` | Extract the ZIP and open `StudyFlow Planner.app`. |
| Windows 10 or 11 · x64 | `StudyFlow-Windows-x64.zip` | Extract the entire ZIP and open `StudyFlow Planner.exe`. Requires .NET Framework 4.8 and [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/#download-section). |
| iPhone and iPad | [StudyFlow Web](https://suanaph-studyflow-planner.netlify.app/) | Open in Safari, then choose **Share → Add to Home Screen**. |

The macOS download is an ad hoc-signed SwiftUI app. It has not been notarized, so Gatekeeper may block a browser download. The Windows build is unsigned and has not yet been tested on a Windows device. To build with the native Mac widget, use the **StudyFlow Mac** scheme in Xcode and configure App Groups for your development team.

## Sync and share

- **Use your planner on another device.** On the Mac, turn off demo mode and go to **Settings → Sync with a code** (ซิงก์ด้วยโค้ด) to create or copy your personal sync code. Enter the same code on your other device to view and edit the same planner.
- **Share selected information.** Use the share button on the timetable. Choose whether to include the timetable and subjects, assignments, or events, then send the share code and password to the recipient.
- **Work offline.** The web and Windows apps can save a local planner immediately. After connecting to a synced planner online, they keep an encrypted local copy. Open it with the same code offline, and edits sync when the app reconnects.
- **Apple Watch.** The watch companion receives data from the paired native iPhone app through Watch Connectivity.

## Build from source

- **macOS.** Use Swift 6 and Xcode Command Line Tools. Run `./build-swift.sh` from the repository root, or open `StudyFlow Planner.xcodeproj` in Xcode for the build with widgets.
- **Windows x64.** Use the .NET SDK and run `dotnet build Windows/StudyFlow.Windows.csproj -c Release -p:Platform=x64`. Keep the files and folders beside the EXE in `Windows/bin/x64/Release/net48/`.
- **Cloud sync.** The source ships with empty Supabase settings. Local planning works immediately. To enable cloud sync in the web and Windows builds, set your Project URL and Publishable Key in `Cloud/Web/config.mjs`. [Cloud setup guide](Cloud/SETUP.md)
- **Tests.** Run `swift test` and `node --test Cloud/Tests/*.test.mjs`.

## Publish a release

Use the contents of `Source` as the repository root. Attach both platform ZIPs to the matching GitHub Release. [GitHub release guide](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)

For wider macOS distribution, see [Apple's guide to notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
