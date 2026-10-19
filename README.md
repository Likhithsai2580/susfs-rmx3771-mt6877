# SUSFS for realme 11 Pro 5G (RMX3771 / mt6877) — kernel 6.6.30

**A working SUSFS loadable kernel module for a device that has none.**

Every published SUSFS/KernelSU LKM targets mainline GKI `6.6.127`. This device runs a
vendor `6.6.30`, so all of them are refused by the kernel. This repo contains the
module built against the device's own kernel source, plus the exact recipe.

```
Device      realme 11 Pro 5G (RMX3771) · codename RE58B8L1 · MediaTek mt6877
Kernel      6.6.30-android15-8-o-gbf7a50923577-4k   (GKI, kleaf-built)
Android     15 (SDK 35)
Artifact    artifacts/susfs_guard_lkm-6.6.30.ko
sha256      86395bee31ef0b5aafaadc56bb576440fdc4c81c31eaa5f1102690d0f6169ac3
vermagic    6.6.30-4k SMP preempt mod_unload modversions aarch64
```

## Status: LOADED AND OPERATIONAL

```
$ susfs_insmod /data/local/tmp/susfs_guard_lkm.ko
susfs_insmod: undefined symbols: 102
susfs_insmod: resolved 102/102; unresolved 0
susfs_insmod: init_module(2490096 bytes, 102 symbols absolutized)
susfs_insmod: OK: /sys/module/susfs_guard_lkm exists
EXIT: 0
```

dmesg:

```
susfs_guard_lkm: susfs_avc_spoof: proc ready (/proc/susfs_avc_spoof)
susfs_guard_lkm: susfs supercall: armed (reboot ABI, version v2.3.0)
susfs_guard_lkm: susfs_hide_syms: s_show armed at ffffffe119c1dee8 (by table identity)
susfs_guard_lkm: susfs_hide_syms: m_show armed at ffffffe119bf3018 (by table identity)
susfs_guard_lkm: sus_path: hooks armed (LSM + dirent rewrite on the stat layer's table entries)
susfs_guard_lkm: hide_modules: list set to 1 name(s)
susfs_guard_lkm: loaded. This module is filtered out of /proc/modules for every caller
                 including root, so `lsmod | grep susfs` stays empty - check
                 /sys/module/susfs_guard_lkm instead
```

All eight control nodes are present:

```
/proc/susfs_avc_spoof      /proc/susfs_enable_log     /proc/susfs_hide_modules
/proc/susfs_hide_mounts    /proc/susfs_kstat          /proc/susfs_opath
/proc/susfs_open_redirect  /proc/susfs_path
```

## Why the published LKMs do not work here

Both KernelSU-Next's and susfs4ksu-lkm's prebuilt `android15-6.6` modules carry:

```
vermagic=6.6.127-4k-g46a034eca005-dirty
```

The device is `6.6.30`. Loading one returns:

```
kernelsu: Unknown symbol mls_sid_to_context (err -2)
kernelsu: Unknown symbol sidtab_sid2str_put (err -2)
kernelsu: Unknown symbol cond_compute_av (err -2)
kernelsu: Unknown symbol ebitmap_cmp (err -2)
kernelsu: Unknown symbol ebitmap_contains (err -2)
```

Those are SELinux internals present in 6.6.127 but not exported in 6.6.30.
A module is not portable across GKI point releases. It has to be built.

## The CRC problem — and the fix

Building with the wrong toolchain produces a module the kernel refuses:

```
susfs_guard_lkm: disagrees about version of symbol module_layout
```

`module_layout` is the CRC of the kernel's core struct layout. It has to match the
running kernel exactly. Three builds, three values:

| Build | `module_layout` CRC | Why |
|---|---|---|
| GCC 12.2.0 | `0x7b09c576` | wrong compiler |
| clang 18, no BTF | `0x6500052f` | right compiler, `CONFIG_DEBUG_INFO_BTF` silently dropped |
| **clang 18 + BTF** | **`0x4e276f37`** | **matches the device** |

The last variable was `CONFIG_DEBUG_INFO_BTF=y`. `make olddefconfig` **silently
removes** options whose dependencies are unmet, and `pahole` was not installed — so
BTF was dropped without a word, changing struct layout and therefore every CRC.

The device's own CRC was read out of a stock module's `__versions` section:

```
$ python3 -c "import struct;d=open('adsp.ko','rb').read();i=d.find(b'module_layout');print(hex(struct.unpack('<I',d[i-8:i-4])[0]))"
0x4e276f37
```

## Build recipe

See `docs/BUILD.md` for the full walkthrough. The short version:

```bash
# 1. AOSP clang r510928 — byte-identical to the stock kernel's toolchain
git clone --depth 1 -b android-15.0.0_r1 \
  https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 aosp-clang

# 2. kernel source (realme GPL release) + the device's own /proc/config.gz
# 3. build the kernel to generate vmlinux.symvers
make ARCH=arm64 LLVM=1 LLVM_IAS=1 HOSTCC=gcc HOSTCXX=g++ -j1 Image

# 4. vmlinux.symvers -> Module.symvers, then build the LKM
make -C $KERNEL M=$SUSFS/kernel ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  KBUILD_MODPOST_WARN=1 modules
```

### Three traps that cost the most time

All three AOSP toolchain entry points are **text files**, not binaries:

```
clang.real   -> "clang-18"
ld.lld       -> "lld"
llvm-strip   -> "llvm-objcopy"
```

Point a shim directory at the real binaries (`clang-18`, `lld`, `llvm-objcopy`).

`llvm-strip` does **not** support GNU's `-o OUT IN`, which the EFI stub Makefile
requires. The shim has to translate it (`cp IN OUT && llvm-objcopy --strip-debug OUT`).
**Call the real binary by absolute path** — a shim that calls bare `llvm-strip`
resolves back to itself and recurses forever.

`-j4` OOMs on this machine (`Error 123` on `net/core`). `-j1` works.

## Why `insmod` fails but `susfs_insmod` works

The kernel's own loader refuses two categories:

- **5 symbols resolved at runtime** by the module's `imports_guard.c`:
  `init_mm`, `__set_fixmap`, `copy_to_kernel_nofault`, `task_work_add`, `saved_boot_config`
- **2 GKI protected exports** (`err -13`): `strnlen_user`, `security_secctx_to_secid`

`susfs_insmod` (shipped with susfs4ksu-lkm) walks kallsyms itself and absolutizes all
102 undefined symbols. Use it, or load through `ksud insmod` on KernelSU.

## What SUSFS buys you

SUSFS hooks at the kernel VFS/LSM layer, so it can hide what Magisk structurally
cannot — Magisk's own `tmpfs magisk` mount tokens, the `/product/bin/su` path, and
SELinux policy modifications. Those are the signals a Magisk-only setup cannot clear.

## Provenance

- SUSFS: [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (GPL-2.0)
- LKM port: [inforcqb/susfs4ksu-lkm](https://github.com/inforcqb/susfs4ksu-lkm) (GPL-2.0)
- Kernel source: realme's GPL release for mt6877 Android V
- The build recipe, the CRC analysis and the toolchain shims in `scripts/` are this repo's work

The module is GPL-2.0, inherited from its sources. Kernel source is realme's, under GPL-2.0.

## Caveats

- Built for **one exact kernel build**. A different `uname -r` will refuse it.
- Loaded manually here; loading at boot needs KernelSU-Next (`ksud insmod`).
- The final `BTFIDS vmlinux` step fails with pahole 1.24 (`libbpf: BTF header not
  found`). That affects only the kernel image's BTF section — `vmlinux.symvers` is
  written before it and carries the CRCs the module needs.
