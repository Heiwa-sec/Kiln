# COVERAGE

Every requirement in the design brief (kept out of this repo, cited here by section number) mapped to where it is implemented and how it was checked.

**Status key.** TESTED: a unit test runs it. SEEN: watched working in a short scripted run, not repeatable by test. UNTESTED: built, never run. NOT IMPLEMENTED: with a reason. N/A: not needed for a personal open-source app.

Counts as of this commit: 85 unit tests pass (`swift test`); the app builds (`xcodebuild`); the registry reports 126 supported conversion pairs on the build Mac.

## §1 Product summary

| Requirement | Status | Where | Test |
|---|---|---|---|
| Drag a file, hold a modifier, drop on a wedge | SEEN (wheel opens, hover, outer ring). The drop was seen only in the spike, not in the final app | `App/Interaction/DragWatcher.swift`, `Overlay.swift`, `App/Wheel/*` | `WheelGeometryTests` (hit-testing); SPIKE.md |
| All conversion runs locally, no upload | TESTED (no network code; HTML import checked against a local listener) | all of `Sources/KilnCore`, `DocumentConverter.sanitizedHTML` | `HTMLPrivacyTests` |
| Apple silicon, macOS 13+ | Builds for arm64 with deployment target 13. Never run on macOS 13 | `project.yml` | none |
| No Dock icon (agent app) | UNTESTED beyond launching | `project.yml` (`LSUIElement`), `App/KilnApp.swift` | none |

## §2.1 Three wheels

| Requirement | Status | Where | Test |
|---|---|---|---|
| Convert wheel (Shift) | SEEN | `WheelModel.convertNodes` | `RegistryTests` |
| File tools wheel (Command) | UNTESTED live; tools themselves TESTED | `WheelModel.toolNodes`, `Sources/KilnCore/Tools/*` | `ToolTests` |
| File actions wheel (Control) | UNTESTED live | `App/Actions/FileActions.swift` | `ShellQuoteTests` (Copy Path quoting only) |
| 275 conversion options | NOT IMPLEMENTED as a number: 126 pairs on this Mac. Only native or optional-ffmpeg pairs are offered | `Registry.standard` | `RegistryTests.reportsPairCount` |
| 26 file tools | NOT IMPLEMENTED: 8 tools (compress image, resize, rotate, strip metadata, merge PDF, split PDF, compress video, extract audio). Crop and Trim need parameter UI; the other names are unknown | `Sources/KilnCore/Tools` | `ToolTests` |
| 6 file actions: AirDrop, Float, Copy, Move, Copy Path, Terminal | UNTESTED live | `FileActions.swift` | `ShellQuoteTests` |
| File actions work on folders and mixed selections | UNTESTED | `FileActions.run` (acts on any URL) | none |
| Actions don't use the conversion allowance | N/A: there is no allowance (DECISIONS U4) | none | none |
| Wheel stays open after the modifier is released | SEEN in the spike and in the first app run | `DragWatcher.tick` | none |
| Shortcuts changeable in Settings | UNTESTED | `App/Settings/GeneralTab.swift`, `Prefs.swift` | none |
| Other Settings (§2.1 says only that settings exist): quality, metadata, size, DPI, bitrate, GIF and video options | Engine effect TESTED; the UI is UNTESTED | `ConversionOptions.swift`, `App/Settings/QualityTab.swift` | `OptionsTests` |
| Compatibility table of supported pairs | UNTESTED UI; reads `Registry.support` | `App/Settings/PairsTab.swift` | `RegistryTests` |

## §2.2 Keyboard format menu

| Requirement | Status | Where | Test |
|---|---|---|---|
| Open the menu on a selected file | UNTESTED. Opens by global hotkey, not bare Enter (DECISIONS U2) | `KeyboardMenu.swift`, `HotKey.swift` | none |
| Arrows move, Enter applies, Escape cancels | UNTESTED | `KeyboardMenuController.key` | none |
| Command or Control switches wheels | UNTESTED. Uses each wheel's configured key | `KeyboardMenuController.flags` | none |
| Selection source | Decided: Finder selection through Apple Events (needs the Automation permission) | `FinderSelection` | none |

## §2.3 Touch input

| Requirement | Status |
|---|---|
| Hold before drag starts a conversion | NOT IMPLEMENTED: hardware unknown, and there is no hold signal from a Mac drag source (DECISIONS U3) |

## §2.4 Supported formats

| Family | Status | Where | Test |
|---|---|---|---|
| Images: JPG, PNG, HEIC, TIFF, BMP, GIF in and out; PDF out | TESTED | `ImageConverter` | `ImageTests` |
| Images: WebP, AVIF | Probed at launch. On the build Mac AVIF in and out are available, WebP output is not | `ImageConverter.init` | `ImageTests.reportsWhichImageTargetsExistHere` (prints) |
| Images: SVG input | NOT IMPLEMENTED: no suitable public SVG rasterizer | none | `RegistryTests.unsupportedPairsAreMarked` |
| PDF to JPG, PNG (all pages, 300 DPI), TXT, MD | TESTED | `PdfConverter` | `PdfTests` |
| PDF to DOCX, Pages, PPTX, XLSX, EPUB | NOT IMPLEMENTED: needs a bundled JVM or templates (DECISIONS U6) | none | `RegistryTests.unsupportedPairsAreMarked` |
| Documents: DOCX, RTF, RTFD, HTML, TXT, MD | TESTED (MD input only; no MD output) | `DocumentConverter` | `TextFormatTests`, `HTMLPrivacyTests` |
| Documents: Pages, EPUB output; text-clipping input | NOT IMPLEMENTED: no native writer or reader | none | none |
| Slides (PPT, PPTX) | NOT IMPLEMENTED: no native engine | none | none |
| Spreadsheets: CSV, TSV | TESTED | `TableConverter` | `TextFormatTests` |
| Spreadsheets: XLSX, ODS, XLS, PDF export | NOT IMPLEMENTED: no native zip/XML spreadsheet engine | none | none |
| Subtitles: SRT, VTT, TXT export | TESTED | `SubtitleConverter` | `TextFormatTests` |
| Audio: MP3, M4A, WAV, AIFF, FLAC in; M4A, WAV, AIFF, CAF, FLAC out | TESTED | `AudioConverter` | `AudioTests` |
| Audio: MP3, Ogg, Opus out; OGG, Opus, WMA in | Optional ffmpeg. TESTED only against a stand-in script | `FFmpegConverter` | `FFmpegTests` |
| Video: MP4, MOV, GIF | TESTED (MP4, MOV in; MP4, MOV, M4A, GIF out) | `VideoConverter` | `VideoTests` |
| Video: MKV, WebM, AVI, WMV; MP3 export | Optional ffmpeg, as above | `FFmpegConverter` | `FFmpegTests` |
| Archives: ZIP, TAR, GZIP create and extract | TESTED, including a hand-built zip with a `../` entry | `ArchiveConverter.swift` | `ArchiveTests` |
| Archives: RAR input | NOT IMPLEMENTED | none | `ArchiveTests.rarIsUnsupported` |
| Full input-to-output matrix | Decided: whatever the registry reports (DECISIONS U5) | `Registry` | `RegistryTests` |

## §3 Engine architecture

| Requirement | Status | Where | Test |
|---|---|---|---|
| Video and audio transcode | Different on purpose: AVFoundation, optional user-installed ffmpeg, nothing bundled (DECISIONS D10) | `VideoConverter`, `AudioConverter`, `FFmpegConverter` | `VideoTests`, `AudioTests`, `FFmpegTests` |
| WebP encode | NOT IMPLEMENTED: ImageIO can't encode WebP here | none | none |
| Image I/O (ImageIO, CoreImage, CoreGraphics) | TESTED (ImageIO, CoreGraphics; CoreImage not used) | `ImageConverter`, `ImageTools.swift` | `ImageTests`, `ToolTests` |
| PDF render and text (PDFKit) | TESTED | `PdfConverter`, `MediaTools.swift` | `PdfTests`, `ToolTests` |
| PPT/PPTX conversion | NOT IMPLEMENTED (U6) | none | none |
| Pages output | NOT IMPLEMENTED (U6) | none | none |
| Metadata read/strip | Strip TESTED. Reading/viewing metadata is NOT IMPLEMENTED | `StripMetadata` | `ToolTests.stripMetadataRemovesGPSAndEXIFButKeepsPixels` |
| Cloud (iCloud) placeholder files | NOT IMPLEMENTED: Kiln does not trigger downloads; an undownloaded file will read as unreadable | none | none |
| Vision usage | NOT IMPLEMENTED: purpose unknown | none | none |
| Highlight sound | NOT IMPLEMENTED on purpose: silence (U17) | none | none |
| SwiftUI + AppKit | Done | `App/` | build |

## §4 Licensing and commerce

| Requirement | Status |
|---|---|
| Subscription layer, ad attribution, allowance, tiers | N/A: none of it belongs in a personal open-source app (U4) |

## §5 Network and file protocols

| Requirement | Status | Where | Test |
|---|---|---|---|
| No upload of user files; no network | TESTED for HTML input; otherwise by absence of network code | whole repo | `HTMLPrivacyTests` |
| No file associations or URL scheme | Done: none registered | `project.yml` | none |

## §6 Settings and persistence

| Requirement | Status | Where | Test |
|---|---|---|---|
| UserDefaults with a documented key list | UNTESTED. Keys documented in README | `Prefs.swift` | none |
| Timestamps, boot time | N/A: no feature uses them | none | none |
| Launch at login | UNTESTED. Exposed in Settings through `SMAppService` | `GeneralTab.swift` | none |
| Output location and naming rules | Naming TESTED. The folder setting is UNTESTED in the UI | `Naming.swift`, `OutputPolicy` | `NamingTests`, `RunnerTests` |

## §7 Error behavior

| Case | Status | Where | Test |
|---|---|---|---|
| Unsupported pair | TESTED | `KilnError.unsupportedPair` | `RunnerTests.unsupportedPairIsTyped` |
| Corrupt input | TESTED for image, PDF, audio, video, archive | `KilnError.corruptInput` | `ImageTests`, `PdfTests`, `AudioTests`, `VideoTests`, `ArchiveTests` |
| Name collision | TESTED | `Naming`, `KilnError.nameCollision` | `NamingTests`, `RunnerTests` |
| Disk full | TESTED by simulation only (a converter throws the out-of-space error). Never tested on a full disk | `KilnError.from` | `ErrorMappingTests`, `RunnerTests.diskFullIsTypedAndCleansUp` |
| Cancel mid-job | TESTED with a stub converter. Not tested on a real long conversion | `JobRunner` | `RunnerTests.cancelRemovesPartialOutput` |
| Encrypted PDF | TESTED | `PdfConverter` | `PdfTests.encryptedPDF` |
| Archive with unsafe paths | TESTED (extra case, added for security) | `ArchiveExtractor` | `ArchiveTests.zipSlipIsRefusedAndNothingEscapes` |
| Messages shown to the user | UNTESTED in the UI; text is covered | `KilnError.message`, `HUD.swift` | `ErrorMappingTests.everyCaseHasADistinctMessage` |
| Allowance exhausted, offline purchase check | N/A | none | none |

## §9 Open items

| Item | Resolution |
|---|---|
| Wheel geometry, ordering, submenus, hit-testing, Escape mid-drag | Own two-ring design (U9). Hit-testing TESTED. Escape needs the Accessibility permission, UNTESTED |
| Modifier-held-during-drag timing, wheel position | SEEN: opens under the cursor early in the drag and stays put |
| Multi-file and folder drops | Decided (U11). UNTESTED in the UI; folder input and multi-file merge are TESTED in the engine |
| Output location and naming | Decided (U12). TESTED |
| Progress, cancel and result UI | Decided (U13). UNTESTED |
| Clipboard output for Copy and Copy Path | Decided (U8, U14). Quoting TESTED against a real shell; pasteboard writes UNTESTED |
| Undo/redo | NOT IMPLEMENTED (U15) |
| Settings window contents and rebinding rules | Decided (U16). UNTESTED |
| Every error state | See §7 |
