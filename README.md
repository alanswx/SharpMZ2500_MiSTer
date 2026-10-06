# Sharp MZ-2500 / MZ-2520 for MiSTer

A MiSTer FPGA core for the Sharp MZ-2500 ("Super MZ", 1985) and the budget MZ-2520: Z80B at 6 MHz, 128-256 KB RAM, a text
+ graphics video controller with 640 x 400 and 320 x 200 modes and up to 256 colours, YM2203 sound, 3.5" 2DD floppies,
kanji ROM, and an MZ-80B / MZ-2000 compatible mode.

Sister project of [SharpMZ_MiSTer](https://github.com/alanswx/SharpMZ_MiSTer) (MZ-80K to MZ-2000), with which it
shares the T80, 8255, 8253, Z80 PIO, floppy and tape RTL.

## Status: Ys III boots from floppy and plays its intro (simulation)

In the Verilator simulation, with the real IPL and kanji ROMs:

- Power on with no media: the IPL's "loading error / Press F or C" screen, identical pixel for pixel to BubiZ-2500's
  (CSP core) at 400 lines and to MAME's at 200 lines (`make test`).
- **Ys III (Falcom, 1989)** from its two D88 disks: the IPL boots it, it loads, shows the Falcom copyright screen,
  fades it out through the 4096-colour palette and plays the scrolling intro with its YM2203 music; at frame 3000
  it is on the same intro page as BubiZ-2500 (`GAMES=1 make test` checks frame 1000).

- **Hoshikuzu-bako / Dust Box** disk magazine (1990-92): the IPL boots BASIC-M25 from the disk, which runs the
  issue's program; the 256-colour title screens of issues 1-7 and Special 1 match BubiZ-2500 pixel for pixel at
  frame 6000 (vol. 2 differs only in an animated raindrop caught at another moment).

The FPGA build fits (43% logic, 298/553 block RAMs, timing met at 85.9 MHz with +0.69 ns) with drives 1 and 2 in
the OSD; it has not been tried on a MiSTer yet.

What exists (`rtl/`): Z80 (T80 v350) with CSP's wait states; the MMU and its reset maps; 256 KB main RAM and the IPL
and the kanji ROM in SDRAM (the text raster fetches glyphs two cells ahead), ROMs from `boot.rom`; text CRTC and graphics controller with text VRAM, PCG and
graphics VRAM (16- and 256-colour modes, RMW window, clear, scroll, palette and priority, the 4096-colour board,
64-colour text); the interrupt block, 8253, 8255, Z80 PIO and keyboard; the MB8876 floppy controller with two D88
drives (wd1793.sv); the YM2203 (jotego jt03) and the beeper; the RP5C15 clock (from MiSTer's RTC); the joystick
port; a minimal Z80 SIO with the mouse on channel B; the data recorder (MZT images from the OSD, held in SDRAM, with
the MZ-2500 and the MZ-80B/2000 tape formats and APSS); the MZ-2000 / MZ-80B compatibility mode (boot mode in the
OSD, 4 MHz CPU, the VRAM windows of PIO port A, the 2000/80B text and graphics display). Not yet: tape recording,
RS-232C, drives 3-4: see [TODO.md](TODO.md).

MZ-2000 mode: set Boot mode to MZ-2000, load an MZT (e.g. MZ-1Z001 BASIC), reset and press C at the IPL menu. In the
sim (`--boot-mode 2000 --tape MZ-1Z001.mzt --type 600:c`) BASIC comes up "Ready" by frame 13500, pixel-identical to
BubiZ-2500 `-mz2000`.

ROMs: build `boot.rom` from your dumps with `tools/make_bootrom.sh IPL.ROM KANJI.ROM boot.rom` (CRCs in
docs/roms.md) and put it in `games/SharpMZ2500/` on the SD card; the sim reads `software/roms/extracted/` by default
or `--rom boot.rom`.

Research: hardware reference, ROM list, software sources and reference emulators in `docs/`. The reference
emulator is BubiZ-2500 (Takeda's EmuZ-2500 core with a headless mode), with MAME as a second opinion; both run
headless on macOS (docs/emulators.md).

Next: try it on a MiSTer, more titles from the MAME list, 256-colour modes, RTC.

## Layout

| Path | Content |
|---|---|
| `SharpMZ2500.sv` | MiSTer `emu` top: OSD, hps_io, PLL, video mixer |
| `SharpMZ2500.qsf`, `.qpf`, `.sdc`, `.srf` | Template_MiSTer's `Template.*` files, unmodified (`.qpf`: only the revision name). Don't edit them: update them from the template |
| `files.qip` | The core's source list (add files here, not in the IDE) |
| `rtl/mz2500.sv` | The machine (shared by the core and the simulation): CPU, waits, MMU, memories, I/O decode, small devices |
| `rtl/mz2500_video.sv` | Raster, text CRTC, graphics controller, VRAMs, mixer |
| `rtl/mz2500_int.sv`, `rtl/mz_pit8253.sv`, `rtl/mz2500_kbd.sv`, `rtl/dpram.sv` | Interrupt block, 8253, keyboard matrix, block RAMs |
| `rtl/T80_v350` | Z80: Sorgelig's MiSTer T80 v350 (`entity work.` added to its instances for GHDL). `rtl/T80` (v303), `rtl/i8255`, `rtl/i8254`, `rtl/z8420` are the SharpMZ copies, not used |
| `rtl/mz2500_fdc.sv`, `rtl/wd1793.sv`, `rtl/wd1793_mem.v` | Floppy: MB8876 wrapper, Sorgelig's WD1793 with FM-7_MiSTer's D77/D88 support (from SharpMZ_MiSTer) |
| `rtl/jt12/` | jotego jt12/jt49 (YM2203 = jt03), from FM-7_MiSTer, GPL-3 |
| `rtl/sdram.sv` | Sorgelig's SDRAM controller (from FM-7_MiSTer), refresh set for 85.9 MHz |
| `rtl/pll*` | 50 MHz to 85.909091 MHz |
| `sys/` | Template_MiSTer framework (do not edit) |
| `verilator/` | Headless simulation, regression tests ([README](verilator/README.md)) |
| `docs/` | [hardware](docs/hardware.md), [design](docs/design.md), [references](docs/references.md), [emulators](docs/emulators.md), [ROMs](docs/roms.md), [software](docs/software.md), [FPGA blocks](docs/fpga_blocks.md) |
| `tools/fetch_refs.sh` | Fetches the reference emulators and documents into `refs/`; `--roms DIR` copies and CRC-checks local ROMs |
| `tools/make_bootrom.sh` | Builds `boot.rom` (IPL + kanji) from ROM dumps, CRC-checked |
| `tools/mame_snap.lua` | MAME autoboot script: snapshot and RAM/VRAM dumps at frame N, for headless comparison |
| `refs/`, `software/` | Local only (gitignored): emulator sources, documents, ROMs, disk images. Their READMEs list every item and where it came from. |

## Getting the references

```
tools/fetch_refs.sh          # MAME driver, EmuZ-2500 (CSP) source, jt12, documents -> refs/
```

ROMs and disk images are copyrighted and are not in this repository and not downloaded by the script:
`software/README.md` lists what is needed and where it is archived. The core will load the ROMs from the SD card.

## Building

Quartus 17.0 Lite (as all MiSTer cores). Clean build every time:

```
rm -rf db incremental_db output_files
quartus_sh --flow compile SharpMZ2500        # -> output_files/SharpMZ2500.rbf
```

On a Mac, the Apple container scripts in `~/dev2/apple-containers-example` run the same flow
(`scripts/quartus-core-apple.sh /path/to/SharpMZ2500_MiSTer`). `build_id.v` is generated by `sys/build_id.tcl`
(pre-flow script) and is not committed. Quartus writes the assignments from `sys/*.tcl` into the `.qsf` during a
build; don't commit that (`git checkout SharpMZ2500.qsf`). The `.qsf`, `.sdc`, `.srf` and `sys/` are Template_MiSTer
master as of commit 3ea1134 (2026-08-26), byte for byte.

The bootstrap build: 8,964 ALMs (21 %), 636 kbit block RAM (11 %, all of it the framework), timing met
(clk_sys 85.90909 MHz, worst setup slack 0.53 ns in the framework's HDMI PLL domain); about 10 minutes in the Apple
container.

Simulation:

```
cd verilator
make && make test
./obj_dir_headless/Vtop --stop-at-frame 400 --screenshot 400   # -> out/frame_000400.png, the IPL screen
```

## Licence

GPL-3.0-or-later (see `LICENSE`). Third-party RTL keeps its own licence (T80: BSD-style; `sys/`: GPL; see the file
headers and docs/references.md). MAME and EmuZ-2500 are used as behavioural references only.
