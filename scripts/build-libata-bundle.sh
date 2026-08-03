#!/usr/bin/env bash
# Rebuild vendor/libata/linux-x64 on Linux (cmake). Run when ata-validator updates.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT/vendor/libata/linux-x64"
ATA_SRC="${ATA_VALIDATOR_SRC:-/tmp/ata-validator}"
BUILD_DIR="$ATA_SRC/build-shared"
STAGING="$ROOT/lib/ata-validator-crystal/libata"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "error: run this script on Linux" >&2
  exit 1
fi

command -v cmake >/dev/null || { echo "error: cmake required" >&2; exit 1; }
command -v crystal >/dev/null || { echo "error: crystal required" >&2; exit 1; }

if [[ ! -d "$ROOT/lib/ata-validator-crystal" ]]; then
  (cd "$ROOT" && shards install)
fi

if [[ ! -d "$ATA_SRC/.git" ]]; then
  git clone --depth 1 https://github.com/ata-core/ata-validator.git "$ATA_SRC"
fi

cd "$ROOT/lib/ata-validator-crystal"
sed -i 's/-DATA_SHARED=ON/-DBUILD_SHARED_LIBS=ON/' scripts/build_native.cr
crystal run scripts/build_native.cr

mkdir -p "$STAGING"
while IFS= read -r -d '' artifact; do
  cp -P "$artifact" "$STAGING/"
done < <(find "$BUILD_DIR" -name '*.so*' -print0)

if command -v patchelf >/dev/null; then
  patchelf --set-rpath '$ORIGIN' "$STAGING/libata.so"
fi

SHA=$(git -C "$ATA_SRC" rev-parse HEAD)
rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR"
cp -P "$STAGING"/*.so* "$VENDOR_DIR/"
cat > "$VENDOR_DIR/MANIFEST" <<EOF
ata-validator=${SHA}
platform=linux-x86_64-gnu
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "vendor bundle ready: $VENDOR_DIR ($(find "$VENDOR_DIR" -name '*.so*' | wc -l) files)"
