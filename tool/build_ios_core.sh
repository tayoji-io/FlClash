#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$PATH"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk="${PLATFORM_NAME:?PLATFORM_NAME is not set}"
out="$root/libclash/ios/$sdk"
config="$root/build_config.yaml"
tags="$(sed -n 's/^tags:[[:space:]]*//p' "$config" | tr -d '"'"'"'')"
ldflags="$(sed -n 's/^go_ldflags:[[:space:]]*//p' "$config" | tr -d '"'"'"'')"
[ -n "$tags" ] || tags="with_gvisor"
[ -n "$ldflags" ] || ldflags="-w -s"

sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
clang="$(xcrun --sdk "$sdk" --find clang)"

mkdir -p "$out"
lock="$out/.build-lock"
for _ in $(seq 1 600); do
  mkdir "$lock" 2>/dev/null && break
  sleep 0.5
done
tmp="$(mktemp -d "$out/.tmp.XXXXXX")"
trap 'rm -rf "$tmp"; rmdir "$lock" 2>/dev/null || true' EXIT

slices=()
for arch in ${ARCHS:-arm64}; do
  case "$arch" in
    arm64 | arm64e) goarch=arm64 ;;
    x86_64) goarch=amd64 ;;
    *) continue ;;
  esac
  if [ "$sdk" = "iphoneos" ]; then
    suffix=""
  else
    suffix="-simulator"
  fi
  triple="$([ "$goarch" = "amd64" ] && echo x86_64 || echo arm64)-apple-ios15.0$suffix"
  mkdir -p "$tmp/$arch"
  (
    cd "$root/core"
    CGO_ENABLED=1 GOOS=ios GOARCH="$goarch" CC="$clang" CXX="$clang++" \
      CGO_CFLAGS="-isysroot $sdk_path -target $triple" \
      CGO_LDFLAGS="-isysroot $sdk_path -target $triple" \
      go build -tags "$tags" -ldflags "$ldflags" -buildmode=c-archive \
      -o "$tmp/$arch/libclash.a" ./cmd/ios
  )
  slices+=("$tmp/$arch/libclash.a")
done

if [ "${#slices[@]}" -eq 1 ]; then
  cp "${slices[0]}" "$tmp/libclash.a"
else
  lipo -create "${slices[@]}" -output "$tmp/libclash.a"
fi
cp "${slices[0]%.a}.h" "$tmp/libclash.h"

if ! cmp -s "$tmp/libclash.a" "$out/libclash.a" || [ ! -f "$out/libclash.h" ]; then
  mv "$tmp/libclash.a" "$out/libclash.a"
  mv "$tmp/libclash.h" "$out/libclash.h"
fi
