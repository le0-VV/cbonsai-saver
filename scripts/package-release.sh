#!/bin/sh
set -eu

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

cd "$(dirname "$0")/.."

version="${1:-1.1.1}"
repo_root="$(pwd)"
project="cbonsai saver/cbonsai saver.xcodeproj"
scheme="cbonsai saver"
configuration="Release"
build_root="build/release"
derived_data="${build_root}/DerivedData"
artifacts_dir="${build_root}/artifacts"
product_dir="${derived_data}/Build/Products/${configuration}"
product="${product_dir}/cbonsai saver.saver"
staging_dir="${build_root}/staging/cbonsai-saver-${version}"
archive="${repo_root}/${artifacts_dir}/cbonsai-saver-${version}.zip"

case "$version" in
  ""|.*|-*|*..*|*[!0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._-]*)
    echo "Invalid release version: $version" >&2
    exit 1
    ;;
esac

mkdir -p "$artifacts_dir"

sign_screen_saver_bundle()
{
  if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - --timestamp=none "$1"
    codesign --verify --deep --strict --verbose=4 "$1"
  fi
}

CBONSAI_BINARY_PATH="$(./scripts/build-cbonsai-source.sh)"
export CBONSAI_BINARY_PATH

if [ "$CBONSAI_BINARY_PATH" != "${repo_root}/build/upstream/cbonsai-v1.4.2/cbonsai" ]; then
  echo "Unexpected verified cbonsai binary path: $CBONSAI_BINARY_PATH" >&2
  exit 1
fi

xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [ ! -d "$product" ]; then
  echo "Missing built screen saver bundle: $product" >&2
  exit 1
fi

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
