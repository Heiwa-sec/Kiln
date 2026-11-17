#!/bin/bash
# Builds the Release app and packs it for a GitHub release: dist/Kiln.zip and dist/Kiln.zip.sha256
# Usage: scripts/package.sh   then   gh release create vX.Y.Z dist/Kiln.zip dist/Kiln.zip.sha256
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Kiln.xcodeproj -scheme Kiln -configuration Release -derivedDataPath build build
APP=build/Build/Products/Release/Kiln.app
codesign --verify --deep --strict "$APP"
rm -rf dist && mkdir dist
ditto -c -k --keepParent "$APP" dist/Kiln.zip
(cd dist && shasum -a 256 Kiln.zip > Kiln.zip.sha256)
echo "Packed $(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist"): dist/Kiln.zip"
