# KERNARIUM_DISPLAY_WIDTH / HEIGHT (local bakeoff fork)

In `Kernarium/Kernarium/ContentView.swift`, just after the guest size is
taken from the view's pixel size and before `width`/`height` are computed,
honor an optional fixed surface. Cap is the existing 4095-pixel bound
(`GuestInputCoordinateSpace.maximumDisplayDimension`). When both env vars
are set, auto-resize is turned off so a later layout pass does not undo
the size. Log line:

    Kernarium: fixed guest display 1920x1080 (auto-resize off)

Pass them through `simctl` as `SIMCTL_CHILD_KERNARIUM_DISPLAY_WIDTH` and
`SIMCTL_CHILD_KERNARIUM_DISPLAY_HEIGHT`.

```swift
        var size = GuestInputCoordinateSpace.boundedDisplaySize(
            geometry.pixelSize
        )
        var autoResizeGuest = configuration.autoResizeGuest
        // Local bakeoff fork: a fixed guest surface (for example 1920x1080)
        // can be larger than the Simulator view and is letterboxed by the
        // existing aspect-fit path. Auto-resize would undo it.
        let env = ProcessInfo.processInfo.environment
        if let widthText = env["KERNARIUM_DISPLAY_WIDTH"],
           let heightText = env["KERNARIUM_DISPLAY_HEIGHT"],
           let requestedWidth = Double(widthText),
           let requestedHeight = Double(heightText),
           requestedWidth >= 1, requestedHeight >= 1,
           requestedWidth <= 4095, requestedHeight <= 4095 {
            size = GuestInputCoordinateSpace.boundedDisplaySize(
                CGSize(width: requestedWidth, height: requestedHeight)
            )
            autoResizeGuest = false
            print(
                "Kernarium: fixed guest display "
                    + "\(Int(size.width.rounded(.down)))x\(Int(size.height.rounded(.down))) "
                    + "(auto-resize off)"
            )
        }
        let width = UInt32(size.width.rounded(.down))
        let height = UInt32(size.height.rounded(.down))
```

The existing `autoResizeGuest` value (not `configuration.autoResizeGuest`
directly) is then passed into `runGuest`.
