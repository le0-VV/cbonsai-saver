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
COMMAND_LINE_PATH="cbonsai saver/cbonsai saver/CBCommandLine.m"
PROJECT_PATH="cbonsai saver/cbonsai saver.xcodeproj/project.pbxproj"
BUNDLE_SCRIPT_PATH="scripts/bundle-cbonsai.sh"
BUILD_SOURCE_SCRIPT_PATH="scripts/build-cbonsai-source.sh"
RELEASE_SCRIPT_PATH="scripts/package-release.sh"
CI_WORKFLOW_PATH=".github/workflows/ci.yml"
FORMULA_PATH="Formula/cbonsai-saver.rb"
HOMEBREW_DOC_PATH="HOMEBREW.md"
LICENSE_PATH="LICENSE"
SECURITY_PATH="SECURITY.md"
THIRD_PARTY_NOTICES_PATH="THIRD_PARTY_NOTICES.md"
if [ ! -f "$MANUAL_PATH" ]; then
  echo "Missing bundled cbonsai manual: $MANUAL_PATH" >&2
  exit 1
fi

sh -n "$BUNDLE_SCRIPT_PATH"
sh -n "$BUILD_SOURCE_SCRIPT_PATH"
sh -n "$RELEASE_SCRIPT_PATH"

if [ ! -f "$FORMULA_PATH" ]; then
  echo "Missing Homebrew formula: $FORMULA_PATH" >&2
  exit 1
fi

if [ ! -f "$HOMEBREW_DOC_PATH" ]; then
  echo "Missing Homebrew tap documentation: $HOMEBREW_DOC_PATH" >&2
  exit 1
fi

if [ ! -f "$LICENSE_PATH" ] || ! grep -Fq 'GNU GENERAL PUBLIC LICENSE' "$LICENSE_PATH"; then
  echo "Missing GPL license file." >&2
  exit 1
fi

if [ ! -f "$SECURITY_PATH" ] || ! grep -Fq 'Reporting a vulnerability' "$SECURITY_PATH"; then
  echo "Missing security policy." >&2
  exit 1
fi

if [ ! -f "$THIRD_PARTY_NOTICES_PATH" ] || ! grep -Fq 'GPL-3.0-or-later' "$THIRD_PARTY_NOTICES_PATH"; then
  echo "Missing third-party license notices." >&2
  exit 1
fi

if [ ! -f "$CI_WORKFLOW_PATH" ]; then
  echo "Missing GitHub Actions workflow: $CI_WORKFLOW_PATH" >&2
  exit 1
fi

if grep -Fq 'actions/checkout@v4' "$CI_WORKFLOW_PATH"; then
  echo "GitHub Actions checkout should be pinned to a commit SHA." >&2
  exit 1
fi

if ! grep -Fq 'actions/checkout@08eba0b27e820071cde6df949e0beb9ba4906955' "$CI_WORKFLOW_PATH"; then
  echo "GitHub Actions checkout pin is missing or changed." >&2
  exit 1
fi

if grep -Fq 'runs-on: macos-latest' "$CI_WORKFLOW_PATH"; then
  echo "GitHub Actions should pin a concrete macOS runner image." >&2
  exit 1
fi

if ! grep -Fq 'runs-on: macos-15' "$CI_WORKFLOW_PATH"; then
  echo "GitHub Actions should use the pinned macos-15 runner." >&2
  exit 1
fi

if grep -Fq 'brew install cbonsai' "$CI_WORKFLOW_PATH"; then
  echo "CI release builds should not install a Homebrew cbonsai binary." >&2
  exit 1
fi

if grep -Fq 'GITHUB_ENV' "$CI_WORKFLOW_PATH"; then
  echo "CI should not pass the cbonsai binary path through GITHUB_ENV." >&2
  exit 1
fi

if ! grep -Fq 'releases/download/1.1/cbonsai-saver-1.1.zip' "$FORMULA_PATH"; then
  echo "Homebrew formula should install the 1.1 release zip." >&2
  exit 1
fi

if grep -Fq 'sha256 "0000000000000000000000000000000000000000000000000000000000000000"' "$FORMULA_PATH"; then
  echo "Homebrew formula SHA-256 must be set before release." >&2
  exit 1
fi

for formula_text in \
  'class CbonsaiSaver < Formula' \
  'license all_of: ["GPL-3.0-or-later", "X11-distribute-modifications-variant"]' \
  'depends_on arch: :arm64' \
  '(prefix/"Screen Savers").install "cbonsai saver.saver"' \
  'assert_path_exists prefix/"Screen Savers/cbonsai saver.saver/Contents/Resources/cbonsai"'
do
  if ! grep -Fq "$formula_text" "$FORMULA_PATH"; then
    echo "Missing Homebrew formula text: $formula_text" >&2
    exit 1
  fi
done

if ! grep -Fq '75cf844940e5ef825a74f2d5b1551fe81883551b600fecd00748c6aa325f5ab0' "$BUILD_SOURCE_SCRIPT_PATH"; then
  echo "Verified cbonsai source SHA-256 is missing." >&2
  exit 1
fi

for source_hardening_text in \
  'PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"' \
  'PKG_CONFIG_PATH=""' \
  '/opt/homebrew/opt/ncurses/lib/pkgconfig' \
  'cbonsai source archive contains unexpected paths.' \
  'cbonsai source archive contains unsafe paths.' \
  'make -C "$source_dir" WITH_BASH=0 cbonsai'
do
  if ! grep -Fq "$source_hardening_text" "$BUILD_SOURCE_SCRIPT_PATH"; then
    echo "Missing verified-source hardening text: $source_hardening_text" >&2
    exit 1
  fi
done

for bundle_hardening_text in \
  'Refusing to bundle cbonsai from a non-absolute path' \
  'Refusing to bundle cbonsai from an unsupported location' \
  'Refusing to bundle unexpected cbonsai binary name' \
  'Unsupported cbonsai dependency path' \
  'codesign --force --sign - --timestamp=none "$1"'
do
  if ! grep -Fq "$bundle_hardening_text" "$BUNDLE_SCRIPT_PATH"; then
    echo "Missing bundle hardening text: $bundle_hardening_text" >&2
    exit 1
  fi
done

for release_hardening_text in \
  'Invalid release version' \
  'CBONSAI_BINARY_PATH="$(./scripts/build-cbonsai-source.sh)"' \
  'Unexpected verified cbonsai binary path'
do
  if ! grep -Fq "$release_hardening_text" "$RELEASE_SCRIPT_PATH"; then
    echo "Missing release hardening text: $release_hardening_text" >&2
    exit 1
  fi
done

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

if ! grep -Fq 'return @"/usr/bin:/bin:/usr/sbin:/sbin";' "$COMMAND_LINE_PATH"; then
  echo "Runtime cbonsai PATH should only include system directories." >&2
  exit 1
fi

if grep -Fq 'execve("/bin/sh"' "$VIEW_PATH" || grep -Fq 'createShellArgv' "$VIEW_PATH" || grep -Fq 'CBONSAI_EXECUTABLE' "$VIEW_PATH"; then
  echo "Screen saver should launch bundled cbonsai directly, not through a shell." >&2
  exit 1
fi

if ! grep -Fq 'execve(processArgv[0], processArgv, processEnvironment)' "$VIEW_PATH"; then
  echo "Screen saver should exec the bundled cbonsai argv directly." >&2
  exit 1
fi

if ! grep -Fq 'CBMaximumTerminalColumns = 220' "$VIEW_PATH" || ! grep -Fq 'CBMaximumCSIParameterLength = 64' "$VIEW_PATH"; then
  echo "Terminal parser and grid size should be bounded." >&2
  exit 1
fi

if grep -Fq '[self setAnimationTimeInterval:1.0 / 30.0]' "$VIEW_PATH"; then
  echo "Screen saver should not keep a 30 Hz idle animation timer." >&2
  exit 1
fi

for performance_text in \
  'CBIdleAnimationTimeInterval = 1.0' \
  'CBTerminalDataFlushInterval = 1.0 / 30.0' \
  'enqueueTerminalData:' \
  'flushPendingTerminalDataAndDisplay' \
  'terminalTextAttributesCache' \
  'cellsForRow:' \
  'contentMetrics'
do
  if ! grep -Fq "$performance_text" "$VIEW_PATH"; then
    echo "Missing performance hardening text: $performance_text" >&2
    exit 1
  fi
done

for multi_display_seed_text in \
  'CBCbonsaiArgumentsFromOptionsWithAutomaticSeed' \
  'CBAutomaticCbonsaiSeedForScreen' \
  'CBDisplayIdentifierForScreen' \
  '@"NSScreenNumber"' \
  'self.window.screen ?: NSScreen.mainScreen'
do
  if ! grep -Fq "$multi_display_seed_text" "$VIEW_PATH" "$COMMAND_LINE_PATH" "cbonsai saver/cbonsai saver/CBCommandLine.h" tests/CBCommandLineTests.m; then
    echo "Missing multi-display automatic seed text: $multi_display_seed_text" >&2
    exit 1
  fi
done

if grep -Fq 'CBCbonsaiArgumentsFromOptions(self.configuredCbonsaiOptions)' "$VIEW_PATH"; then
  echo "Screen saver should pass a display-salted automatic seed when launching cbonsai." >&2
  exit 1
fi

if awk '
  /- \(void\)drawRect:/ { in_draw = 1 }
  /- \(void\)animateOneFrame/ { in_draw = 0 }
  in_draw && /updateTerminalGeometry/ { found = 1 }
  END { exit found ? 0 : 1 }
' "$VIEW_PATH"; then
  echo "drawRect should not recompute terminal geometry." >&2
  exit 1
fi

if grep -Fq '[availableData copy]' "$VIEW_PATH" || grep -Fq '[self.pendingTerminalData copy]' "$VIEW_PATH"; then
  echo "PTY batching should not copy coalesced data before parsing." >&2
  exit 1
fi

if ! grep -Fq 'NSData *data = availableData;' "$VIEW_PATH" || ! grep -Fq 'self.pendingTerminalData = [NSMutableData dataWithCapacity:data.length];' "$VIEW_PATH"; then
  echo "PTY batching should pass read buffers through and swap pending buffers." >&2
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

for bounded_control in \
  'self.waitStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 90, y - 4, 20, 28) min:0.01 max:600.0 increment:0.25]' \
  'self.multiplierStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 90, y - 4, 20, 28) min:1.0 max:20.0 increment:1.0]' \
  'self.lifeStepper = [self addStepperToView:documentView frame:NSMakeRect(fieldX + 90, y - 4, 20, 28) min:1.0 max:200.0 increment:1.0]'
do
  if ! grep -Fq "$bounded_control" "$VIEW_PATH"; then
    echo "Missing bounded configuration control: $bounded_control" >&2
    exit 1
  fi
done

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
