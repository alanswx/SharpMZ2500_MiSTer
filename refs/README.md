# refs/

Local reference material for the MZ-2500 core. Everything here except this README is gitignored (third-party code, copyrighted manuals
and scans, build trees). Re-fetch with `tools/fetch_refs.sh`. Sizes as of 2026-10-05.

| Path | Source | Licence | Size | Use |
|---|---|---|---|---|
| `mame/src-tree/` | https://github.com/mamedev/mame (shallow, blob-filtered, 395cc09e 2026-10-05) | GPL-2.0+ (mz2500 driver BSD-3) | 1.5 GB (incl. build) | full tree; `./mz2500` single-driver binary built here |
| `mame/mz2500.cpp`, `mz2500.h`, `mz2500_flop.xml`, `mz2000_flop.xml` | copies from the tree | BSD-3 / CC0 | 300 KB | quick reading |
| `mame/roms/mz2500/`, `mame/roms/mz2520/` | our ROM dumps renamed for MAME | Sharp copyright | 1 MB | `-rompath ../roms` |
| `mame/run/` | headless runs: `snap.lua`, PNGs, memory dumps | | 1 MB | |
| `mame/build.log` | MAME build log | | | |
| `csp/takeda/`, `csp/source.7z` | https://takeda-toshiya.my.coocan.jp/common/source.7z (2026-01-01) | GPLv2 | 34 MB / 4.5 MB | primary register reference (`source/src/vm/mz2500/`) |
| `csp/common_source_project-fm7/` | https://github.com/Artanejp/common_source_project-fm7 (shallow) | GPLv2 | 68 MB | Qt port source, with `macos_build.patch` applied |
| `csp/build/`, `csp/build_emuz2500.sh`, `csp/macos_stubs/`, `csp/macos_build.patch` | local build of `emumz2500` (Qt5) | GPLv2 | 28 MB | GUI emulator; see docs/emulators.md |
| `csp/run/` | EmuZ Qt home dir with ROMs, logs, window captures | | 2 MB | |
| `csp/BubiZ-2500/` | https://github.com/bubio/BubiZ-2500 (shallow, 197ffc3) | GPLv2 | 6 MB | CSP core vendored in `core/csp/` |
| `csp/bubiz-release/` | BubiZ-2500 v1.0.0 macOS apple-silicon .dmg + extracted .app (SHA256 683de6d5…) | GPLv2 | 4.5 MB | **headless reference emulator** |
| `csp/bubiz-run/` | ROM dir and headless output | | 1 MB | |
| `fpga/jt12/` | https://github.com/jotego/jt12 (shallow dc9be7c, jt49 submodule 7f6abfd) | GPL-3.0 | 53 MB | YM2203 (jt03) to vendor |
| `fpga/rtc/x68000_rp5c15.vhd`, `x68000_rtcbody.vhd`, `x68000_rtc.qip` | https://github.com/MiSTer-devel/X68000_MiSTer rtl/rtc | not stated | 20 KB | RP5C15 candidate |
| `fpga/rtc/msx_rtc.vhd` | https://github.com/MiSTer-devel/MSX_MiSTer rtl/peripheral/rtc.vhd | BSD-style, non-commercial | 25 KB | RP5C01 for comparison |
| `docs/` | web pages and manuals, see `docs/INDEX.md` | various (copyrighted scans) | 508 MB | |
| `compare/` | MAME vs BubiZ-2500 frames (IPL, Dust Box 1, Ys III) and an EmuZ Qt window capture | | 400 KB | first golden frames |
