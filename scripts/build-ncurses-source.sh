#!/bin/sh
set -eu

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

cd "$(dirname "$0")/.."

release_arch="${1:-x86_64}"
deployment_target="${2:-10.15}"

case "$release_arch" in
  x86_64)
    ;;
  *)
    echo "Source-built ncurses is only supported for x86_64 releases." >&2
    exit 1
    ;;
esac

case "$deployment_target" in
  10.15)
    ;;
  *)
    echo "Unsupported ncurses deployment target: $deployment_target" >&2
    exit 1
    ;;
esac

version="6.6"
archive_sha256="355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11"
url="https://ftpmirror.gnu.org/gnu/ncurses/ncurses-${version}.tar.gz"
archive_root="build/upstream/ncurses"
build_root="${archive_root}/${release_arch}-macos${deployment_target}"
archive="${archive_root}/ncurses-${version}.tar.gz"
source_dir="${build_root}/ncurses-${version}"
prefix="$(pwd)/build/release/deps/ncurses/${release_arch}-macos${deployment_target}"

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

verify_macho_file()
{
  actual_archs="$(lipo -archs "$1" 2>/dev/null || true)"
  if [ "$actual_archs" != "$release_arch" ]; then
    echo "Unexpected architecture for $1: got '$actual_archs', expected '$release_arch'." >&2
    exit 1
  fi

  minimum_macos="$(macho_minimum_macos "$1")"
  if [ -z "$minimum_macos" ] || ! version_le "$minimum_macos" "$deployment_target"; then
    echo "Unexpected minimum macOS for $1: got '${minimum_macos:-unknown}', expected <= '$deployment_target'." >&2
    exit 1
  fi
}

mkdir -p "$archive_root" "$build_root"

if [ ! -f "$archive" ]; then
  temporary_archive="${archive}.$$"
  trap 'rm -f "$temporary_archive"' EXIT
  curl -fsSL "$url" -o "$temporary_archive"
  mv "$temporary_archive" "$archive"
fi

actual_sha256="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
if [ "$actual_sha256" != "$archive_sha256" ]; then
  echo "ncurses source checksum mismatch: got $actual_sha256, expected $archive_sha256" >&2
  exit 1
fi

if ! tar -tzf "$archive" | awk -v root="ncurses-${version}/" -v rootdir="ncurses-${version}" '
  $0 == rootdir || index($0, root) == 1 { next }
  { bad = 1 }
  END { exit bad ? 1 : 0 }
'; then
  echo "ncurses source archive contains unexpected paths." >&2
  exit 1
fi

if tar -tzf "$archive" | awk '
  substr($0, 1, 1) == "/" || $0 ~ /(^|\/)\.\.(\/|$)/ { bad = 1 }
  END { exit bad ? 0 : 1 }
'; then
  echo "ncurses source archive contains unsafe paths." >&2
  exit 1
fi

rm -rf "$source_dir" "$prefix"
tar -xzf "$archive" -C "$build_root"

if [ ! -d "$source_dir" ]; then
  echo "Expected ncurses source directory at $source_dir" >&2
  exit 1
fi

compiler="${CC:-cc}"
make_jobs="$(sysctl -n hw.ncpu 2>/dev/null || printf '2')"

export MACOSX_DEPLOYMENT_TARGET="$deployment_target"
export CC="$compiler -arch $release_arch"
export CFLAGS="-mmacosx-version-min=$deployment_target ${CFLAGS:-}"
export LDFLAGS="-arch $release_arch -mmacosx-version-min=$deployment_target ${LDFLAGS:-}"

(
  cd "$source_dir"
  ./configure \
    --prefix="$prefix" \
    --enable-pc-files \
    --with-pkg-config-libdir="${prefix}/lib/pkgconfig" \
    --enable-sigwinch \
    --enable-symlinks \
    --enable-widec \
    --with-shared \
    --with-gpm=no \
    --without-ada \
    --without-cxx \
    --without-cxx-binding
  make -j"$make_jobs"
  make install
)

for dylib in \
  "${prefix}/lib/libncursesw.6.dylib" \
  "${prefix}/lib/libpanelw.6.dylib"
do
  if [ ! -f "$dylib" ]; then
    echo "Missing built ncurses dylib: $dylib" >&2
    exit 1
  fi

  verify_macho_file "$dylib"
done

printf '%s\n' "$prefix"
