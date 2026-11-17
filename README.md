# Kiln

Drag a file, hold a key, drop it on a wedge. Kiln converts files and runs small file tools on your Mac, and nothing leaves the machine.

Kiln is an independent project. It is not affiliated with or endorsed by any other app, and contains no code or assets from one.

**Status: early, partly tested.** The engine has unit tests. The drag, wheel and keyboard behavior has been seen working in short scripted runs only; the full manual checklist is in [TESTING.md](TESTING.md). Nothing here has been run by a person on real hardware yet.

## How it works

Start dragging a file, then hold a key. A two-ring wheel opens under the cursor and stays open until you drop on a wedge or let go off the wheel.

| Hold (default) | Wheel | What it does |
|---|---|---|
| Shift | Convert | Pick a group (Image, PDF, Text, Audio, Video, ...), then a format. Unsupported formats are greyed out. |
| Command | Tools | Compress, resize, rotate, strip metadata, merge or split PDFs, compress video, extract audio. |
| Control | File actions | AirDrop, Float, Copy, Move, Copy Path, Terminal. |

Keyboard path: select files in Finder, press the shortcut (default Option+Space). Arrow keys move, Return applies, Escape closes, a wheel's key switches wheels.

Results are written next to the original (or in a folder you choose). A name that is taken gets a number (`photo 2.tiff`); Kiln never overwrites. Settings (menu bar icon, then Settings, or open Kiln again) has five tabs: **General** (launch at login, menu bar icon, sound, haptics, show finished files in Finder, wheel keys, keyboard shortcut, Float and Terminal choices), **Quality** (JPG/HEIC/AVIF quality, keep metadata, largest side, AAC bitrate, video size, GIF length/rate/width, PDF resolution, each with restore defaults), **Compatibility** (a live table of which conversions work on this Mac, read from the registry), **Folders** and **About**.

## What it converts

Only what macOS can do natively, plus extra formats if you have ffmpeg. The registry reports 126 supported pairs on the Mac this was built on; the exact set depends on your macOS version (WebP and AVIF are probed at launch).

| Kind | In | Out |
|---|---|---|
| Image | JPG, PNG, HEIC, TIFF, BMP, GIF, WebP and AVIF (where macOS reads them) | JPG, PNG, HEIC, TIFF, BMP, GIF, PDF, AVIF (where macOS writes it) |
| PDF | PDF | PNG, JPG (every page, 300 DPI, into a folder), TXT, MD |
| Text | TXT, MD, RTF, RTFD, HTML, DOCX | TXT, RTF, RTFD, HTML, DOCX |
| Sheet | CSV, TSV | TSV, CSV |
| Captions | SRT, VTT | VTT, SRT, TXT |
| Audio | MP3, M4A, WAV, AIFF, FLAC, CAF | M4A, WAV, AIFF, CAF, FLAC |
| Video | MP4, MOV | MP4, MOV, M4A (audio only), GIF (10 s, 480 px at most) |
| Archive | any file or folder; ZIP, TAR, GZIP | ZIP, TAR, GZIP (single files only); extract to a folder |

Not supported, and shown as unsupported rather than faked: slides, XLSX/ODS, EPUB, Pages, PDF to Word, WebM/MKV/AVI/WMV and MP3/Ogg/Opus output (these last need ffmpeg), RAR. HTML input drops images, styles and link targets on purpose: the file is rebuilt from a small allowlist so it can't make Kiln load anything from the network.

**Optional ffmpeg.** If you have ffmpeg (for example `brew install ffmpeg`), Kiln finds it in the usual places and enables MP3, Ogg, Opus, WebM, MKV, AVI and WMV pairs. Kiln never bundles, downloads or commits ffmpeg or its codecs. This path is tested only against a stand-in script, not a real ffmpeg.

## Known limits

- Dropping many files at once starts every job together; there is no queue, so very large batches (hundreds of videos) will be slow and memory-hungry.
- Size caps (100 MB for text-like files, 200 megapixels for images and PDF pages) apply to what is on disk, not to what a compressed file expands to.
- Markdown is converted with inline formatting only (bold, italic, links). Headings and lists stay as plain text.
- PDF to TXT or MD needs selectable text. A scanned PDF gives an error, because Kiln has no text recognition.
- Animated GIFs convert as their first frame.
- The optional ffmpeg path has only been tested against a stand-in script, never a real ffmpeg.

## Install

Paste this in Terminal. It downloads the latest release, checks its checksum, puts Kiln.app in Applications and opens it:

```sh
curl -fsSL https://raw.githubusercontent.com/Heiwa-sec/Kiln/main/scripts/install.sh | bash
```

Run it again to update. To remove Kiln, quit it from the menu bar and delete `/Applications/Kiln.app`. You can also download `Kiln.zip` from the Releases page; because the app is not notarized, macOS will then ask you to allow it in System Settings, which the one-line install avoids.

## Requirements

Apple silicon, macOS 13 or later. Built with Xcode 27.2 and Swift 6.4; older versions are untested. Building from source needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Build

```sh
swift test                      # engine tests
xcodegen generate               # makes Kiln.xcodeproj from project.yml
xcodebuild -project Kiln.xcodeproj -scheme Kiln -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Kiln.app
```

The build is ad-hoc signed, not sandboxed and not notarized. macOS may ask you to allow it in System Settings. Because the signature changes with each rebuild, macOS can forget permissions you granted to a previous build. Developer ID signing and notarization need a paid Apple account and have not been tried.

## Permissions

| What | Needed for | Asked |
|---|---|---|
| None | Drag detection, the wheel, conversions, tools, most file actions | n/a |
| Automation (control Finder) | Keyboard menu: reading the Finder selection | First time you press the shortcut |
| Accessibility | Pressing Escape to close the wheel mid-drag | Optional. Without it, let go off the wheel to cancel |

## Privacy

Kiln has no analytics, no updater and no network code. Files are read and written locally. AirDrop is the only action that sends anything, and only when you pick it.

## Settings keys

Stored in `UserDefaults` for `dev.kiln.Kiln`.

| Key | Meaning | Default |
|---|---|---|
| `wheel.modifier.convert` | Key for the Convert wheel (`shift`, `command`, `control`, `option`) | `shift` |
| `wheel.modifier.tools` | Key for the Tools wheel | `command` |
| `wheel.modifier.actions` | Key for the File actions wheel | `control` |
| `output.folder` | Folder for results; absent means next to the original | absent |
| `output.collisionRule` | `suffix` (add a number) or `fail` (stop with a message) | `suffix` |
| `actions.moveDestination` | Where Move puts files; absent means ask the first time | absent |
| `general.showMenuBar` | Show the menu bar icon (open Kiln again to reach Settings when hidden) | `true` |
| `feedback.sound` | Play system sounds on hover, done and failed | `false` |
| `feedback.haptic` | Trackpad haptic tick when a wedge is highlighted | `true` |
| `results.reveal` | Show finished files in Finder | `false` |
| `float.behaviour` | `new` (a float per drop) or `replace` | `new` |
| `terminal.appPath` | Path to the app the Terminal action opens; absent means Terminal | absent |
| `conversion.options` | JSON of the Quality tab settings; absent means defaults | absent |
| `menu.hotkey.keyCode` | Virtual key code of the keyboard-menu shortcut | `49` (Space) |
| `menu.hotkey.modifiers` | Carbon modifier mask of that shortcut | `2048` (Option) |
| `menu.hotkey.label` | Text shown in Settings | `⌥Space` |

Reset everything with `defaults delete dev.kiln.Kiln`.

## Project layout

- `Sources/KilnCore`: the engine (no UI). Formats, registry, job runner, typed errors, naming, converters, tools, wheel geometry.
- `Tests/KilnCoreTests`: unit tests, using generated sample files only.
- `App`: the agent app. Drag watcher, wheel overlay, keyboard menu, file actions, settings.
- `PLAN.md`, `DECISIONS.md`, `SPIKE.md`, `COVERAGE.md`, `TESTING.md`: design record and test status.

## License

MIT. See [LICENSE](LICENSE).
