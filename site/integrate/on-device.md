---
description: What CutawayServer listens on, what capturing touches and restores, and what lasts after Cutaway disconnects.
---

# Behavior on the device

Inspecting an app should not change how it behaves. This page says exactly what CutawayServer does inside your app.

## Networking

- It listens for TCP on the loopback address `127.0.0.1` only, never on other network interfaces. Other devices on the network cannot connect.
- In the Simulator, Cutaway reaches it over the Mac’s loopback address. On a device, the Mac reaches it through the USB connection, by way of macOS’s `usbmuxd`; the server itself knows nothing about USB.
- It takes the first free port from 48160 to 48167. If all of them are taken it does not listen, and tries again the next time the app becomes active.
- If listening fails while running (for example after the app resumes from suspension), it listens again after 0.5 seconds while the app is active, preferring the port it had. Further failures double the interval, up to 30 seconds.
- It serves one client at a time. A second one is turned away while the first is connected.
- Connections use TCP keepalive: a peer that does not answer for about 25 seconds is disconnected, and the server can accept the next client right away.

## Threads and memory

- Only the work that must touch UIKit and Core Animation runs on the main thread, one layer at a time, so the app handles events between layers. Compression, encoding and networking run on background queues.
- When Cutaway falls behind, memory stays bounded: once the data not yet sent plus the images waiting to be compressed exceed 32 MiB, the server starts no new image and no next request until Cutaway catches up. With 64 requests waiting, it stops reading.
- Layers and views are held weakly, and everything a connection owns is released when it closes.
- Malformed data and extreme requests are answered with errors; they do not crash the app.

The measured numbers are on the [Performance](/resources/performance) page.

## Capturing

- **The hierarchy.** Member variable names (such as `titleLabel`) are found by comparing addresses in the owner’s memory; no getter is called. [Limitations](/integrate/limitations#member-variable-names) lists the references this cannot find.
- **Images.** Each layer is rendered on its own. While rendering a layer, the server temporarily sets its opacity to 1 and makes it visible, and for the image without sublayers temporarily hides the sublayers. All of this is restored in the same stretch of main-thread code, with no animation and no layout.
- **Attributes.** Reading attributes does not trigger layout. Colors are sent in sRGB, so wide-gamut colors are clipped; dynamic colors are resolved for the view’s current appearance (light or dark), and with CutawayServer 1.2 in both appearances.

## What lasts after Cutaway disconnects

| | After the connection closes |
|---|---|
| **Edits** you made to attributes | Stay. The server neither records nor reverts them; they are changes to the app’s running state, like any other. |
| **Environment overrides** (appearance, text size, layout direction, size classes) | Are removed. The server restores the app’s own values when the connection closes, for any reason. What the app did in response to the changed traits is the app’s, and is not undone. |

## Next

<NextSteps :items="[
  { title: 'Limitations', text: 'What the images and names cannot show.', link: '/integrate/limitations' },
  { title: 'Privacy and security', text: 'What Cutaway and the server send, and to whom.', link: '/resources/privacy' }
]" />
