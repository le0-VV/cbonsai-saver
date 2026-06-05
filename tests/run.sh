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

MANUAL_PATH="cbonsai saver/cbonsai saver/cbonsai-manual.html"
VIEW_PATH="cbonsai saver/cbonsai saver/cbonsai_saverView.m"
if [ ! -f "$MANUAL_PATH" ]; then
  echo "Missing bundled cbonsai manual: $MANUAL_PATH" >&2
  exit 1
fi

for anchor in \
  executable \
  font-size \
  screensaver \
  live \
  infinite \
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
Command used to launch cbonsai.
Terminal font size.
Continuously redraw trees.
Animate growth.
Keep cbonsai running.
Growth delay in seconds.
Delay after each tree.
Text rendered with the tree.
Pass --base when enabled.
Leaf character list.
ANSI color list.
Branch density.
Branch lifetime.
Print final tree.
Fixed random seed.
Save tree state file.
Load tree state file.
Print extra output.
Show cbonsai help and exit.
Open manual.
EOF
