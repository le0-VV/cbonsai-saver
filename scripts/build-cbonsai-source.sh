#!/bin/sh
set -eu

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

cd "$(dirname "$0")/.."

release_arch="${1:-$(uname -m)}"
deployment_target="${2:-}"
case "$release_arch" in
  arm64|x86_64)
    ;;
  *)
    echo "Unsupported cbonsai release architecture: $release_arch" >&2
    exit 1
    ;;
esac

case "$deployment_target" in
  ""|10.15)
    ;;
  *)
    echo "Unsupported cbonsai deployment target: $deployment_target" >&2
    exit 1
    ;;
esac

version="1.4.2"
archive_sha256="75cf844940e5ef825a74f2d5b1551fe81883551b600fecd00748c6aa325f5ab0"
url="https://gitlab.com/jallbrit/cbonsai/-/archive/v${version}/cbonsai-v${version}.tar.gz"
archive_root="build/upstream"
release_profile="$release_arch"
if [ -n "$deployment_target" ]; then
  release_profile="${release_profile}-macos${deployment_target}"
fi
build_root="${archive_root}/${release_profile}"
archive="${archive_root}/cbonsai-v${version}.tar.gz"
source_dir="${build_root}/cbonsai-v${version}"
binary="${source_dir}/cbonsai"

library_supports_arch()
{
  if [ ! -f "$1" ]; then
    return 1
  fi

  lipo -archs "$1" 2>/dev/null | tr ' ' '\n' | grep -Fx "$release_arch" >/dev/null
}

macho_minimum_macos()
{
  otool -l "$1" | awk '
    /LC_BUILD_VERSION/ { in_build = 1; in_version_min = 0; next }
    in_build && $1 == "minos" { print $2; exit }
    /LC_VERSION_MIN_MACOSX/ { in_version_min = 1; in_build = 0; next }
    in_version_min && $1 == "version" { print $2; exit }
  '
}

version_le()
{
  awk -v actual="$1" -v maximum="$2" '
    BEGIN {
      split(actual, a, ".")
      split(maximum, b, ".")
      for (part = 1; part <= 3; part++) {
        left = a[part] + 0
        right = b[part] + 0
        if (left < right) {
          exit 0
        }
        if (left > right) {
          exit 1
        }
      }
      exit 0
    }
  '
}

library_supports_deployment_target()
{
  if [ -z "$deployment_target" ]; then
    return 0
  fi

  minimum_macos="$(macho_minimum_macos "$1")"
  [ -n "$minimum_macos" ] && version_le "$minimum_macos" "$deployment_target"
}

add_pkg_config_dir()
{
  pkg_config_dir="$1"
  if [ ! -d "$pkg_config_dir" ]; then
    return
  fi

  libdir="$(PKG_CONFIG_PATH="$pkg_config_dir" pkg-config --variable=libdir ncursesw 2>/dev/null || true)"
  if [ -z "$libdir" ]; then
    return
  fi

  if ! library_supports_arch "${libdir}/libncursesw.6.dylib" || ! library_supports_arch "${libdir}/libpanelw.6.dylib"; then
    return
  fi

  if ! library_supports_deployment_target "${libdir}/libncursesw.6.dylib" || ! library_supports_deployment_target "${libdir}/libpanelw.6.dylib"; then
    return
  fi

  if [ -n "$PKG_CONFIG_PATH" ]; then
    PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:$pkg_config_dir"
  else
    PKG_CONFIG_PATH="$pkg_config_dir"
  fi
}

PKG_CONFIG_PATH=""
if [ -n "${CBONSAI_NCURSES_PKG_CONFIG_PATH:-}" ]; then
  case "$CBONSAI_NCURSES_PKG_CONFIG_PATH" in
    "$(pwd)"/build/release/deps/ncurses/*/lib/pkgconfig)
      ;;
    *)
      echo "Unsupported cbonsai ncurses pkg-config path: $CBONSAI_NCURSES_PKG_CONFIG_PATH" >&2
      exit 1
      ;;
  esac

  add_pkg_config_dir "$CBONSAI_NCURSES_PKG_CONFIG_PATH"
else
  case "$release_arch" in
    arm64)
      add_pkg_config_dir /opt/homebrew/opt/ncurses/lib/pkgconfig
      add_pkg_config_dir /usr/local/opt/ncurses/lib/pkgconfig
      ;;
    x86_64)
      add_pkg_config_dir /usr/local/opt/ncurses/lib/pkgconfig
      add_pkg_config_dir /opt/homebrew/opt/ncurses/lib/pkgconfig
      ;;
  esac
fi
export PKG_CONFIG_PATH

if [ -z "$PKG_CONFIG_PATH" ]; then
  echo "Unable to find $release_arch ncurses pkg-config metadata for deployment target '${deployment_target:-default}'." >&2
  exit 1
fi

if [ "$release_arch" = x86_64 ] && [ "$deployment_target" = 10.15 ]; then
  case "$PKG_CONFIG_PATH" in
    "$(pwd)"/build/release/deps/ncurses/x86_64-macos10.15/lib/pkgconfig)
      ;;
    *)
      echo "x86_64 macOS 10.15 releases must use source-built ncurses." >&2
      exit 1
      ;;
  esac
fi

mkdir -p "$archive_root" "$build_root"

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

compiler="${CC:-cc}"
build_cflags="${CFLAGS:-}"
build_ldflags="${LDFLAGS:-}"
if [ -n "$deployment_target" ]; then
  export MACOSX_DEPLOYMENT_TARGET="$deployment_target"
  build_cflags="-mmacosx-version-min=$deployment_target $build_cflags"
  build_ldflags="-mmacosx-version-min=$deployment_target $build_ldflags"
fi

make -C "$source_dir" WITH_BASH=0 CC="$compiler -arch $release_arch" CFLAGS="$build_cflags" LDFLAGS="$build_ldflags" cbonsai >&2

if [ ! -x "$binary" ]; then
  echo "Expected built cbonsai binary at $binary" >&2
  exit 1
fi

actual_archs="$(lipo -archs "$binary" 2>/dev/null || true)"
if [ "$actual_archs" != "$release_arch" ]; then
  echo "Built cbonsai has architecture '$actual_archs', expected '$release_arch'." >&2
  exit 1
fi

if [ -n "$deployment_target" ]; then
  minimum_macos="$(macho_minimum_macos "$binary")"
  if [ -z "$minimum_macos" ] || ! version_le "$minimum_macos" "$deployment_target"; then
    echo "Built cbonsai has minimum macOS '${minimum_macos:-unknown}', expected <= '$deployment_target'." >&2
    exit 1
  fi
fi

printf '%s\n' "$(pwd)/$binary"
