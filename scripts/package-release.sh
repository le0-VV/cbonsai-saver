#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

version="${1:-1.0}"
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

mkdir -p "$artifacts_dir"

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
