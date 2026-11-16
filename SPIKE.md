# SPIKE: interaction layer

Question: can Kiln detect a modifier held during a file drag, detect that a drag is active, and show a borderless panel at the cursor that receives the drop, with public APIs only?

**Answer: yes, with no permission prompt.** Run 2026-11-17 on macOS 27, Apple silicon. Throwaway code: `Spike/spike.swift` (commit "Spike", deleted afterwards).

## How it was run
- A real Finder window, a generated PNG, and scripted mouse events (CGEvent) with modifier flags.
- Final runs used the spike as its own ad-hoc-signed `.app` with no permission grants (`AXIsProcessTrusted=false`), so the results are not borrowed from the terminal's permissions.

## Results

| Need | API used | Result | Permission |
|---|---|---|---|
| A drag is active | Global `leftMouseDragged` monitor, plus a change in `NSPasteboard(name: .drag).changeCount` with a file URL on it | Works. Detected on the first drag event | None |
| Modifier held during the drag | Poll `NSEvent.modifierFlags` at 30 Hz while a drag is active | Works. Shift, Command and Control each picked correctly | None |
| Switch wheel mid-drag | Same poll | Works. Shift to Command to Control switched the wheel | None |
| Wheel stays after modifier release | Do not hide when flags become empty | Works | None |
| Panel at the cursor | Borderless `NSPanel`, `.nonactivatingPanel`, level `.popUpMenu`, `orderFrontRegardless` | Works. Shown about 40 ms after detection, over Finder | None |
| Panel receives the drop | `registerForDraggedTypes([.fileURL])` on the content view | Works. `draggingEntered`, `prepareForDragOperation`, `performDragOperation` fired; the file URL was readable | None |
| Position inside the panel during the drag | `draggingLocation` in `draggingUpdated` / `performDragOperation` | Works. Gives the point for wedge hit-testing | None |
| Global hotkey for the keyboard menu | Carbon `RegisterEventHotKey` (Option+Space) | Registration returned 0. Pressing it was not tested | None expected |

No private APIs were used. The fallback (floating drop zone, status-item target) is not needed. A status item stays in the plan for Settings and as a way to quit.

## Caveats (untested)
- Events were scripted. Real hardware modifier keys should look the same to `NSEvent.modifierFlags` but that is unverified. TESTING.md covers it.
- One drop out of three failed in an earlier unprivileged run (the drag entered the panel, no `performDragOperation`). Not reproduced in the next two runs. Cause unknown, so it goes in TESTING.md as a repeat-it item.
- Not tested: full-screen apps and other Spaces, multiple displays, the panel near screen edges, dragging from apps other than Finder, folder or multi-file drags.
- Not tested: reading the Finder selection for the keyboard menu (expected to need the Automation permission), and key handling (Enter, arrows, Escape) in the menu panel, which must become key.
- How Escape behaves in a drag Kiln does not own is still open; the plan is to close the wheel and leave the drag alone (DECISIONS U10).

## Consequences for M3
- DragWatcher = the global monitor + pasteboard check + 30 Hz modifier poll above.
- OverlayPanel = the panel above, sized for two rings, with `draggingUpdated` driving wedge highlight.
- The wheel opens at the cursor position at detection time and stays put.
