# Evidence

Raw output captured on the device. Nothing here is paraphrased.

## Device

```
$ adb shell getprop ro.product.model
RMX3771
$ adb shell getprop ro.product.device
RE58B8L1
$ adb shell getprop ro.board.platform
mt6877
$ adb shell uname -r
6.6.30-android15-8-o-gbf7a50923577-4k
$ adb shell getprop ro.build.version.release
15
```

## Kernel banner

```
$ adb shell su -c 'cat /proc/version'
Linux version 6.6.30-android15-8-o-gbf7a50923577-4k (kleaf@build-host)
(Android (11368308, +pgo, +bolt, +lto, +mlgo, based on r510928) clang version 18.0.0
(https://android.googlesource.com/toolchain/llvm-project 477610d4d0d988e69dbc3fae4fe86bff3f07f2b5),
LLD 18.0.0) #1 SMP PREEMPT Wed Apr 23 00:26:30 UTC 2025
```

## Module loading is permitted

```
$ adb shell su -c 'zcat /proc/config.gz' | grep -E 'MODULE_SIG|MODULE_UNLOAD'
CONFIG_MODULE_SIG_FORMAT=y
CONFIG_MODULE_SIG=y
# CONFIG_MODULE_SIG_FORCE is not set      <- unsigned modules load
CONFIG_MODULE_SIG_PROTECT=y
CONFIG_MODULE_UNLOAD=y                   <- reversible
```

## The device's module_layout CRC

Read out of a stock module's `__versions` section:

```
$ python3 -c "import struct;d=open('adsp.ko','rb').read();i=d.find(b'module_layout');print(hex(struct.unpack('<I',d[i-8:i-4])[0]))"
0x4e276f37
```

## A published LKM is refused (wrong GKI point release)

```
$ adb shell su -c 'insmod /data/local/tmp/kernelsu.ko'
insmod: failed to load /data/local/tmp/kernelsu.ko: No such file or directory

$ adb shell su -c 'dmesg | tail'
kernelsu: Unknown symbol mls_sid_to_context (err -2)
kernelsu: Unknown symbol sidtab_sid2str_put (err -2)
kernelsu: Unknown symbol cond_compute_av (err -2)
kernelsu: Unknown symbol ebitmap_cmp (err -2)
kernelsu: Unknown symbol ebitmap_contains (err -2)
```

Its vermagic, for comparison:

```
$ python3 -c "import re;d=open('kernelsu.ko','rb').read();print([r.decode() for r in re.findall(rb'[\x20-\x7e]{6,}',d) if b'vermagic' in r])"
['vermagic=6.6.127-4k-g46a034eca005-dirty SMP preempt mod_unload modversions aarch64']
```

## Wrong toolchain -> CRC mismatch

```
$ adb shell su -c 'insmod /data/local/tmp/susfs_test.ko'
insmod: failed to load /data/local/tmp/susfs_test.ko: Exec format error

$ adb shell su -c 'dmesg | tail -1'
susfs_guard_lkm: disagrees about version of symbol module_layout
```

The three CRCs observed:

```
GCC 12.2.0        0x7b09c576
clang 18, no BTF  0x6500052f
clang 18 + BTF    0x4e276f37   <- matches the device
```

## Correct build -> loads

```
$ adb shell su -c '/data/local/tmp/susfs_insmod /data/local/tmp/susfs_crc.ko'
susfs_insmod: image /data/local/tmp/susfs_crc.ko (2490096 bytes)
susfs_insmod: undefined symbols: 102
susfs_insmod: resolved 102/102; unresolved 0
susfs_insmod: init_module(2490096 bytes, 102 symbols absolutized, params "")
susfs_insmod: loaded (vermagic fixup not needed); checking /sys/module/susfs_guard_lkm
susfs_insmod: OK: /sys/module/susfs_guard_lkm exists
EXIT: 0
```

dmesg:

```
susfs_guard_lkm: susfs_avc_spoof: proc ready (/proc/susfs_avc_spoof)
susfs_guard_lkm: susfs supercall: armed (reboot ABI, version v2.3.0)
susfs_guard_lkm: susfs_hide_syms: kallsyms_op.show=ffffffe119c1dee8, probe body=ffffffe119c1dee8
susfs_guard_lkm: susfs_hide_syms: s_show armed at ffffffe119c1dee8 (by table identity)
susfs_guard_lkm: susfs_hide_syms: modules_op.show=ffffffe119bf3018, probe body=ffffffe119bf3018
susfs_guard_lkm: susfs_hide_syms: m_show armed at ffffffe119bf3018 (by table identity)
susfs_guard_lkm: sus_path: hooks armed (LSM + dirent rewrite on the stat layer's table entries)
susfs_guard_lkm: hide_modules: list set to 1 name(s)
susfs_guard_lkm: loaded. This module is filtered out of /proc/modules for every caller
                 including root, so `lsmod | grep susfs` stays empty - check
                 /sys/module/susfs_guard_lkm instead (a second insmod fails with
                 -EEXIST while it is loaded).
initcall init_module+0x0/0x174 [susfs_guard_lkm] returned 0 after 258577 usecs
```

## Control nodes present

```
$ adb shell su -c 'ls /proc/susfs*'
/proc/susfs_avc_spoof
/proc/susfs_enable_log
/proc/susfs_hide_modules
/proc/susfs_hide_mounts
/proc/susfs_kstat
/proc/susfs_opath
/proc/susfs_open_redirect
/proc/susfs_path
```

## Correctly hidden from lsmod

```
$ adb shell su -c 'lsmod | grep -c susfs'
0
```

## Artifact

```
$ sha256sum artifacts/susfs_guard_lkm-6.6.30.ko
86395bee31ef0b5aafaadc56bb576440fdc4c81c31eaa5f1102690d0f6169ac3

$ modinfo artifacts/susfs_guard_lkm-6.6.30.ko
description:    SUSFS guard LKM (susfs_guard_lkm) v2.3.0-gki
vermagic:       6.6.30-4k SMP preempt mod_unload modversions aarch64
name:           susfs_guard_lkm
```
