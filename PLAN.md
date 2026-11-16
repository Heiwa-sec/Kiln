# PLAN: Kiln

> Scope note: this is the original plan. Where the build differs, DECISIONS.md is authoritative (for example, the registry reports its real pair count instead of the matrix below, and video to WAV was dropped). COVERAGE.md has the line-by-line status and TESTING.md the manual checklist.

Drag a file, hold a modifier, drop on a wedge. Local-only. Apple silicon, macOS 13+. Swift 6.

Nothing here is built yet. Status marks below: **native** = a system framework does it, **probe** = checked at runtime because it depends on the macOS version, **ffmpeg** = only with a user-installed ffmpeg, **no** = shown as unsupported in the UI. All "native" rows are untested until the engine tests run.

## Milestones

| M | What | Done when |
|---|---|---|
| M0 | Scaffold: `Package.swift`, `project.yml`, git, docs skeleton | `swift build` and `xcodegen` + `xcodebuild` succeed on empty targets |
| M1 | Spike on the interaction layer (throwaway target) | SPIKE.md lists what works, what needs permissions, and the fallback if drag + modifier fails |
| M2 | Core engine, no UI (`KilnCore`) | Registry, runner, errors, naming, all native converters, tests pass on generated files |
| M3 | Interaction layer: agent app, drop target, 3 wheels, keyboard menu, file actions | App builds and launches headless. Behavior goes in TESTING.md as untested |
| M4 | Settings, persistence, error messages | UserDefaults key list documented. Six error cases mapped and unit-tested |
| M5 | COVERAGE.md, TESTING.md, README, LICENSE, icon | Every spec line has a row. Build and tests are clean |

Build after every milestone. One small commit per step. No push without asking.

## Module layout

```
Package.swift                 KilnCore (library) + KilnCoreTests
Sources/KilnCore/
  Model/       FileKind, Format, ConversionKey, ToolID
  Engine/      Converter (protocol), Registry, JobRunner (actor), KilnError, Naming, OutputPolicy
  Converters/  Image, Pdf, Document, Subtitle, Table, Audio, Video, Archive, FFmpegOptional
  Tools/       StripMetadata, CompressImage, ResizeImage, RotateImage, MergePdf, SplitPdf, CompressVideo, ExtractAudio
Tests/KilnCoreTests/          registry, naming, error mapping, one test per converter family
project.yml                   XcodeGen: app target "Kiln", depends on KilnCore
App/
  KilnApp, AppDelegate        agent app (LSUIElement), status item
  Interaction/                DragWatcher, OverlayPanel, WheelView, KeyboardMenu, HotKey
  Actions/                    AirDrop, Float, Copy, Move, CopyPath, Terminal
  Settings/                   SettingsView, Prefs (typed UserDefaults keys), ShortcutRecorder
  Design/                     Palette.swift (the only place colors live)
Spike/                        throwaway; deleted after SPIKE.md is written
```

Core types: `Converter` (async throws, reports `Progress`, honors cancel), `Registry` keyed by `ConversionKey(input: Format, output: Format)`, `JobRunner` (an actor: queue, progress stream, cancel, partial-output cleanup), `KilnError` (typed, one user message each).

## Conversion matrix

| Family | Inputs | Outputs | Engine |
|---|---|---|---|
| Image | JPG, PNG, HEIC, TIFF, BMP, GIF (first frame) | JPG, PNG, HEIC, TIFF, BMP, GIF, PDF | native (ImageIO) |
| Image | WebP, AVIF | same outputs | probe (decode) |
| Image | any | WebP, AVIF | probe (encode), else ffmpeg |
| Image | SVG | any | no |
| PDF | PDF | PNG, JPG (all pages at 300 DPI, into a folder), TXT, MD | native (PDFKit) |
| PDF | PDF | DOCX, Pages, PPTX, XLSX, EPUB | no |
| Document | DOCX, RTF, RTFD, HTML, TXT, MD | DOCX, RTF, RTFD, HTML, TXT | native (NSAttributedString, markdown parser) |
| Document | any | Pages, EPUB, PDF | no (PDF export is a stretch goal) |
| Slides | PPT, PPTX | anything | no |
| Spreadsheet | CSV, TSV | TSV, CSV | native (own parser) |
| Spreadsheet | XLSX, ODS, XLS | anything | no |
| Subtitle | SRT, VTT | VTT, SRT, TXT | native (own parser) |
| Audio | MP3, M4A, WAV, AIFF, FLAC, CAF | M4A (AAC), WAV, AIFF, CAF | native (AVFoundation) |
| Audio | MP3, M4A, WAV, AIFF, FLAC, CAF | FLAC | probe |
| Audio | any | MP3 | ffmpeg |
| Audio | OGG, Opus, WMA | any | ffmpeg |
| Video | MP4, MOV, M4V | MP4, MOV (re-encode), GIF (capped length), M4A, WAV (audio only) | native (AVFoundation, ImageIO) |
| Video | MKV, WebM, AVI, WMV | any | ffmpeg |
| Video | any | WebM, MKV, AVI, WMV, MP3 | ffmpeg |
| Archive | file or folder | ZIP, TAR, GZIP (single file only) | native (system `ditto`, `tar`, `gzip`) |
| Archive | ZIP, TAR, GZIP | extract to folder | native (same tools) |
| Archive | RAR | extract | no (maybe via `tar`, to be checked in M2) |

The registry reports the real number of supported pairs in a test. The count is a result, not a target.

## File tools (Command wheel)

Strip metadata (image), Compress image (JPEG/HEIC quality), Resize image (50%, 25%, max edge 1920), Rotate image 90°, Merge PDFs (multi-file drop), Split PDF (one file per page), Compress video (export preset), Extract audio. That's 8 tools.

NOT IMPLEMENTED, with reason: Crop and Trim (they need parameter UI).

## File actions (Control wheel)

AirDrop (`NSSharingService`), Float, Copy, Move, Copy Path, Terminal. They work on files, folders and mixed selections. All use public APIs.

## Interaction layer: expected approach, to be proven in M1

Not assumed to work until M1 runs it.
1. **Drag active:** global mouse-dragged monitor plus a change in the drag pasteboard. Expected to need no permission.
2. **Modifier during drag:** poll `NSEvent.modifierFlags` (class property) while a drag is active. Expected to need no permission.
3. **Overlay:** a borderless non-activating panel at the cursor that registers for file drops. Expected to work for any window under the cursor.
4. **Keyboard menu:** a global hotkey, registered through the Carbon hot-key API (public, no permission), opens the menu on the Finder selection. Reading the Finder selection needs the Automation permission.
5. **Fallback if 1–3 fail:** a status-item drop target and a floating drop zone, each showing the same wheels. SPIKE.md will say which.

## Design

Own name, own icon (generated by a script, flat glyph, no gradient), no sounds. System font stack. A flat dark surface and a small palette in `Palette.swift`: ash text, charcoal surface, one verdigris accent, one amber for warnings. No gradients, no cards with colored borders, no glass. Wheel is two flat rings with thin gaps.

## Known risks

- Drag + modifier detection may behave differently across macOS versions. M1 decides.
- Ad-hoc signing makes macOS forget Accessibility/Input Monitoring grants on each rebuild.
- UI behavior counts as untested until it has been run by hand; TESTING.md is the checklist.
- Developer ID signing and notarization are untested (no paid account).
- "Native" rows may fall short on the actual macOS version. The probes and tests will show where.
