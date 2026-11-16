# TESTING: manual checklist

Run this by hand. The wheel, keyboard and file-action behavior has only been exercised in short scripted runs. Tick or note each line. Anything not listed here is untested.

Use copies of throwaway files. Kiln writes next to the original, so work in a scratch folder.

## 0. Setup
- [ ] `swift test` passes (100 tests at last count).
- [ ] Build and open the app as in README. A flame icon appears in the menu bar and no Dock icon appears.
- [ ] Quit any other app that also reacts to drags with a modifier, so two wheels don't open.
- [ ] Make a scratch folder with: a PNG, a JPG with GPS data (a phone photo copy), a two-page PDF, a password-protected PDF, a WAV or MP3, a short MP4 or MOV, a TXT, a folder with two files, and a text file renamed to `broken.png`.

## 1. Wheel opens (the core feature)
- [ ] Drag the PNG, then hold Shift. A wheel opens under the cursor and stays where it opened.
- [ ] Start the drag first and press Shift after: still opens. Press Shift first, then drag: note whether it opens (it should).
- [ ] Release Shift while still dragging: the wheel stays open.
- [ ] While dragging, press Command, then Control, then Shift: the wheel switches each time.
- [ ] Open it near each screen edge, the menu bar and the Dock: the wheel stays on screen.
- [ ] With two displays, open it on the second one.
- [ ] Open it while a full-screen app is in front.
- [ ] Hover a group: the outer ring opens. Move across the wheel to a format on the far side: the ring stays open (it only switches after you rest on another group for a moment).
- [ ] Greyed-out wedges (for example WebP) don't highlight and refuse the drop (the cursor shows no-drop).
- [ ] Drag a file Kiln can't convert (for example a `.xyz`): the wheel opens with an empty ring and a drop does nothing.

## 2. Drop and results
- [ ] Drop the PNG on JPG: `name.jpg` appears next to it, the PNG is untouched, and a small strip shows the result with a Show button.
- [ ] Drop on the same target again: `name 2.jpg`.
- [ ] Open Settings, set "If the name is taken" to "Stop and tell me", repeat: a message appears and no file is written.
- [ ] Set a results folder in Settings: results go there.
- [ ] Repeat the drop on a wedge 10 times in a row. The spike lost one drop out of three once; count failures.
- [ ] Release over the empty centre or outside the wheel: nothing is converted and the wheel closes within about half a second.
- [ ] Escape mid-drag: with Accessibility granted to Kiln it should close the wheel. Without it, nothing happens (expected). Note which.

## 3. Conversions (spot-check each family)
For each row, check the output opens in the right app and looks right.
- [ ] PNG to JPG, TIFF, HEIC, BMP, GIF, PDF.
- [ ] PDF to PNG: a folder `name pages` with one 300-DPI PNG per page. PDF to TXT and MD.
- [ ] TXT to RTF, DOCX, HTML. DOCX back to TXT.
- [ ] WAV or MP3 to M4A, AIFF, FLAC. Listen to one.
- [ ] MP4 or MOV to MP4, M4A (audio), GIF. The GIF should be 10 s or shorter.
- [ ] Folder to ZIP and TAR; extract the ZIP. A single file to GZIP.
- [ ] Drop several PNGs at once on one format: each is converted. Mix a PNG and a TXT: the TXT is reported as skipped.
- [ ] Drop a folder on the Convert wheel: only archive targets are enabled.

## 4. Errors (the six required cases, plus one)
- [ ] Unsupported pair: PDF to DOCX is greyed out. If you can force one, the message names both formats.
- [ ] Corrupt input: drop `broken.png` on JPG. Message says it can't be read.
- [ ] Name collision: section 2.
- [ ] Disk full: convert a large video onto a nearly full disk or small disk image. The message says the disk is full and no partial file is left. (Only simulated in unit tests.)
- [ ] Cancel mid-job: start a long video or GIF conversion and press Cancel. The partial output disappears.
- [ ] Encrypted PDF: drop the protected PDF on TXT. Message asks you to remove the password.
- [ ] Unsafe archive: unzip a zip containing `../` paths (make one with a hex editor or script). Kiln refuses and writes nothing.

## 5. Tools (Command wheel)
- [ ] Compress on a JPG: smaller file named `name compressed.jpg`. Greyed out for a PNG.
- [ ] Resize: half the pixels. Rotate: 90 degrees clockwise, correct way up.
- [ ] Strip metadata on the GPS JPG: check with Preview's Inspector or `mdls` that location data is gone.
- [ ] Merge: drop two PDFs together: one `... merged.pdf`. With one PDF it is greyed out.
- [ ] Split: one PDF per page in `name split`.
- [ ] Compress video and Extract audio on an MP4.

## 6. File actions (Control wheel)
- [ ] Copy: paste the file in Finder.
- [ ] Copy Path: paste in Terminal and in a text editor; try a file with spaces, an apostrophe and a `;` in the name. Nothing should run.
- [ ] Move: asks for a folder the first time, then remembers it. Name collisions get a number.
- [ ] Terminal: opens at the file's folder (or the folder itself).
- [ ] Float: an always-on-top preview appears; drag it back out into Finder; Escape or double-click closes it.
- [ ] AirDrop: the system AirDrop sheet appears.
- [ ] Actions on a folder and on a mixed selection.

## 7. Keyboard menu
- [ ] Select a file in Finder, press Option+Space. A menu opens. The first time macOS asks to let Kiln control Finder: allow it.
- [ ] Arrows move (skipping greyed rows), Return applies, Escape closes. Clicking elsewhere closes it.
- [ ] Command and Control switch wheels.
- [ ] Press the shortcut with nothing selected, or with another app in front: a short message appears.
- [ ] Deny the Automation permission and press again: the message says where to allow it.

## 8. Settings
- [ ] Change a wheel's key to Option: dragging with Option opens that wheel. Picking a key another wheel uses swaps the two.
- [ ] Record a new keyboard-menu shortcut. Use one with no modifier: it is refused. Use one taken by another app: a message says so.
- [ ] Open at login on and off. (Needs a signed build to be reliable.)
- [ ] Choose and reset the results folder and the Move folder.

- [ ] Quality tab, Images: lower JPG quality and convert a photo: the file is clearly smaller. Turn off "Keep metadata": the result has no location (check in Preview's Inspector). Set a largest side: the result is that size, and a smaller image is not enlarged.
- [ ] Quality tab: set GIF to 5 fps and 5 s, convert a clip: the GIF is shorter and smaller. Set PDF to 150 DPI: page images are smaller. Set AAC to 32 kbps: an M4A is smaller.
- [ ] Each Quality area's "Restore defaults" button works and changes only that area.
- [ ] Compatibility tab: a check mark means it really works (spot-check three), "ff" pairs fail with the ffmpeg message when ffmpeg is not installed.
- [ ] General: turn the menu bar icon off. It disappears. Open Kiln again from Finder or Launchpad: Settings opens. Turn it back on.
- [ ] Sound on: a tick when a wedge highlights, a chime when a job finishes, a thud on failure. Haptics: a tap on the trackpad as wedges highlight.
- [ ] "Show finished files in Finder" reveals results when a job ends.
- [ ] Float: "Replace the current float" closes the old one when a new one opens. Terminal app: choose iTerm or another app; the Terminal action opens it.
- [ ] About: "Reset all settings" asks first, then returns everything to defaults (including the shortcut).

## 9. Permissions and signing
- [ ] After rebuilding, check whether macOS forgot Automation or Accessibility (ad-hoc signing changes the identity). Note it.
- [ ] Look at System Settings > Privacy: Kiln should hold only Automation, and Accessibility if you granted it. No Input Monitoring or Screen Recording.

## 10. Housekeeping
- [ ] Only one `Kiln.app` is registered (delete build copies).
- [ ] `defaults delete dev.kiln.Kiln` resets every setting.
- [ ] Look at the look: flat dark surface, one green accent, no gradients, no emoji. Say what feels wrong.
