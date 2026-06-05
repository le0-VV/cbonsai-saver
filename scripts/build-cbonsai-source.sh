#!/bin/sh
set -eu

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

PKG_CONFIG_PATH=""
for pkg_config_dir in /opt/homebrew/opt/ncurses/lib/pkgconfig /usr/local/opt/ncurses/lib/pkgconfig
do
  if [ -d "$pkg_config_dir" ]; then
    if [ -n "$PKG_CONFIG_PATH" ]; then
      PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:$pkg_config_dir"
    else
      PKG_CONFIG_PATH="$pkg_config_dir"
    fi
  fi
done
export PKG_CONFIG_PATH

cd "$(dirname "$0")/.."

version="1.4.2"
archive_sha256="75cf844940e5ef825a74f2d5b1551fe81883551b600fecd00748c6aa325f5ab0"
url="https://gitlab.com/jallbrit/cbonsai/-/archive/v${version}/cbonsai-v${version}.tar.gz"
build_root="build/upstream"
archive="${build_root}/cbonsai-v${version}.tar.gz"
source_dir="${build_root}/cbonsai-v${version}"
binary="${source_dir}/cbonsai"

mkdir -p "$build_root"

if [ ! -f "$archive" ]; then
  temporary_archive="${archive}.$$"
  trap 'rm -f "$temporary_archive"' EXIT
  curl -fsSL "$url" -o "$temporary_archive"
  mv "$temporary_archive" "$archive"
fi

actual_sha256="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
if [ "$actual_sha256" != "$archive_sha256" ]; then
  echo "cbonsai source checksum mismatch: got $actual_sha256, expected $archive_sha256" >&2
  exit 1
fi

if ! tar -tzf "$archive" | awk -v root="cbonsai-v${version}/" -v rootdir="cbonsai-v${version}" '
  $0 == rootdir || index($0, root) == 1 { next }
  { bad = 1 }
  END { exit bad ? 1 : 0 }
'; then
  echo "cbonsai source archive contains unexpected paths." >&2
  exit 1
fi

if tar -tzf "$archive" | awk '
  substr($0, 1, 1) == "/" || $0 ~ /(^|\/)\.\.(\/|$)/ { bad = 1 }
  END { exit bad ? 0 : 1 }
'; then
  echo "cbonsai source archive contains unsafe paths." >&2
  exit 1
fi

rm -rf "$source_dir"
tar -xzf "$archive" -C "$build_root"

if [ ! -d "$source_dir" ]; then
  echo "Expected cbonsai source directory at $source_dir" >&2
  exit 1
fi

make -C "$source_dir" WITH_BASH=0 cbonsai >&2

if [ ! -x "$binary" ]; then
  echo "Expected built cbonsai binary at $binary" >&2
  exit 1
fi

printf '%s\n' "$(pwd)/$binary"
