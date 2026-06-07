#!/bin/sh
set -eu

PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <cbonsai saver.saver> <arch>" >&2
  exit 2
fi

saver="$1"
release_arch="$2"
binary="${saver}/Contents/Resources/cbonsai"

case "$release_arch" in
  arm64|x86_64)
    ;;
  *)
    echo "Unsupported release architecture: $release_arch" >&2
    exit 1
    ;;
esac

if [ ! -x "$binary" ]; then
  echo "Bundled cbonsai is missing or not executable: $binary" >&2
  exit 1
fi

actual_archs="$(lipo -archs "$binary" 2>/dev/null || true)"
if [ "$actual_archs" != "$release_arch" ]; then
  echo "Unexpected bundled cbonsai architecture: got '$actual_archs', expected '$release_arch'." >&2
  exit 1
fi

codesign --verify --strict --verbose=4 "$binary"

typescript="$(mktemp "${TMPDIR:-/tmp}/cbonsai-launch.XXXXXX")"
trap 'rm -f "$typescript"' EXIT

launcher='
binary="$1"
shift
"$binary" "$@" &
child_pid=$!
sleep 1
if kill -0 "$child_pid" 2>/dev/null; then
  kill -TERM "$child_pid" 2>/dev/null || true
  sleep 0.2
  if kill -0 "$child_pid" 2>/dev/null; then
    kill -KILL "$child_pid" 2>/dev/null || true
  fi
  wait "$child_pid" 2>/dev/null || true
  exit 0
fi
wait "$child_pid"
child_status=$?
echo "cbonsai launch command exited early with status ${child_status}." >&2
exit "$child_status"
'

if ! env -i \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  TERM=xterm-256color \
  TERMINFO_DIRS=/usr/share/terminfo \
  LANG=en_US.UTF-8 \
  LC_ALL=en_US.UTF-8 \
  /usr/bin/script -q "$typescript" /bin/sh -c "$launcher" cbonsai-launch "$binary" \
    --live \
    --infinite \
    --time=0.03 \
    --wait=3 \
    --base=1 \
    "--leaf=&" \
    --color=2,3,10,11 \
    --multiplier=5 \
    --life=32 >/dev/null
then
  sed -n '1,120p' "$typescript" >&2
  echo "cbonsai did not stay alive under PTY long enough to verify launch." >&2
  exit 1
fi

if [ ! -s "$typescript" ]; then
  echo "cbonsai launched under PTY but produced no terminal output." >&2
  exit 1
fi
