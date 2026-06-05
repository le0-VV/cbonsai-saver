#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

BUILD_DIR="${TMPDIR:-/tmp}/cbonsai-saver-tests"
mkdir -p "$BUILD_DIR"

clang \
  -fobjc-arc \
  -framework Foundation \
  -I"cbonsai saver/cbonsai saver" \
  "cbonsai saver/cbonsai saver/CBCommandLine.m" \
  tests/CBCommandLineTests.m \
  -o "$BUILD_DIR/CBCommandLineTests"

"$BUILD_DIR/CBCommandLineTests"

clang \
  -fobjc-arc \
  -framework Foundation \
  -I"cbonsai saver/cbonsai saver" \
  "cbonsai saver/cbonsai saver/CBTerminalGeometry.m" \
  tests/CBTerminalGeometryTests.m \
  -o "$BUILD_DIR/CBTerminalGeometryTests"

"$BUILD_DIR/CBTerminalGeometryTests"

MANUAL_PATH="cbonsai saver/cbonsai saver/cbonsai-manual.html"
VIEW_PATH="cbonsai saver/cbonsai saver/cbonsai_saverView.m"
PROJECT_PATH="cbonsai saver/cbonsai saver.xcodeproj/project.pbxproj"
BUNDLE_SCRIPT_PATH="scripts/bundle-cbonsai.sh"
if [ ! -f "$MANUAL_PATH" ]; then
  echo "Missing bundled cbonsai manual: $MANUAL_PATH" >&2
  exit 1
fi

sh -n "$BUNDLE_SCRIPT_PATH"

if grep -Fq 'addLabel:@"Executable"' "$VIEW_PATH"; then
  echo "Executable setting should not be present in the configuration sheet." >&2
  exit 1
fi

if grep -Fq 'addLabel:@"Font size"' "$VIEW_PATH" || grep -Fq 'CBFontSizeKey' "$VIEW_PATH" || grep -Fq 'fontSizeField' "$VIEW_PATH"; then
  echo "Font size should be automatic, not exposed as a setting." >&2
  exit 1
fi

if grep -Fq 'CBDefaultExecutablePath' "cbonsai saver/cbonsai saver/CBCommandLine."*; then
  echo "Executable path defaults should not be exposed." >&2
  exit 1
fi

if grep -Fq 'CBCbonsaiScreensaverKey' "cbonsai saver/cbonsai saver/CBCommandLine."* "$VIEW_PATH"; then
  echo "Screensaver mode should not be exposed." >&2
  exit 1
fi

if grep -Fq 'CBCbonsaiLiveKey' "cbonsai saver/cbonsai saver/CBCommandLine."* "$VIEW_PATH" || grep -Fq 'CBCbonsaiInfiniteKey' "cbonsai saver/cbonsai saver/CBCommandLine."* "$VIEW_PATH"; then
  echo "Live and infinite modes should always be enabled, not exposed as settings." >&2
  exit 1
fi

if grep -Fq 'Live (--live)' "$VIEW_PATH" || grep -Fq 'Infinite (--infinite)' "$VIEW_PATH" || grep -Fq 'addSectionTitle:@"Mode"' "$VIEW_PATH"; then
  echo "Live and infinite controls should not be present in the configuration sheet." >&2
  exit 1
fi

if grep -Eq 'add(Label|Checkbox):@"[^"]*\(--' "$VIEW_PATH"; then
  echo "Visible setting labels should not expose command-line flags." >&2
  exit 1
fi

if grep -Fq 'id="live"' "$MANUAL_PATH" || grep -Fq 'id="infinite"' "$MANUAL_PATH"; then
  echo "Live and infinite should not have setting manual anchors." >&2
  exit 1
fi

if ! grep -Fq "Bundle cbonsai" "$PROJECT_PATH" || ! grep -Fq "bundle-cbonsai.sh" "$PROJECT_PATH"; then
  echo "Xcode target should bundle cbonsai during build." >&2
  exit 1
fi

for anchor in \
  time \
  wait \
  message \
  base \
  leaf \
  color \
  multiplier \
  life \
  print \
  seed \
  save \
  load \
  verbose \
  help
do
  if ! grep -q "id=\"$anchor\"" "$MANUAL_PATH"; then
    echo "Missing cbonsai manual anchor: $anchor" >&2
    exit 1
  fi
done

if grep -Fq 'id="font-size"' "$MANUAL_PATH"; then
  echo "Font size should not have a setting manual anchor." >&2
  exit 1
fi

while IFS= read -r label
do
  if [ -z "$label" ]; then
    continue
  fi

  if ! grep -Fq "$label" "$VIEW_PATH"; then
    echo "Missing renamed setting label: $label" >&2
    exit 1
  fi
done <<'EOF'
Tree growth interval (seconds)
Growth restart wait time (seconds)
Pot style
Leaf character
Tree colour (ANSI indices)
Tree density
Branch lifetime duration (steps)
EOF

while IFS= read -r tooltip
do
  if [ -z "$tooltip" ]; then
    continue
  fi

  if ! grep -Fq "@\"$tooltip\"" "$VIEW_PATH"; then
    echo "Missing concise setting tooltip: $tooltip" >&2
    exit 1
  fi
done <<'EOF'
Delay between growth steps.
Delay before restarting growth.
Text rendered with the tree.
Styles 1 or 2, or use 0 for no pot.
Character used for leaves.
ANSI colour indices.
Branch density.
How long branches keep growing.
Print final tree.
Fixed random seed.
Save tree state file.
Load tree state file.
Print extra output.
Show cbonsai help and exit.
Open manual.
EOF
