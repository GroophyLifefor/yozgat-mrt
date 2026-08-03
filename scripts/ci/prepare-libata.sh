#!/usr/bin/env bash
# Build libata.so and copy its transitive shared libs into libata/.
# Cached artifacts must include libata.so + libre2.so* + libsimdjson.so*
# so release jobs can link without /tmp/ata-validator/build-shared present.
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/../.." && pwd)}"
LIB_DIR="$ROOT/lib/ata-validator-crystal/libata"
ATA_SRC="${ATA_VALIDATOR_SRC:-/tmp/ata-validator}"
BUILD_DIR="$ATA_SRC/build-shared"

libata_complete() {
  [[ -f "$LIB_DIR/libata.so" ]] || return 1
  compgen -G "$LIB_DIR/libre2.so*" >/dev/null || return 1
  compgen -G "$LIB_DIR/libsimdjson.so*" >/dev/null || return 1
}

copy_transitive_libs() {
  mkdir -p "$LIB_DIR"
  for name in libre2 libsimdjson; do
    while IFS= read -r -d '' artifact; do
      cp -P "$artifact" "$LIB_DIR/"
    done < <(find "$BUILD_DIR" -name "${name}.so*" -print0)
  done
}

build_libata() {
  if [[ ! -d "$ATA_SRC/.git" ]]; then
    git clone --depth 1 https://github.com/ata-core/ata-validator.git "$ATA_SRC"
  fi

  cd "$ROOT/lib/ata-validator-crystal"
  sed -i 's/-DATA_SHARED=ON/-DBUILD_SHARED_LIBS=ON/' scripts/build_native.cr
  crystal run scripts/build_native.cr
  copy_transitive_libs

  if command -v patchelf >/dev/null; then
    patchelf --set-rpath '$ORIGIN' "$LIB_DIR/libata.so"
  fi
}

if libata_complete; then
  echo "libata bundle already complete in $LIB_DIR"
  ls -la "$LIB_DIR"
  exit 0
fi

echo "libata bundle incomplete — building native library..."
build_libata
echo "libata bundle ready:"
ls -la "$LIB_DIR"
