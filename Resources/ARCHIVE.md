# Archive Format

Cutaway saves one inspection as a `.cutaway` file (C-ARCH-01). The format is defined by this repository and is not part of the protocol; the frames inside it are protocol messages, kept unchanged. This document is the specification of the format; the code that reads and writes it is in `CutawayKit/Sources/CutawayWire/Archive/` (`ArchiveManifest.swift`, `ArchiveEncoder.swift`, `ArchiveDecoder.swift`).

The uniform type identifier is `dev.cutaway.archive`, conforming to `public.data`, with the extension `cutaway`.

## Structure

All integers are unsigned and little-endian. An archive consists of, in order:

| Section | Content |
|---|---|
| Magic | 8 bytes, ASCII `CTWYARCH` |
| Format version | `u32`. This document describes version 1 |
| Manifest | `u32` length, followed by that many bytes of a UTF-8 JSON object |
| Interface state | `u32` length, followed by that many bytes. See "Interface state"; may be empty |
| Frames | Zero or more. Each is the same as a frame on the wire (P-FRAME-01): a `u32` length (1 to 268435456), followed by a buffer of that many bytes |
| Trailer | `u32` 0, `u32` number of frames, 8 bytes ASCII `CTWYDONE`. The file ends here |

A frame's length is never 0, so reading a length of 0 means the trailer has been reached.

## Manifest

```json
{
  "protocol": { "major": 1, "minor": 0 },
  "cutawayVersion": "0.1.0",
  "savedAt": "2026-10-06T08:30:00Z"
}
```

| Key | Meaning |
|---|---|
| `protocol` | The protocol version negotiated when the frames were obtained (P-HELLO-04). The Server's own version is in the saved `Hello` |
| `cutawayVersion` | The version of the Cutaway that wrote the archive, the same as the `client.version` it sent in its `Hello`. For display and troubleshooting only |
| `savedAt` | When the archive was saved, ISO 8601, UTC, to the second |

All three keys are required. A reader ignores keys it does not recognize. Adding a key does not raise the format version; changing the meaning of an existing key, or changing the structure above, raises the format version by 1.

## Frames

The frames are, in order:

1. The Server's `Hello` (`role` is `Server`, with `app`), exactly one;
2. `AppIcon`, exactly one;
3. `Hierarchy`, exactly one;
4. `Environment`, at most one: the app's trait environment when the archive was saved (C-ENV-04). Written from protocol 1.2 on; an archive without it, from 1.1 for example, has none, and a reader treats it as no overrides;
5. `LayerDetailsChunk`, zero or more. Saving an archive may send several `GetLayerDetails`; their chunks follow one after another.

Each buffer holds the bytes as they were received, not re-encoded, so fields appended by a higher minor version are kept too. `request_id` and `sequence` mean something only on the connection they came from; a reader ignores them. `StreamEnd`, `Error`, `AppStateChanged` and frames sent by the Client are not saved.

Layer IDs are meaningful only within the archive (P-HIER-03). The app may change between `GetHierarchy` and `GetLayerDetails`; the details of a layer that no longer exists by then are `LayerNotFound` (P-DET-02), and are saved as they are.

## Interface state

The state of the interface at the time of saving, restored when the archive is opened (C-ARCH-03). A UTF-8 JSON object, written with its keys in alphabetical order:

```json
{
  "borderStyle": "byKind",
  "cameras": {
    "threeD": { "layerSpacing": 50, "panX": -12, "panY": 30, "pitch": 0.2618, "yaw": 0.5236, "zoom": 1.4 },
    "twoD":   { "layerSpacing": 0, "panX": 0, "panY": 0, "pitch": 0, "yaw": 0, "zoom": 1 }
  },
  "expanded": [1, 2, 4],
  "focused": null,
  "mode": "3d",
  "onlyAppClasses": false,
  "selected": 3,
  "showsBorders": true,
  "showsConstraintEnds": false,
  "showsHiddenLayers": false
}
```

| Key | Meaning | When missing |
|---|---|---|
| `expanded` | The layer IDs of the expanded nodes, in ascending order. An empty list collapses every node | The tree opens as a new inspection's does (C-HIER-09) |
| `selected` | The selected layer ID, or `null` | Nothing selected |
| `focused` | The root of the focused subtree, or `null` | Not focused |
| `mode` | `"2d"` or `"3d"` | The mode for new inspections in Settings (`"2d"` until it is changed) |
| `cameras` | Each mode's own camera: the angles about the vertical and horizontal axes (`yaw`, `pitch`, in radians), `zoom`, the pan (`panX`, `panY`, in points of the viewport), and the layer spacing (`layerSpacing`, in points). The projection follows from the mode and is not saved | The mode's default camera, item by item; the 3D camera's layer spacing is the one in Settings |
| `showsHiddenLayers` | "Show Hidden Layers" | As in Settings (`false` until it is changed) |
| `borderStyle` | The borders' style: `"off"`, `"plain"` or `"byKind"` | `showsBorders` read as below; without it too, the style in Settings (`"byKind"` until it is changed) |
| `onlyAppClasses` | "Only the App's Own Classes": only layers of the app's own classes are outlined | As in Settings (`false` until it is changed), also when `showsBorders` stands for the style |
| `showsConstraintEnds` | "Show Constraint Ends": every other end of the selected view's constraints is marked, not only those pointed at (C-PREV-18) | As in Settings (`false` until it is changed) |
| `showsBorders` | Whether the borders are on; written for readers of earlier versions. Read only when `borderStyle` is missing or not one of its values: `true` is `"byKind"`, `false` is `"off"` | Not read |

The layer IDs come from the same connection as the frames in the archive. The text of the search field is not saved.

When reading, each key is parsed on its own: if it is missing, has the wrong type, or is a number that is not finite, that item takes the value in the last column, which for most items is the one in Settings when the archive is opened (C-PREF-02), and the other items are unaffected; unknown keys are ignored; if the section as a whole is not a JSON object (including when it is empty), every item takes the value in the last column. Failing to understand this section never makes the archive count as damaged. An ID that refers to a layer that does not exist is treated as the default when the archive is opened (C-ARCH-03).

## Reading

A reader makes the checks below in order; the first one that fails decides the result:

| Result | Condition |
|---|---|
| Not an archive | Fewer than 8 bytes, or the magic is not `CTWYARCH` |
| Newer format | The format version is higher than the reader's |
| Incomplete | The file ends before the trailer has been read, including when the length of any section runs past the end of the file |
| Damaged | A frame's length exceeds 268435456; the trailer's magic is wrong; there are bytes after the trailer; the trailer's count does not match the number of frames; the manifest is not a JSON object, or a key is missing or has the wrong type |
| Different protocol major version | The major version in the manifest differs from the reader's |
| Newer protocol minor version | The minor version in the manifest is higher than the reader's |
| Damaged | A frame fails verification (P-FRAME-04, P-FRAME-06); the kinds or the order of the frames do not match the "Frames" section |

The versions are checked before the frames are verified: an archive with a higher minor version may contain union members the reader does not know, which fail verification, but what should be reported is "the archive is newer", not "the archive is damaged".

An archive with a newer minor version is not read: an archive involves no negotiation, and an older reader would silently read a new enum value as the first member. How old archives are handled when the major version is raised is stated by the decision that makes that change (P-EVO-04).

Every frame is verified when the archive is opened, so a bad archive is rejected before anything is shown.

## Writing

A writer first writes the magic, the format version, the manifest and the interface state, then writes each frame as it arrives, and finally writes the trailer. A writer puts only a file whose trailer has been written at the location the user chose (C-ARCH-02); a file without a trailer never appears there.
