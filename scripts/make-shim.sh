#!/bin/bash
# make-shim.sh — build a shim dir that bypasses the AOSP clang Go wrappers.
#
# WHY: three AOSP toolchain entry points are TEXT FILES, not ELF binaries:
#   clang.real  -> "clang-18"
#   ld.lld      -> "lld"
#   llvm-strip  -> "llvm-objcopy"
# The `clang` Go wrapper execs clang.real and dies with
#   "exec format error" / "posix_spawn failed"
#
# This creates $SHIM with symlinks to the REAL binaries. Put it FIRST in PATH.
#
# Usage:  bash make-shim.sh /clang/clang-r510928/bin /tmp/shim
set -eu

CDIR="${1:?usage: make-shim.sh <clang-bin-dir> <shim-dir>}"
SHIM="${2:?usage: make-shim.sh <clang-bin-dir> <shim-dir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"

rm -rf "$SHIM"
mkdir -p "$SHIM"

# clang-18 is the real compiler; clang/clang++ are wrappers
ln -sf "$CDIR/clang-18"      "$SHIM/clang"
ln -sf "$CDIR/clang-18"      "$SHIM/clang++"

# lld is the real linker; ld.lld is a wrapper
ln -sf "$CDIR/lld"           "$SHIM/ld.lld"
ln -sf "$CDIR/lld"           "$SHIM/ld"

# plain binaries, safe to link directly
ln -sf "$CDIR/llvm-ar"       "$SHIM/llvm-ar"
ln -sf "$CDIR/llvm-nm"       "$SHIM/llvm-nm"
ln -sf "$CDIR/llvm-objcopy"  "$SHIM/llvm-objcopy"
ln -sf "$CDIR/llvm-objdump"  "$SHIM/llvm-objdump"
ln -sf "$CDIR/llvm-readelf"  "$SHIM/llvm-readelf"
ln -sf "$CDIR/llvm-size"     "$SHIM/llvm-size"

# llvm-strip needs the -o translation shim (see llvm-strip-shim.sh).
# The shim itself calls $CDIR/llvm-objcopy by ABSOLUTE PATH.
if [ -f "$HERE/llvm-strip-shim.sh" ]; then
  sed "s|@REAL_STRIP@|$CDIR/llvm-objcopy|" \
      "$HERE/llvm-strip-shim.sh" > "$SHIM/llvm-strip"
  chmod +x "$SHIM/llvm-strip"
else
  ln -sf "$CDIR/llvm-objcopy" "$SHIM/llvm-strip"
fi

echo "shim built at $SHIM:"
ls -la "$SHIM"
echo
echo "export PATH=$SHIM:\$PATH"
