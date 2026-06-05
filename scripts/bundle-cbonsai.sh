#!/bin/sh
set -eu

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
  echo "TARGET_BUILD_DIR and UNLOCALIZED_RESOURCES_FOLDER_PATH are required." >&2
  exit 1
fi

resources_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
bundled_cbonsai="${resources_dir}/cbonsai"
lib_dir="${resources_dir}/lib"

if [ -n "${CBONSAI_BINARY_PATH:-}" ]; then
  cbonsai_source="${CBONSAI_BINARY_PATH}"
else
  cbonsai_source="$(command -v cbonsai || true)"
fi

if [ -z "$cbonsai_source" ] || [ ! -x "$cbonsai_source" ]; then
  echo "Unable to find cbonsai. Install cbonsai or set CBONSAI_BINARY_PATH." >&2
  exit 1
fi

mkdir -p "$resources_dir" "$lib_dir"
cp -f "$cbonsai_source" "$bundled_cbonsai"
chmod 755 "$bundled_cbonsai"

temp_root="${TEMP_FILES_DIR:-${TMPDIR:-/tmp}}"
queue="$(mktemp "${temp_root%/}/cbonsai-deps.queue.XXXXXX")"
seen="$(mktemp "${temp_root%/}/cbonsai-deps.seen.XXXXXX")"
trap 'rm -f "$queue" "$seen" "$queue.next"' EXIT

is_bundled_dependency()
{
  case "$1" in
    /usr/lib/*|/System/Library/*|@*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

add_dependencies()
{
  otool -L "$1" | awk 'NR > 1 { print $1 }' | while IFS= read -r dependency
  do
    if ! is_bundled_dependency "$dependency"; then
      continue
    fi

    if [ ! -f "$dependency" ]; then
      echo "Missing cbonsai dependency: $dependency" >&2
      exit 1
    fi

    if ! grep -Fxq "$dependency" "$seen"; then
      printf '%s\n' "$dependency" >> "$seen"
      printf '%s\n' "$dependency" >> "$queue"
    fi
  done
}

rewrite_dependency_paths()
{
  binary="$1"
  otool -L "$binary" | awk 'NR > 1 { print $1 }' | while IFS= read -r dependency
  do
    if is_bundled_dependency "$dependency"; then
      install_name_tool -change "$dependency" "@executable_path/lib/$(basename "$dependency")" "$binary"
    fi
  done
}

sign_binary()
{
  if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ] && command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none "$1"
  fi
}

add_dependencies "$cbonsai_source"
while [ -s "$queue" ]
do
  dependency="$(sed -n '1p' "$queue")"
  sed '1d' "$queue" > "$queue.next"
  mv "$queue.next" "$queue"

  bundled_dependency="${lib_dir}/$(basename "$dependency")"
  if [ ! -f "$bundled_dependency" ]; then
    cp -f "$dependency" "$bundled_dependency"
    chmod 755 "$bundled_dependency"
  fi

  add_dependencies "$dependency"
done

rewrite_dependency_paths "$bundled_cbonsai"
for dylib in "$lib_dir"/*.dylib
do
  if [ ! -e "$dylib" ]; then
    continue
  fi

  install_name_tool -id "@executable_path/lib/$(basename "$dylib")" "$dylib"
  rewrite_dependency_paths "$dylib"
  sign_binary "$dylib"
done

sign_binary "$bundled_cbonsai"
