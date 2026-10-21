---
description: The limits the test suites hold Cutaway and CutawayServer to, and how both stay fast with large interfaces.
---

# Performance

A large interface should still feel immediate, and inspecting an app shouldn’t change how it behaves. Both sides are designed around that, and their test suites hold them to the numbers on this page on every run.

## Cutaway, on the Mac

The limits are measured against a generated, app-shaped tree of 10,000 layers (windows, containers, a navigation bar and a long list of cells, each with an icon, labels and a separator), in a Debug build:

| Operation | Limit |
|---|---|
| The tree arrives → the list is on screen | 2 s |
| Laying out the scene | 1 s |
| A new frame after the camera moves | 16 ms |
| Drawing one frame | 16 ms |
| Selecting a row → the preview and the inspector follow | 100 ms |
| Searching the list | 200 ms |
| Expand all / collapse all | 1 s |
| Opening an archive of the tree → the list is on screen | 2 s |

Two more limits cover layers with many attributes:

| Operation | Limit |
|---|---|
| Selecting a layer with 1,000 attributes → the inspector shows them | 0.5 s |
| Filtering those attributes by one more character | 0.1 s |

### How it gets there

- **Screenshots stay compressed.** The model keeps only the compressed bytes it received. They are decompressed off the main thread, uploaded to the GPU, and the pixels are let go.
- **Screenshots arrive in batches.** Cutaway asks for screenshots 32 layers at a time, with two batches in flight, so the work after each batch is paid once per batch rather than once per layer.
- **Long attribute lists are built as you scroll.** Rows are made as they come into view, so a layer with a thousand attributes shows at once.
- **The preview draws only on change.** No frame is submitted while nothing moves.
- **Reading keeps pace with drawing.** When screenshots arrive faster than they are used, Cutaway stops reading from the connection, and TCP tells the app to wait. Nothing piles up in memory.
- **Nothing accumulates.** The suite repeats every operation ten times over 5,000 layers and checks that no screenshot, texture, request or window is left behind. A longer soak run prints the memory curve over a hundred rounds.
- **Bad data doesn’t crash it.** Every frame is validated before it is decoded, and the parsers are fuzzed with mutated, truncated and spliced frames on every run.

## CutawayServer, in your app

The measured values are from the iOS Simulator, in a Debug build:

| Scenario | Limit | Measured |
|---|---|---|
| A 10,000-layer tree: hierarchy, then images, attributes and constraints of every layer — longest single main-thread block¹ | 150 ms | 65–76 ms |
| The same, from the request to the last layer’s details | 30 s | about 8.5 s |
| A client that never reads — app memory growth, relative to the 32 MiB budget | 1.5 × | 1.07 × |
| 200 rounds of hierarchy, details, edits and refreshes while the UI changes — memory growth after round 10 | 4 MiB | ≤ 0.06 MiB |
| 1,000 requests sent at once | answered in order; memory doesn’t grow linearly with the count | passes |
| Over 100,000 mutated, truncated and spliced frames | no crash | passes |

¹ Not counting the rendering of a single layer itself.

### How it gets there

- **The main thread stays responsive.** Only the work that must touch UIKit and Core Animation runs on the main thread, one layer at a time, so the app handles events between layers. Compression, encoding and networking run on background queues.
- **Memory stays bounded when Cutaway falls behind.** Once the data not yet sent plus the images waiting to be compressed exceed 32 MiB, the server starts no new image and no next request until the client catches up. With 64 requests waiting, it stops reading.
- **Nothing accumulates over a long session.** Layers and views are held weakly, and everything a connection owns is released when it closes.
- **Bad input doesn’t crash the app.** Malformed data and extreme requests are answered with errors.

## Between the two

Neither side buffers without limit for the other. When Cutaway reads slower than the server sends, the server stops starting new work; when the server has too many requests waiting, it stops reading, and TCP flow control makes Cutaway wait. The rules are in the [protocol](/protocol/).
