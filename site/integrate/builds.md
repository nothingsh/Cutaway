---
description: Which builds of your app contain CutawayServer, and how to use it in configurations other than Debug.
---

# Debug and Release builds

By default CutawayServer is compiled only into builds that define `DEBUG`. In every other build `start()` is an empty function, and the product contains no listening code.

<BuildsDiagram />

## Which configurations define `DEBUG`

Whether the package sees `DEBUG` depends on the **name** of the host app’s build configuration, not on its settings:

| Host configuration name | `DEBUG` defined in the package? |
|---|---|
| `Debug`, and names that contain `Debug` or `Development` (for example `DebugQA`) | Yes |
| `Release`, `Staging`, `QA` and any other name, even if the configuration was copied from Debug | No |

So a configuration named `Staging` that was copied from `Debug` still builds CutawayServer as an empty function, and the app never appears in Cutaway’s list.

## Use the server in other configurations

To use the server in configurations of the second kind, enable the package trait `ReleaseEnabled`.

::: code-group

```swift [Package.swift]
.package(
    url: "https://github.com/nothingsh/CutawayServer",
    from: "1.2.0",
    traits: ["ReleaseEnabled"]
)
```

```text [Xcode project]
Enable the trait ReleaseEnabled on the CutawayServer package dependency.
```

```text [XcodeGen]
List the trait under packages.<name>.traits.
Demo/release-enabled.yml in the CutawayServer repository is an example.
```

:::

::: danger The trait applies to every configuration
Once `ReleaseEnabled` is on, the server is compiled into **every** configuration of the host, including the one you submit to the App Store. It is then up to your app not to call `start()` in builds it ships, for example by calling it only under a condition of your own.
:::

## What a build without the server contains

Without `DEBUG` and without the trait, the product contains nothing of the package but the entry point: no server, no `Network` symbols, and none of the protocol’s encoding code. CutawayServer’s own test script checks this on its demo app’s Release build with `nm`.

The [extension interface](/integrate/customizing) (`describe`, `registerColor`) is compiled in every configuration too, so your app can call it without conditions of its own; without the server, registering does nothing.

`CutawayWire` and `CutawayFlatBuffers`, the package’s other modules, are implementation details. A host can import them in a Debug build, but nothing in them is public API or covered by the version number.

## Next

<NextSteps :items="[
  { title: 'Customizing what Cutaway shows', text: 'Your own attributes, virtual nodes and color names.', link: '/integrate/customizing' },
  { title: 'Behavior on the device', text: 'What the server listens on and what capturing touches.', link: '/integrate/on-device' }
]" />
