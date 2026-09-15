# Item Scanner — iOS Shell with AR Measure

A thin native app that hosts the deployed web app (so web updates keep flowing
via GitHub Pages with **no app rebuilds**) and adds a native ARKit measure
screen for tape-measure-grade dimensions. Works on **all** modern iPhones —
no LiDAR required (LiDAR phones automatically get better surface detection).

## What you need
- A Mac with **Xcode** (free, from the Mac App Store — it's a big download)
- Your iPhone + its cable
- Your Apple ID (a free account is enough to run on your own phone)

## Setup (about 10 minutes)

1. **Open Xcode → Create New Project…** Choose **iOS → App**, click Next.
2. Fill in:
   - Product Name: `ItemScanner`
   - Team: click "Add Account…" and sign in with your Apple ID, then select
     your Personal Team (or the uShip team if you have one)
   - Organization Identifier: `com.uship.prototype` (anything works)
   - Interface: **SwiftUI** · Language: **Swift**
   - Uncheck "Include Tests"
3. Save it anywhere (e.g. Desktop).
4. In the file list on the left, you'll see `ContentView.swift`. **Delete it**
   (right-click → Delete → Move to Trash).
5. Drag these three files from this folder **into the Xcode file list**
   (drop them next to `ItemScannerApp.swift`; check "Copy items if needed"):
   - `ItemScanner/ContentView.swift`
   - `ItemScanner/WebView.swift`
   - `ItemScanner/ARMeasure.swift`
6. **Camera permission** (required for AR and the in-app camera):
   click the blue `ItemScanner` project icon at the top of the file list →
   select the `ItemScanner` target → **Info** tab → hover over any row, click
   **+**, and add:
   - Key: `Privacy - Camera Usage Description`
   - Value: `Used to scan and measure items for shipping estimates.`
7. **Run it on your phone:**
   - Plug in your iPhone. Unlock it and tap "Trust" if asked.
   - In the toolbar at the top of Xcode, click the device menu (says
     "iPhone 16 Simulator" or similar) and pick **your actual iPhone**.
   - Press the **▶ Run** button.
   - First time only: your phone will block the app. Go to
     **Settings → General → VPN & Device Management**, tap your Apple ID,
     tap **Trust**. Then launch the app from your home screen.

That's it. The app loads the live web app; when you're on a scan result,
you'll see a **"Measure with AR"** button that opens the native measuring
screen (aim the circle, tap **+** at one edge, tap **+** at the other edge,
then tap **W**, **H**, or **D** to save it — even one dimension is enough,
the app rescales the rest proportionally).

## Notes

- **Web updates need no rebuild.** The app shows whatever is live on GitHub
  Pages. Rebuilding is only needed when the Swift files change.
- **Free Apple ID signing expires after 7 days** — just press Run again to
  re-install. For the board of directors, use uShip's Apple Developer
  account and distribute via **TestFlight** (Xcode → Product → Archive →
  Distribute App → TestFlight; board members install via an email link).
- If the GitHub Pages URL ever changes, update `appURL` at the top of
  `ContentView.swift`.
- Roadmap: on LiDAR iPhones (Pro models), Apple's **RoomPlan** can scan a
  whole room and return furniture as measured boxes automatically — it can be
  added to this same app later, feature-gated so non-Pro phones keep the
  tap-to-measure flow. One app for everyone.
