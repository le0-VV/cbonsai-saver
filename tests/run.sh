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

if grep -Fq 'CBCbonsaiPrintKey' "cbonsai saver/cbonsai saver/CBCommandLine."* "$VIEW_PATH" || grep -Fq 'CBCbonsaiHelpKey' "cbonsai saver/cbonsai saver/CBCommandLine."* "$VIEW_PATH"; then
  echo "Print and help should not be supported as screen saver settings." >&2
  exit 1
fi

if grep -Fq 'CBCbonsaiSave' "cbonsai saver/cbonsai saver/CBCommandLine."* "$VIEW_PATH" || grep -Fq 'CBCbonsaiLoad' "cbonsai saver/cbonsai saver/CBCommandLine."* "$VIEW_PATH"; then
  echo "Save and load files should not be supported as screen saver settings." >&2
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

if grep -Fq 'Print when finished' "$VIEW_PATH" || grep -Fq 'Show help' "$VIEW_PATH"; then
  echo "Print and help controls should not be present in the configuration sheet." >&2
  exit 1
fi

if grep -Fq 'Save file' "$VIEW_PATH" || grep -Fq 'Load file' "$VIEW_PATH"; then
  echo "Save and load file controls should not be present in the configuration sheet." >&2
  exit 1
fi

if ! grep -Fq 'NSTabView' "$VIEW_PATH" || ! grep -Fq 'advancedTab.label = @"Advanced"' "$VIEW_PATH"; then
  echo "Seed and verbose settings should live in an Advanced sub-pane." >&2
  exit 1
fi

if grep -Eq 'add(Label|Checkbox):@"[^"]*\(--' "$VIEW_PATH"; then
  echo "Visible setting labels should not expose command-line flags." >&2
  exit 1
fi

if grep -Fq 'baseEnabledButton' "$VIEW_PATH" || grep -Fq 'baseField' "$VIEW_PATH"; then
  echo "Pot style should be a pop-up menu, not a checkbox plus integer field." >&2
  exit 1
fi

if grep -Fq 'colorField' "$VIEW_PATH" || grep -Fq 'Tree colour (ANSI indices)' "$VIEW_PATH"; then
  echo "Tree colour should use ANSI colour controls, not a raw index text field." >&2
  exit 1
fi

for pot_option in \
  'addItemWithTitle:@"style 1"' \
  'addItemWithTitle:@"style 2"' \
  'addItemWithTitle:@"no pot"'
do
  if ! grep -Fq "$pot_option" "$VIEW_PATH"; then
    echo "Missing pot style menu option: $pot_option" >&2
    exit 1
  fi
done

for color_control in \
  darkLeafColorPopUpButton \
  darkWoodColorPopUpButton \
  lightLeafColorPopUpButton \
  lightWoodColorPopUpButton
do
  if ! grep -Fq "$color_control" "$VIEW_PATH"; then
    echo "Missing tree colour pop-up control: $color_control" >&2
    exit 1
  fi
done

if grep -Fq 'id="live"' "$MANUAL_PATH" || grep -Fq 'id="infinite"' "$MANUAL_PATH"; then
  echo "Live and infinite should not have setting manual anchors." >&2
  exit 1
fi

if grep -Fq 'id="print"' "$MANUAL_PATH" || grep -Fq 'id="help"' "$MANUAL_PATH"; then
  echo "Print and help should not have setting manual anchors." >&2
  exit 1
fi

if grep -Fq 'id="save"' "$MANUAL_PATH" || grep -Fq 'id="load"' "$MANUAL_PATH"; then
  echo "Save and load should not have setting manual anchors." >&2
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
  seed \
  verbose
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
Tree colour
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
Choose style 1, style 2, or no pot.
Character used for leaves.
Choose fixed ANSI colours.
Branch density.
How long branches keep growing.
Fixed random seed.
Print extra output.
Open manual.
EOF
