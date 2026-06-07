#!/bin/sh
set -eu

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

cd "$(dirname "$0")/.."

version="${1:-1.1.1}"
release_arch="${2:-arm64}"
repo_root="$(pwd)"
project="cbonsai saver/cbonsai saver.xcodeproj"
scheme="cbonsai saver"
configuration="Release"

case "$release_arch" in
  arm64)
    release_profile="arm64"
    deployment_target=""
    archive_name="cbonsai-saver-${version}.zip"
    ;;
  x86_64)
    deployment_target="10.15"
    release_profile="x86_64-macos${deployment_target}"
    archive_name="cbonsai-saver-${version}-${release_profile}.zip"
    ;;
  *)
    echo "Unsupported release architecture: $release_arch" >&2
    exit 1
    ;;
esac

build_root="build/release/${release_profile}"
derived_data="${build_root}/DerivedData"
artifacts_dir="build/release/artifacts"
product_dir="${derived_data}/Build/Products/${configuration}"
product="${product_dir}/cbonsai saver.saver"
staging_dir="${build_root}/staging/cbonsai-saver-${version}"
archive="${repo_root}/${artifacts_dir}/${archive_name}"

case "$version" in
  ""|.*|-*|*..*|*[!0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._-]*)
    echo "Invalid release version: $version" >&2
    exit 1
    ;;
esac

mkdir -p "$artifacts_dir"

verify_macho_architecture()
{
  actual_archs="$(lipo -archs "$1" 2>/dev/null || true)"
  if [ "$actual_archs" != "$release_arch" ]; then
    echo "Unexpected architecture for $1: got '$actual_archs', expected '$release_arch'." >&2
    exit 1
  fi
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

verify_macho_deployment_target()
{
  if [ -z "$deployment_target" ]; then
    return
  fi

  minimum_macos="$(macho_minimum_macos "$1")"
  if [ -z "$minimum_macos" ] || ! version_le "$minimum_macos" "$deployment_target"; then
    echo "Unexpected minimum macOS for $1: got '${minimum_macos:-unknown}', expected <= '$deployment_target'." >&2
    exit 1
  fi
}

verify_macho_file()
{
  verify_macho_architecture "$1"
  verify_macho_deployment_target "$1"
}

verify_release_binaries()
{
  verify_macho_file "${product}/Contents/MacOS/cbonsai saver"
  verify_macho_file "${product}/Contents/Resources/cbonsai"

  for dylib in "${product}/Contents/Resources/lib"/*.dylib
  do
    if [ ! -e "$dylib" ]; then
      continue
    fi

    verify_macho_file "$dylib"
  done
}

sign_screen_saver_bundle()
{
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - --timestamp=none "$1"
    codesign --verify --deep --strict --verbose=4 "$1"
  fi
}

if [ "$release_arch" = x86_64 ]; then
  NCURSES_PREFIX="$(./scripts/build-ncurses-source.sh "$release_arch" "$deployment_target")"
  CBONSAI_NCURSES_PKG_CONFIG_PATH="${NCURSES_PREFIX}/lib/pkgconfig"
  export CBONSAI_NCURSES_PKG_CONFIG_PATH
fi

CBONSAI_BINARY_PATH="$(./scripts/build-cbonsai-source.sh "$release_arch" "$deployment_target")"
export CBONSAI_BINARY_PATH

if [ "$CBONSAI_BINARY_PATH" != "${repo_root}/build/upstream/${release_profile}/cbonsai-v1.4.2/cbonsai" ]; then
  echo "Unexpected verified cbonsai binary path: $CBONSAI_BINARY_PATH" >&2
  exit 1
fi

if [ -n "$deployment_target" ]; then
  xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination "platform=macOS,arch=${release_arch}" \
    -derivedDataPath "$derived_data" \
    ARCHS="$release_arch" \
    ONLY_ACTIVE_ARCH=YES \
    MACOSX_DEPLOYMENT_TARGET="$deployment_target" \
    CODE_SIGNING_ALLOWED=NO \
    build
else
  xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination "platform=macOS,arch=${release_arch}" \
    -derivedDataPath "$derived_data" \
    ARCHS="$release_arch" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    build
fi

if [ ! -d "$product" ]; then
  echo "Missing built screen saver bundle: $product" >&2
  exit 1
fi

verify_release_binaries
sign_screen_saver_bundle "$product"

rm -rf "$staging_dir"
mkdir -p "$staging_dir"
/usr/bin/ditto --norsrc "$product" "${staging_dir}/cbonsai saver.saver"
cp -f LICENSE THIRD_PARTY_NOTICES.md SECURITY.md "$staging_dir/"

export COPYFILE_DISABLE=1
(
  cd "$staging_dir"
  /usr/bin/ditto --norsrc -c -k . "$archive"
)

shasum -a 256 "$archive"
