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
