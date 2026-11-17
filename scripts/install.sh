#!/bin/bash
# Installs Kiln: downloads the latest release, checks it, copies Kiln.app to Applications and opens it.
#   curl -fsSL https://raw.githubusercontent.com/Heiwa-sec/Kiln/main/scripts/install.sh | bash
# KILN_BASE_URL overrides where Kiln.zip and Kiln.zip.sha256 are fetched from (used for testing).
set -euo pipefail
BASE=${KILN_BASE_URL:-https://github.com/Heiwa-sec/Kiln/releases/latest/download}

[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || { echo "Kiln needs a Mac with Apple silicon." >&2; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ] || { echo "Kiln needs macOS 13 or later." >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo "Downloading Kiln..."
curl -fsSL "$BASE/Kiln.zip" -o "$tmp/Kiln.zip"
curl -fsSL "$BASE/Kiln.zip.sha256" -o "$tmp/Kiln.zip.sha256"
(cd "$tmp" && shasum -a 256 -c Kiln.zip.sha256 >/dev/null) || { echo "Download is corrupt (checksum mismatch). Nothing installed." >&2; exit 1; }
ditto -x -k "$tmp/Kiln.zip" "$tmp/x"
codesign --verify --deep --strict "$tmp/x/Kiln.app" || { echo "App signature is broken. Nothing installed." >&2; exit 1; }

DEST=/Applications
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
pkill -x Kiln 2>/dev/null && sleep 1 || true   # a running copy would keep the old build alive
rm -rf "$DEST/Kiln.app"
ditto "$tmp/x/Kiln.app" "$DEST/Kiln.app"
xattr -dr com.apple.quarantine "$DEST/Kiln.app" 2>/dev/null || true
open "$DEST/Kiln.app"
echo "Installed Kiln in $DEST and opened it. Look for its icon in the menu bar."
