#!/bin/bash
# llvm-strip-shim.sh — make llvm-strip accept GNU's "-o OUT IN".
#
# WHY: drivers/firmware/efi/libstub/Makefile runs
#        $(STRIP) --strip-debug -o $@ $<
#      LLVM's strip does NOT accept -o. GNU strip cannot read aarch64 objects on an
#      x86 host. So translate: cp IN OUT && llvm-objcopy --strip-debug OUT
#
# CRITICAL: call the real binary by ABSOLUTE PATH. A shim installed as `llvm-strip`
# that calls bare `llvm-strip` resolves back to itself and recurses forever, hanging
# the build with no output at all.
#
# @REAL_STRIP@ is substituted by make-shim.sh.

REAL_STRIP="@REAL_STRIP@"
[ "$REAL_STRIP" = "@REAL_STRIP@" ] && REAL_STRIP="/clang/clang-r510928/bin/llvm-objcopy"

OUT=""
ALL=()

while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      OUT="$2"
      shift 2
      ;;
    *)
      ALL+=("$1")
      shift
      ;;
  esac
done

REAL_FLAGS=()
INPUT=""
for a in "${ALL[@]}"; do
  case "$a" in
    -*) REAL_FLAGS+=("$a") ;;
    *)  INPUT="$a" ;;
  esac
done

if [ -n "$OUT" ] && [ -n "$INPUT" ]; then
  cp "$INPUT" "$OUT" || exit 1
  exec "$REAL_STRIP" "${REAL_FLAGS[@]}" "$OUT"
elif [ -n "$INPUT" ]; then
  exec "$REAL_STRIP" "${REAL_FLAGS[@]}" "$INPUT"
else
  exec "$REAL_STRIP" "${REAL_FLAGS[@]}"
fi
