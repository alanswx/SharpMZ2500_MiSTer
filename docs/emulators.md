# Reference emulators

Status on this Mac (Apple Silicon, macOS 27, Homebrew qt@5 5.15.19, sdl2, ffmpeg 8, cmake, ninja), 2026-10-05.

## Comparison

| Emulator | Licence | Core | Accuracy | macOS | Headless |
|---|---|---|---|---|---|
| **EmuZ-2500** (Takeda Toshiya, Common Source Code Project, official source 2026-01-01) | GPLv2 | C++ | The most complete: all three boot modes (2500/2000/80B), cycle-level Z80 with M1/memory/I/O waits and display-period VRAM WAIT, both video controllers with all graphics modes, split scroll, palettes and priority, CMT with APSS, SASI, MZ-1R12/1R13/1R37/1E26/1E30/1E32, CMU-800 | official build is Win32 only | no (debugger only) |
| **BubiZ-2500** (bubio, v1.0.0, 2026) | GPLv2 | the CSP EmuZ-2500 core (identical to the official 2026-01-01 `vm/mz2500/` apart from one cast), Odin + Sokol front end | = EmuZ-2500 | **release binary works** (apple-silicon .dmg) | **yes**: `-headless N -screenshot`, `-shotat`, `-key`, `-wav`, `-savestate/-loadstate` |
| CSP Qt port (Artanejp/common_source_project-fm7, `emumz2500`) | GPLv2 | older CSP core (crtc.cpp differs by ~440 lines from 2026-01-01) | slightly behind the official source | **built** with workarounds (below); GUI runs, IPL works | no; `--fd0` didn't insert the disk in my test |
| **MAME** `mz2500` / `mz2520` (Angelo Salese) | BSD-3-Clause (driver header); MAME as a whole GPL-2.0+ | C++ | `MACHINE_IMPERFECT_GRAPHICS`; no wait states, no 2000/80B modes, partial graphics modes; softlist 31 yes / 26 partial / 18 no | **built** single-driver | **yes**: `-video none`, Lua autoboot (snapshot + memory dumps) |
| Michael Franzen's Z80 emulator | freeware, closed | | test version, very old | Windows/DOS | no |
| youkan700 "EmuZ-2500 野良ビルド" (github.com/youkan700/CSCP) | GPLv2 (CSP) | CSP fork with fixes, mostly merged upstream 2025-11 | ≈ CSP | Windows | no |
| kuran-kuran fork (github.com/kuran-kuran/CommonSourceCodeProject) | GPLv2 (CSP) | CSP fork (CMU-800, MZ-1R12), merged upstream 2025-12 | ≈ CSP | Windows | no |
| RetroArch | | MAME core only (no dedicated libretro core) | = MAME | | |

**Recommendation:** use **BubiZ-2500 (CSP core) as the primary reference**, headless; MAME as a second opinion and for memory dumps via Lua.
Read register-level behaviour from the official CSP source in `refs/csp/takeda/`.

## BubiZ-2500 (works headless) — primary

```bash
# fetch (tools/fetch_refs.sh does this)
gh release download v1.0.0 -R bubio/BubiZ-2500 -p '*macos-apple-silicon.dmg' -p SHA256SUMS.txt -D refs/csp/bubiz-release
cd refs/csp/bubiz-release
hdiutil attach -nobrowse -readonly -mountpoint ./mnt BubiZ-2500-1.0.0-macos-apple-silicon.dmg
cp -R mnt/BubiZ-2500.app . && hdiutil detach ./mnt && xattr -cr BubiZ-2500.app

# ROMs: IPL.ROM KANJI.ROM DICT.ROM PHONE.ROM (KANJI2.ROM) in one folder
B=refs/csp/bubiz-release/BubiZ-2500.app/Contents/MacOS/BubiZ-2500
$B -romdir refs/csp/bubiz-run/roms -noconfig -nosaveconfig -nosound \
   -headless 600 -screenshot out/ipl.png                         # IPL "loading error" screen
$B -romdir refs/csp/bubiz-run/roms -noconfig -nosaveconfig -nosound \
   -headless 7000 -shotat 1200:out/f1200.bmp -screenshot out/f7000.png disk.d88   # boot a D88 in drive 1
```

7000 frames (126 s emulated) run in under 3 s. Output is 640x400. Other options: `-mz2000/-mz80b` boot mode, `-monitor <n>` (CSP monitor
type: bit 1 = 200-line), `-key <frame>:<key>[:<hold>]`, `-tapeload`, `-wav`, `-savestate <frame>:<slot>`. Full list in
`refs/csp/BubiZ-2500/docs/usage.md`.

Building BubiZ from source (not tried): `scripts/setup.sh && scripts/build.sh release` with mise + Odin `dev-2026-09` (`brew install odin`
has 2026-09), CMake, Xcode CLT. The CSP core is vendored under `core/csp/`, so a C++-only headless harness could be made from it if
memory dumps or CPU traces are needed (BubiZ has a debugger: `-debug`).

## MAME single-driver build (works headless)

```bash
git clone --depth 1 --filter=blob:none https://github.com/mamedev/mame.git refs/mame/src-tree   # ~1.5 GB checked out
cd refs/mame/src-tree
make SUBTARGET=mz2500 SOURCES=src/mame/sharp/mz2500.cpp REGENIE=1 -j14     # ~6 minutes on this Mac, binary ./mz2500 (78 MB)
```

ROMs in `refs/mame/roms/mz2500/` with MAME names (`ipl.rom cg.rom kanji.rom kanji2.rom dict.rom phone.rom`; `mz2520/ipl2520.rom`).

Headless run with the Lua helper `refs/mame/run/snap.lua` (copied to `tools/mame_snap.lua`): after `SNAP_FRAMES` frames it saves a
snapshot (PNG under `<snapshot_directory>/mz2500/`), dumps the CPU's 64 KB view and the `wram`, `cgram`, `tvram` shares, then exits.

```bash
cd refs/mame/run
SNAP_FRAMES=3000 SNAP_OUT=ys3 ../src-tree/mz2500 mz2500 -rompath ../roms -flop1 disk.d88 \
  -video none -sound none -nothrottle -snapshot_directory . -autoboot_script snap.lua
```

About 13x real time. MAME's output is 640x200 (its DSW default selects the 200-line monitor). `-seconds_to_run` also works instead of the Lua
frame counter. Software-list names work too (`mz2500 ys3` with a softlist ROM path).

## CSP Qt port (`emumz2500`) — builds, GUI only

```bash
git clone --depth 1 https://github.com/Artanejp/common_source_project-fm7.git refs/csp/common_source_project-fm7
# one source fix for clang: __builtin_expect needs a long, not a pointer (refs/csp/macos_build.patch)
sed -i '' 's/__builtin_expect((foo), \([01]\))/__builtin_expect(!!(foo), \1)/g' \
  refs/csp/common_source_project-fm7/source/src/types/optimizer_utils.h
mkdir -p refs/csp/macos_stubs && printf '#pragma once\n#include <stdlib.h>\n' > refs/csp/macos_stubs/malloc.h
CXXF="-DGL_DYNAMIC_STORAGE_BIT=0x0100 -DGL_MAP_PERSISTENT_BIT=0x0040 -DGL_MAP_COHERENT_BIT=0x0080 -D__isnan=isnan \
 -include arm_acle.h -I$PWD/refs/csp/macos_stubs -D'avcodec_close(x)=0' -DFF_PROFILE_H264_HIGH=100"
refs/csp/build_emuz2500.sh -DCMAKE_CXX_FLAGS="$CXXF" -DCMAKE_C_FLAGS="-I$PWD/refs/csp/macos_stubs" \
  -DUSE_MOVIE_SAVER=OFF -DUSE_MOVIE_LOADER=OFF -DUSE_LTO=OFF \
  -DCMAKE_SHARED_LINKER_FLAGS="-L/opt/homebrew/lib -undefined dynamic_lookup" -DCMAKE_EXE_LINKER_FLAGS="-L/opt/homebrew/lib"
```

`build_emuz2500.sh` turns every `BUILD_*` machine off except `BUILD_MZ2500` and runs CMake + Ninja (Qt5 from Homebrew). Problems worked around:
macOS GL headers lack GL 4.4 constants; no `malloc.h`; `__isnan`/`__isb` in the i386 core (`-include arm_acle.h`); FFmpeg 8 removed
`avcodec_close`/`FF_PROFILE_*`; libraries linked with undefined symbols (`-undefined dynamic_lookup`); `-L` for SDL2.

Run: `refs/csp/build/emumz2500 --gl2 -d refs/csp/run/home/` (ROMs in `refs/csp/run/home/CommonSourceCodeProject/emumz2500/`). Without `--gl2`
the OpenGL context fails and the screen stays black. Sound init fails (runs unthrottled at ~200%). The IPL screen is correct.
`--fd0 <file>` logged the media but the drive stayed empty; use the menu or BubiZ instead. `QT_QPA_PLATFORM=offscreen` starts but
can't render (QOpenGLWidget unsupported), so no headless use.

## Comparison plan for the core

1. Golden frames: BubiZ-2500 `-headless N -screenshot` at fixed frame numbers for a set of disks (software.md test list), 640x400 PNG.
   Same ROMs, `-noconfig` for a fixed default configuration (400-line, MZ-2500 mode).
2. The Verilator sim of the core writes frames as PNG at the same frame numbers (frame = graphics V-blank count from reset) and compares
   with a tolerance (palette differences: CSP uses 127/152 levels for half-bright and grey on an analogue monitor; use the digital
   palette or compare indices where possible).
3. Keyboard input: BubiZ `-key <frame>:<key>`; the sim injects the same matrix bits at the same frame.
4. Memory/CPU state: MAME Lua dumps (`snap.lua`) of main RAM, VRAM and text VRAM at a frame; MAME has no wait states, so only compare
   frame-insensitive states (after loading, at a menu). BubiZ's debugger (`-debug`) can dump memory interactively; for scripted CPU traces
   build a small harness from `refs/csp/BubiZ-2500/core/csp`.
5. Already captured examples: `refs/compare/` (IPL, Dust Box 1 title, Ys III intro) from both emulators.

## Other notes

- MAME's software list `hash/mz2500_flop.xml` (CC0) is the acceptance set; its header documents BASIC-M25 tricks (HELP key at boot for S25).
- CSP history and the author's diary (`refs/docs/takeda/`) list most timing fixes (VRAM WAIT, 8253 write timing, MB8877 density, VBLANK
  when start == end).
