---
description: Write your own client or server for the Cutaway Protocol, and test it against the reference fixtures.
---

# Implementing a peer

You can write another client or server for the protocol: a command-line tool that dumps an app’s hierarchy, a server for another UI framework, a test harness. Everything you need is in the [CutawayProtocol](https://github.com/nothingsh/CutawayProtocol) repository, which contains no Swift code of its own.

| Path | What it is |
|---|---|
| `PROTOCOL.md` | The normative [specification](/protocol/spec). Numbered clauses (`P-TRANS-01`, `P-FRAME-03`, …) are requirements; everything else is explanation |
| `schema/cutaway.fbs` | The FlatBuffers schema. Every frame’s payload is a `Frame` defined here |
| `schema/released/` | A snapshot of the schema for every released `MAJOR.MINOR`, never edited after release |
| `fixtures/` | Reference frames for testing an implementation: JSON sources, the compiled buffers, and the exact bytes on the wire |
| `PROTOCOL_VERSION` | The current protocol version |
| `FLATBUFFERS_VERSION`, `FLATC_SHA256` | The pinned `flatc` release and the checksum of its macOS binary |

<div class="steps">

## Read the specification

Read `PROTOCOL.md` end to end. The clauses are short and cross-referenced; [the overview](/protocol/) is a map of them.

## Generate code from the schema

Generate code from `schema/cutaway.fbs` with the pinned `flatc` (see `FLATBUFFERS_VERSION`). `scripts/get-flatc.sh` downloads that exact release into `.tools/` and checks its checksum. Pin a tag of the repository, for example as a git submodule, so the schema you build against doesn’t move under you.

## Test against the fixtures

Each scenario in `fixtures/bin/` has two kinds of file:

- **`.bin`** is one buffer, with no length prefix: for testing that you decode one frame.
- **`.stream`** is one direction of a whole scenario, each frame preceded by its 4-byte length: exactly the bytes on the TCP connection, for testing that you split frames out of a byte stream.

The scenarios cover the handshake and a version mismatch, a busy server, the icon, the hierarchy (with virtual nodes and an excluded subtree), layer details (normal, edge cases, cancelled, failed), the app going inactive, editing attributes (accepted and rejected), subtrees, and the environment. `fixtures/README.md` lists every scenario with the clauses it verifies.

## Raise your verifier’s table limit

If your FlatBuffers runtime’s verifier has a limit on the number of tables, raise it. The protocol allows frames with far more tables than most defaults: a receiver must not reject a conforming frame within the size limit because of its number of tables, its nesting depth or its apparent size (P-FRAME-06).

</div>

## Easy to get wrong

- **The length prefix is not FlatBuffers’.** A frame is a 4-byte little-endian length `N`, then an *ordinary* FlatBuffer. Don’t use FlatBuffers’ size-prefixed functions; the `.stream` fixtures show the exact bytes (P-FRAME-01).
- **Verify before you read.** Verify the whole buffer before reading any field, and close the connection on a frame that fails, is too long (over 256 MiB) or has the wrong identifier (P-FRAME-03, 04).
- **Defaults are omitted.** `flatc` does not write fields equal to their defaults, so they read back as 0, false, or the enum’s first member. Write your expectations accordingly.
- **The server always answers `Hello`.** Even when the major versions differ, the server sends its own `Hello` before closing, so a client can tell the user why. Before the handshake completes, any other frame a client receives means the handshake failed (P-HELLO-02, 03, 07).
- **Work at the lower minor version.** Never send a message, enum value or union member the negotiated minor version doesn’t have; new table fields are fine (P-HELLO-04).
- **Every frame the client sends takes its own `request_id`**, including `Cancel`, increasing from 1. Match responses by `request_id`, not by order alone (P-REQ-01).
- **`Cancel` can arrive late.** A stream may end normally before the server reads your `Cancel`; then the `Cancel` is ignored. Keep fewer than 64 requests outstanding so the server never pauses reading and `Cancel` takes effect promptly (P-REQ-04, 09).
- **Branch on error codes, never on messages.** `Error.message` is English text for people (Error codes in the [specification](/protocol/spec#error-codes)).
- **A server waits 5 seconds for `Hello`**, then closes the connection (P-HELLO-06).

## Check the protocol repository itself

The repository’s `scripts/verify.sh` downloads the pinned `flatc`, compiles the schema, rebuilds every fixture and compares the result with `fixtures/bin/`, checks the fixtures against the clauses the schema cannot express, and checks that the schema is an allowed evolution of the latest released snapshot. It needs `bash`, `curl` and `python3`, and runs on macOS only.

## Next

<NextSteps :items="[
  { title: 'Specification', text: 'The normative text, clause by clause.', link: '/protocol/spec' },
  { title: 'Versions and compatibility', text: 'How the protocol evolves.', link: '/protocol/versions' },
  { title: 'Contributing', text: 'Propose a change to the protocol.', link: '/resources/contributing' }
]" />
