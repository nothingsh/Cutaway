---
description: How Cutaway and CutawayServer talk to each other, in one page.
---

# The Cutaway Protocol

Cutaway and CutawayServer share no code. They talk over a small, versioned wire protocol defined in its own repository, [CutawayProtocol](https://github.com/nothingsh/CutawayProtocol): a [FlatBuffers](https://flatbuffers.dev) schema, a normative [specification](/protocol/spec) with numbered clauses, and fixtures for testing either end. Both sides pin a tag of that repository as a git submodule and generate their code from the schema.

This page is an orientation. Every rule below is a clause of the specification (`P-TRANS-01`, `P-FRAME-03`, …), linked where it matters.

<div class="facts">
  <Badge type="info" text="Protocol 1.2" />
  <Badge type="info" text="FlatBuffers" />
  <Badge type="info" text="MIT license" />
</div>

<PartsDiagram />

## Transport

- The server listens on TCP, **loopback only**, trying ports 48160 through 48167 in order and binding the first one available (P-TRANS-01, 02).
- A simulator shares the Mac’s loopback address. A device connected over USB is reached through macOS’s `usbmuxd`, which the server knows nothing about.
- One client at a time: while a connection exists, a new one gets `Error` (code `Busy`) and is closed (P-TRANS-03).

Transports beyond loopback, such as Wi-Fi, are left to a later version, and would have to authenticate and encrypt the connection.

## Frames

<FrameDiagram />

A frame is a 4-byte little-endian length `N` followed by `N` bytes holding one ordinary FlatBuffer with root type `Frame` and file identifier `CTWY` (P-FRAME-01, 02). This is **not** FlatBuffers’ size-prefixed format; the `.stream` fixtures show the exact bytes.

`N` may not exceed 256 MiB, and a receiver verifies the whole buffer before reading any field (P-FRAME-03, 04). A frame that fails gets the connection closed.

## Handshake and versions

The client’s first frame is `Hello`; the server always answers with its own `Hello`, carrying its protocol version and information about the app (P-HELLO-01, 02).

- **Major versions differ:** the handshake fails and both sides close (P-HELLO-03). Because the server still sent its `Hello`, Cutaway can show which versions met and why the app can’t be inspected.
- **Minor versions differ:** the handshake succeeds and both sides work at the lower minor version (P-HELLO-04).

[Versions and compatibility](/protocol/versions) has the rules and which releases work together.

## Requests, streams and events

<ExchangeDiagram />

- **`request_id`.** The client numbers its requests from 1, increasing within a connection; every response carries the number of its request. 0 is reserved for the handshake, events, and errors that answer no particular request (P-REQ-01).
- **Ordinary requests** get exactly one response: `GetAppIcon`, `GetHierarchy`, `GetSubtree`, `SetAttribute`, and since 1.2 `GetEnvironment` and `SetEnvironment` (P-REQ-02).
- **Streaming requests.** `GetLayerDetails` asks for images, attributes and constraints by layer ID. Its response is zero or more `LayerDetailsChunk` frames, then exactly one `StreamEnd` (P-REQ-03).
- **Cancel.** `Cancel` ends a stream early; the stream ends with `StreamEnd` (status `Cancelled`). It has no response of its own (P-REQ-04).
- **Order.** The server handles requests one at a time, in the order received, except `Cancel`, which it handles while the current request is in progress (P-REQ-06).
- **Backpressure.** With 64 requests outstanding, the server may pause reading; TCP flow control then holds the client back. The protocol has no flow control of its own (P-REQ-09).
- **Events.** The server sends `AppStateChanged` with `request_id` 0 right after the handshake and whenever the app’s active state changes (P-EVT-01, 02). While the app is not active, requests that capture or change it fail with `AppNotActive` (P-APP-01).

## Errors

`Error` carries a stable `ErrorCode` and a human-readable English message. Clients branch on the code, never on the text.

| Code | Meaning |
|---|---|
| `Unknown` | An unclassified error |
| `MalformedFrame` | The frame’s length, file identifier or verification is invalid |
| `UnexpectedMessage` | A message that should not appear in the current state |
| `Busy` | The server is already serving another client |
| `AppNotActive` | The app is not active and cannot be captured |
| `Internal` | An internal server error |
| `LayerNotFound` | The layer the request names does not exist |
| `AttributeNotEditable` | The attribute does not exist or cannot be modified |
| `InvalidAttributeValue` | The value to write is invalid, or outside the attribute’s limits |
| `NotSupported` | The server cannot apply an override the request asks for (1.2) |

## What the messages carry

| Message | What it is for |
|---|---|
| `GetAppIcon` → `AppIcon` | The app’s icon, for the app list |
| `GetHierarchy` → `Hierarchy` | The whole layer tree, without images or attributes |
| `GetSubtree` → `Hierarchy` | A layer and all its descendants, for refreshing part of the tree |
| `GetLayerDetails` → `LayerDetailsChunk`…, `StreamEnd` | Images, attributes and constraints of the layers asked for |
| `SetAttribute` → `SetAttributeResult` | Changes one attribute of one layer; the result has the layer’s attributes after the change |
| `GetEnvironment`, `SetEnvironment` → `Environment` | The app’s trait environment and Cutaway’s overrides of it (1.2) |
| `AppStateChanged` | Event: the app became active or inactive |

## Go further

<NextSteps :items="[
  { title: 'Versions and compatibility', text: 'How the protocol evolves, and which releases work together.', link: '/protocol/versions' },
  { title: 'Implementing a peer', text: 'Generate the code, test against the fixtures.', link: '/protocol/implementing' },
  { title: 'Specification', text: 'The normative text, clause by clause.', link: '/protocol/spec' }
]" />
