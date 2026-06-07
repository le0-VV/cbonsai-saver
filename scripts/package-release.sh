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
build_root="build/release/${release_arch}"
derived_data="${build_root}/DerivedData"
artifacts_dir="build/release/artifacts"
product_dir="${derived_data}/Build/Products/${configuration}"
product="${product_dir}/cbonsai saver.saver"
staging_dir="${build_root}/staging/cbonsai-saver-${version}"

case "$release_arch" in
  arm64)
    archive_name="cbonsai-saver-${version}.zip"
    ;;
  x86_64)
    archive_name="cbonsai-saver-${version}-x86_64.zip"
    ;;
  *)
    echo "Unsupported release architecture: $release_arch" >&2
    exit 1
    ;;
esac

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

verify_release_architecture()
{
  verify_macho_architecture "${product}/Contents/MacOS/cbonsai saver"
  verify_macho_architecture "${product}/Contents/Resources/cbonsai"

  for dylib in "${product}/Contents/Resources/lib"/*.dylib
  do
    if [ ! -e "$dylib" ]; then
      continue
    fi

    verify_macho_architecture "$dylib"
  done
}

sign_screen_saver_bundle()
{
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - --timestamp=none "$1"
    codesign --verify --deep --strict --verbose=4 "$1"
  fi
}

CBONSAI_BINARY_PATH="$(./scripts/build-cbonsai-source.sh "$release_arch")"
export CBONSAI_BINARY_PATH

if [ "$CBONSAI_BINARY_PATH" != "${repo_root}/build/upstream/${release_arch}/cbonsai-v1.4.2/cbonsai" ]; then
  echo "Unexpected verified cbonsai binary path: $CBONSAI_BINARY_PATH" >&2
  exit 1
fi

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

if [ ! -d "$product" ]; then
  echo "Missing built screen saver bundle: $product" >&2
  exit 1
fi

verify_release_architecture
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
