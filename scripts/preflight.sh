#!/bin/bash
# Run before every release: scripts/preflight.sh [--fast]   (--fast skips the tests and the Release build)
# Prints PASS / FAIL per check and exits 1 if any FAIL. Changes no tracked file.
# Optional: KILN_FORBIDDEN='word1|word2' scripts/preflight.sh also checks that no tracked file, commit, author or the built binary contains
# those words. They are passed in, never written into the repo.
cd "$(dirname "$0")/.." || exit 2
FAILS=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS  $1"; else echo "FAIL  $1"; FAILS=$((FAILS+1)); fi; }

echo "== Secrets and identity"
check "no secret-like text or key/certificate/database files in any commit" "scripts/scan-secrets.sh"
[ -n "$KILN_FORBIDDEN" ] && check "no forbidden words in tracked files, history or authors" \
  "! git ls-files -z | xargs -0 grep -qIiE '$KILN_FORBIDDEN' && ! git log --all -p --format='%an %ae %cn %ce %s%n%b' | grep -qiE '$KILN_FORBIDDEN'"

echo "== Network and dependencies"
check "no URLs and no network APIs in the sources" \
  "! grep -rE 'https?://|URLSession|URLRequest|NWConnection|WKWebView' Sources App --include='*.swift'"
check "no third-party packages" "! grep -q '\\.package(' Package.swift && [ ! -f Podfile ]"

echo "== Code"
check "no try!, as!, fatalError, print or NSLog in the sources" "! grep -rnE 'try!|as!|fatalError|\\bprint\\(|NSLog' Sources App --include='*.swift'"
check "every subprocess is started with an argument array (no shell)" "! grep -rnE '/bin/(ba|z)?sh|\"(ba|z)?sh\"' Sources App --include='*.swift'"
check "entitlements are only apple-events" "[ \"\$(grep -c '<key>' App/Kiln.entitlements)\" = 1 ] && grep -q automation.apple-events App/Kiln.entitlements"

if [ "$1" != "--fast" ]; then
  echo "== Tests and Release build"
  check "unit tests pass" "swift test"
  APP=build/Build/Products/Release/Kiln.app
  check "Release build succeeds" "xcodegen generate && xcodebuild -project Kiln.xcodeproj -scheme Kiln -configuration Release -derivedDataPath build build"
  check "signature valid, hardened runtime on, no debugger entitlement" \
    "codesign --verify --deep --strict $APP && codesign -dv $APP 2>&1 | grep -q 'flags=.*runtime' && ! codesign -d --entitlements - $APP 2>&1 | grep -q get-task-allow"
  check "usage string for Apple events is in Info.plist" "plutil -extract NSAppleEventsUsageDescription raw $APP/Contents/Info.plist"
  check "binary has no absolute user paths" "! strings -a $APP/Contents/MacOS/Kiln | grep -qE '/Users/[A-Za-z]'"
  [ -n "$KILN_FORBIDDEN" ] && check "binary contains no forbidden words" "! strings -a $APP/Contents/MacOS/Kiln | grep -qiE '$KILN_FORBIDDEN'"
fi

echo
if [ $FAILS -eq 0 ]; then echo "PREFLIGHT PASSED"; else echo "PREFLIGHT: $FAILS item(s) to fix before you release"; exit 1; fi
