---
description: How the Cutaway Protocol is versioned, and which releases of Cutaway and CutawayServer work together.
---

# Versions and compatibility

The protocol version is `MAJOR.MINOR`; releases of the protocol repository are tagged `vMAJOR.MINOR.PATCH`. Cutaway and CutawayServer each speak one protocol version, and the handshake decides what they use together.

## Which releases work together

| Cutaway | CutawayServer | Protocol |
|---|---|---|
| 1.0.0 | 1.0.0 | 1.0 |
| 1.1.0 | 1.1.0 | 1.1 |
| 1.2.0 | 1.2.0 | 1.2 |

**Any 1.x Cutaway works with any 1.x CutawayServer.** When their minor versions differ, both work at the lower one: Cutaway 1.2 with CutawayServer 1.1 speaks protocol 1.1, and so does Cutaway 1.1 with CutawayServer 1.2. You get what the older side knows.

A 0.x release and a 1.x release cannot work together: 1.0 was a major version, and the handshake fails by design.

## What needs 1.2 on both sides

These arrived with protocol 1.2. They appear only when both Cutaway and CutawayServer are 1.2 or later:

| Feature | Where it shows |
|---|---|
| Overriding the app’s environment: appearance, text size, layout direction, size classes | The Environment button in the toolbar, **View › Environment** |
| Virtual nodes, views collapsed by default, views excluded from images | The layer list and the preview; see [Customizing](/integrate/customizing) |
| Attribute groups the app adds | The App section of the inspector |
| Colors named by the app; a dynamic color’s light and dark values | The color rows of the inspector |
| The Accessibility section | The inspector |
| Attributes that refer to other layers, such as a stack view’s `arrangedSubviews` | Chips you can point at and click |

With an older side, the rest of Cutaway works as before; these are simply absent.

## When versions don’t match

If the major versions differ, Cutaway still lists the app, with both versions, and explains that it can’t be inspected. Update the older side: Cutaway from its [releases](https://github.com/nothingsh/Cutaway/releases) or **Cutaway › Check for Updates…**, CutawayServer by raising the version in your package dependency.

## How the protocol evolves

- **Append only.** The schema grows by appending: fields at the end of tables, members at the end of enums and unions. Structs, the file identifier and the root type never change. Anything else is a new major version (P-EVO-01 to 03).
- **Absent means as before.** A field a sender of an earlier version does not write must mean the behavior from before it was added (P-EVO-06).
- **Minor versions are negotiated.** Neither side sends a message, enum value or union member that does not exist in the negotiated minor version. New table fields may be sent anyway, because a receiver ignores fields it does not know (P-HELLO-04, P-EVO-07).
- **Patch versions** change wording or fixtures without touching the schema.
- **Frozen at 1.0.** The protocol has been frozen since 1.0: from there it only grows, in minor versions. The frame format and the first ten messages, `Hello` to `Error`, never change in any major version, so that any two versions can always read each other’s handshake (P-EVO-05).

The full rules are the `P-EVO` clauses of the [specification](/protocol/spec#evolution).

## Archives

A `.cutaway` archive records the protocol version that was negotiated when it was saved. Archives involve no negotiation, so Cutaway does not open an archive written under a newer minor version than its own: it says the archive is newer instead of misreading it. Older archives open as before.

## Next

<NextSteps :items="[
  { title: 'Implementing a peer', text: 'Generate the code, test against the fixtures.', link: '/protocol/implementing' },
  { title: 'Release notes', text: 'What each release of Cutaway added.', link: '/resources/releases' }
]" />
