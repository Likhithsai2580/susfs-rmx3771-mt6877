# Build walkthrough

Everything below was run on Windows 11 with Docker Desktop (Linux containers).
The kernel source lives in a Docker named volume so the build is reproducible.

## 0. Facts to establish first

```bash
adb shell uname -r
# 6.6.30-android15-8-o-gbf7a50923577-4k

adb shell su -c 'zcat /proc/config.gz' > stock.config     # the device's own config
adb shell su -c 'modinfo /vendor/lib/modules/adsp.ko' | grep vermagic
# vermagic: 6.6.30-android15-8-o-gbf7a50923577-4k SMP preempt mod_unload modversions aarch64
```

Check that unsigned modules can load:

```bash
grep -E 'CONFIG_MODULE_SIG_FORCE|CONFIG_MODULE_UNLOAD' stock.config
# # CONFIG_MODULE_SIG_FORCE is not set    <- unsigned modules load
# CONFIG_MODULE_UNLOAD=y                 <- reversible
```

## 1. Read the device's `module_layout` CRC

This is the number the whole build has to hit. It is in the `__versions` section of
any stock module:

```bash
adb shell su -c 'cp /vendor/lib/modules/adsp.ko /data/local/tmp/'
adb pull /data/local/tmp/adsp.ko

python3 - <<'EOF'
import struct
d = open('adsp.ko','rb').read()
i = d.find(b'module_layout')
print(hex(struct.unpack('<I', d[i-8:i-4])[0]))
EOF
# 0x4e276f37
```

## 2. Toolchain — AOSP clang r510928

The stock kernel's banner names its compiler exactly:

```
Android (11368308, +pgo, +bolt, +lto, +mlgo, based on r510928) clang version 18.0.0
```

Get that tree:

```bash
git clone --depth 1 -b android-15.0.0_r1 \
  https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 aosp-clang
# ~17 GB; clang-r510928/ inside it is the one you want
```

### The wrapper trap

Three entry points are **text files**, not ELF binaries:

```bash
$ file aosp-clang/clang-r510928/bin/clang.real
clang.real: ASCII text, with no line terminators      # contents: "clang-18"

$ file aosp-clang/clang-r510928/bin/ld.lld
ld.lld: ASCII text                                    # contents: "lld"

$ file aosp-clang/clang-r510928/bin/llvm-strip
llvm-strip: ASCII text                                # contents: "llvm-objcopy"
```

The Go wrapper (`clang`) execs `clang.real`, which fails with
`exec format error` / `posix_spawn failed`. Build a shim directory that points at the
**real** binaries instead — see `scripts/make-shim.sh`.

## 3. The `llvm-strip -o` problem

`drivers/firmware/efi/libstub/Makefile` runs:

```
$(STRIP) --strip-debug -o $@ $<
```

LLVM's strip does **not** accept `-o`. GNU strip can't read aarch64 objects on an
x86 host. So the shim has to translate:

```bash
cp "$IN" "$OUT" && llvm-objcopy --strip-debug "$OUT"
```

**Call the real binary by absolute path.** A shim that calls bare `llvm-strip`
resolves back to itself and hangs forever with no output — that cost one full build
cycle. See `scripts/llvm-strip-shim.sh`.

## 4. Kernel source and config

Realme publish the mt6877 Android V kernel source (GPL-2.0). Extract it on Linux —
Windows cannot create `drivers/gpu/drm/nouveau/**/aux.c` (reserved name).

```bash
docker volume create kbuild
docker run --rm -v kbuild:/w -v "$PWD:/host" debian:bookworm-slim \
  bash -c 'mkdir -p /w/src && tar -xf /host/kernel.tar.gz -C /w/src --strip-components=1'
```

Strip CRLF from the whole tree (19k files; extension-based passes miss extensionless
ones):

```bash
grep -rlZ -m1 $'\r' . | xargs -0 -r sed -i 's/\r$//'
```

Then place the device's own config:

```bash
cp stock.config /w/src/.config
```

## 5. Build the kernel

```bash
make ARCH=arm64 LLVM=1 LLVM_IAS=1 HOSTCC=gcc HOSTCXX=g++ -j1 Image
```

- `-j1` is required. `-j4` dies with `Error 123` on `net/core` (OOM).
- Stop other Docker workloads first — the `vmlinux.o` link needs ~1.5–2 GB.
- `HOSTCC=gcc` avoids a stale `.cmd` referencing a gcc-13 header path.

## 6. `Module.symvers` — the file that matters

The build ends with:

```
LD      vmlinux
BTFIDS  vmlinux
FAILED: load BTF from vmlinux: Invalid argument
```

pahole 1.24 cannot parse this vmlinux. **This does not matter for the module.**
`vmlinux.symvers` is written *before* the BTFIDS step and carries the CRCs:

```bash
grep module_layout vmlinux.symvers
# 0x4e276f37	module_layout	vmlinux	EXPORT_SYMBOL
```

Copy it over:

```bash
cp vmlinux.symvers Module.symvers
```

## 7. Build the LKM

```bash
git clone --depth 1 https://github.com/inforcqb/susfs4ksu-lkm
make -C /w/src M=/w/susfs_lkm_src/kernel \
     ARCH=arm64 LLVM=1 LLVM_IAS=1 KBUILD_MODPOST_WARN=1 modules
```

`KBUILD_MODPOST_WARN=1` is required: five symbols are intentionally unresolved at
link time and resolved at runtime by `imports_guard.c`.

## 8. Load it

```bash
adb push susfs_guard_lkm.ko /data/local/tmp/
adb push susfs_insmod /data/local/tmp/
adb shell su -c 'chmod 755 /data/local/tmp/susfs_insmod'
adb shell su -c '/data/local/tmp/susfs_insmod /data/local/tmp/susfs_guard_lkm.ko'
```

`insmod` will fail with `Unknown symbol` / `Protected symbol`. That is expected —
`susfs_insmod` walks kallsyms itself and resolves all 102.

Verify:

```bash
adb shell su -c 'ls /sys/module/susfs_guard_lkm'
adb shell su -c 'ls /proc/susfs*'
```

## 9. Recovering from a bad build

A module that fails to load is harmless — the kernel rejects it and continues.
Nothing is written to disk. If a *kernel image* is ever flashed and bootloops,
restore the backed-up boot partitions:

```bash
fastboot flash boot_a boot_a.img
fastboot flash boot_b boot_b.img
```

Back up first, always:

```bash
adb shell su -c 'dd if=/dev/block/by-name/boot_a of=/data/local/tmp/boot_a.img'
adb pull /data/local/tmp/boot_a.img
```
