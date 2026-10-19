#!/bin/bash
docker run --rm -v kbuild:/w kbuild:2 bash -c '
cd /w/src
echo "=== START $(date) ==="
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules -j1 2>&1 | tail -30
echo "=== EXIT: $? ==="
ls -la Module.symvers 2>/dev/null && wc -l Module.symvers
echo "=== END $(date) ==="
'
