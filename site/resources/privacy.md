---
description: What Cutaway and CutawayServer connect to, what they store, and what they never do.
---

# Privacy and security

Cutaway stays between your Mac and your app. It has no account, no analytics and no crash reports, and it never contacts a server of its own.

## What Cutaway connects to

- **Simulators on this Mac.** Every two seconds, Cutaway tries ports 48160 to 48167 on `127.0.0.1`, where CutawayServer listens in simulators.
- **Devices over USB.** It tries the same ports on each device connected over USB, through the system’s `usbmuxd`. Nothing goes over Wi-Fi or the internet.
- **Only apps that answer.** An app that answers the handshake is listed. Cutaway keeps one connection per app for as long as the app is listed, and leaves an app that already has a client alone.
- **GitHub, when you ask.** **Cutaway › Check for Updates…** asks GitHub for the list of Cutaway’s releases, over HTTPS. It sends nothing about your Mac, and it runs only when you choose it: there is no automatic check.

Cutaway makes no other network connection.

## What Cutaway stores

- **Preferences** are in `UserDefaults`, and recent archives are in the system’s recent-documents list.
- **Project folders** you link (see [Source code](/guide/source)) are remembered by the app’s bundle ID. Cutaway only reads them: the sources, asset catalogs and string catalogs. It never writes into a project folder or sends it anywhere.
- **Archives** are files you save yourself. They hold what you inspected: the tree, screenshots, attributes and constraints. Share them as you would share a screenshot of your app.

## Why Cutaway isn’t sandboxed or notarized

Cutaway is not sandboxed, because the socket it uses to reach devices over USB is outside the sandbox. That is also why it is distributed outside the Mac App Store, on [GitHub Releases](https://github.com/nothingsh/Cutaway/releases).

Its builds are not notarized by Apple, so the first time you open it macOS says it can’t verify the developer. Open **System Settings › Privacy & Security** and choose **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

Cutaway is open source under the GPL-3.0: you can read every line, or build it yourself. Each release lists the SHA-256 checksums of its files.

## CutawayServer in your app

- **Loopback only.** The server listens for TCP on `127.0.0.1` only, never on other network interfaces. On a device, the Mac reaches it through the USB connection.
- **One client at a time.** A second client is turned away while the first is connected.
- **Keepalive.** A peer that doesn’t answer for about 25 seconds is disconnected, and the server can accept the next client right away.
- **Not in Release builds.** By default the server is compiled only into builds that define `DEBUG`. Every other build contains an empty `start()` and no listening code. See [Debug and Release builds](/integrate/builds).
- **Content you choose to hide.** Your app can leave sensitive views, such as a card number, out of every screenshot. See [Customizing what Cutaway shows](/integrate/customizing).
- **Bad input doesn’t crash the app.** Malformed data and extreme requests are answered with errors.

What capturing touches in your app, and how it is restored, is in [Behavior on the device](/integrate/on-device).
