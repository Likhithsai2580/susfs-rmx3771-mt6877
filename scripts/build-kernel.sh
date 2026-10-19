#!/bin/bash
docker run --rm \
  -v kbuild:/w \
  -v "C:/Users/Likhith/Desktop/duckfix-backup/kernel_build/aosp-clang:/clang:ro" \
  -v "C:/Users/Likhith/Desktop/duckfix-backup/kernel_build/strip-shim2.sh:/strip-shim2.sh:ro" \
  kbuild:4 bash -c '
CDIR=/clang/clang-r510928/bin
rm -rf /tmp/shim && mkdir -p /tmp/shim
ln -sf $CDIR/clang-18     /tmp/shim/clang
ln -sf $CDIR/clang-18     /tmp/shim/clang++
ln -sf $CDIR/lld          /tmp/shim/ld.lld
ln -sf $CDIR/lld          /tmp/shim/ld
ln -sf $CDIR/llvm-ar      /tmp/shim/llvm-ar
ln -sf $CDIR/llvm-nm      /tmp/shim/llvm-nm
ln -sf $CDIR/llvm-objcopy /tmp/shim/llvm-objcopy
ln -sf $CDIR/llvm-objdump /tmp/shim/llvm-objdump
ln -sf $CDIR/llvm-readelf /tmp/shim/llvm-readelf
ln -sf $CDIR/llvm-size    /tmp/shim/llvm-size
ln -sf /strip-shim2.sh    /tmp/shim/llvm-strip
export PATH=/tmp/shim:$CDIR:$PATH
cd /w/src
echo "=== RESUME $(date) ==="
echo "=== BUILD IMAGE (clang 18 + CFI + BTF) ==="
make ARCH=arm64 LLVM=1 LLVM_IAS=1 HOSTCC=gcc HOSTCXX=g++ -j1 Image > /tmp/build.log 2>&1
echo "=== IMAGE EXIT: $? ==="
tail -15 /tmp/build.log
echo
echo "=== CRC CHECK ==="
grep "module_layout" vmlinux.symvers 2>/dev/null
echo "device expects: 0x4e276f37"
echo "=== END $(date) ==="
'
