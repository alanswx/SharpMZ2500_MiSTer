# Design

Architecture of the MZ-2500 / MZ-2520 core. Status: milestone 1 (the real IPL reaches its first screen in the
simulation; README.md). The CPU, MMU, waits, I/O decode, 8255, PIO, OPN/FDC stubs live in `rtl/mz2500.sv`; video in
`rtl/mz2500_video.sv`; the 8253, interrupt block and keyboard in their own files. The 8255, 8253 and PIO are new
SystemVerilog rather than the copied VHDL: they take one-clock bus strobes at the end of each cycle, which the VHDL
versions (enable-gated read/write levels) would see several times. Hardware facts are in [hardware.md](hardware.md); this file is about how
the core will be built.

## Goals and non-goals

- MZ-2500 (MZ-2511/2521/2531) and MZ-2520, booting the real IPL loaded from the SD card, running the MAME `mz2500_flop`
  software list from D88 images.
- MZ-80B / MZ-2000 compatibility modes as the real machine does them: the 2500's IPL switches the same hardware (MMU
  mode, CRTC mode, 4 MHz). Lower priority; SharpMZ_MiSTer already has MZ-80B and MZ-2000 models.
- Not planned at first: SASI HDD (MZ-1E30), EMM (MZ-1R37), RS-232C beyond the mouse, LAN boards, the MZ-2800/2861 (16-bit).

## Top level

```
SharpMZ2500.sv (emu)          hps_io, OSD, PLL, ROM download, SD image slots, video_mixer, audio
 └─ rtl/mz2500.sv             machine: everything the Verilator sim also runs (verilator/sim.v)
     ├─ mz2500_clocks         clock enables (CPU 6/4 MHz, OPN 2 MHz, 8253 31.25 kHz, dot 21.477/14.318 MHz)
     ├─ T80se                 Z80B (VHDL, shared with SharpMZ_MiSTer)
     ├─ mz2500_mmu            8 x 8 KB windows, page registers B4/B5, mode B7, IPL/special reset maps
     ├─ mz2500_int            interrupt vector registers C6/C7 (CRTC, 8253, printer, RTC), IM 2 acknowledge
     ├─ i8255 (E0-E3)         tape control, IPL/reset, beeper, 200/400 line
     ├─ i8253 (E4-E7)         timers (CLK0 31.25 kHz)
     ├─ z8420 PIO (E8-EB)     keyboard strobe/return
     ├─ mz2500_kbd            PS/2 -> MZ-2500 matrix (KANA, GRAPH, HENKAN, MUHENKAN, function keys)
     ├─ mz2500_crtc           text + graphics video controller (the bulk of the work)
     ├─ jt03 (YM2203)         FM + SSG, ports A/B (mouse select; mode and 200/400-line switches)
     ├─ mz2500_rtc            RP5C15, seeded from hps_io RTC
     ├─ mz_fdc / wd1793       MB8876 at D8-DE (inverted bus), 2DD D88, up to 4 drives
     ├─ cmt / tape_image      data recorder with APSS (MZ-80B/2000 signalling), MZT images
     ├─ mz2500_sio            Z80 SIO channel B for the mouse (later)
     └─ sdram                 main RAM, kanji, kanji2, dictionary and phone ROM
```

Module names under `rtl/` that don't exist yet are placeholders for the plan.

## Clocks

The MZ-2500 has a 24 MHz crystal (CPU 6 MHz = /4, OPN 2 MHz = /12; the 8253's 31.25 kHz comes from it) and a
21.477 MHz (6 x NTSC colour subcarrier) dot clock for 400-line mode, 14.318 MHz for 200-line mode.

| Clock | Value | From clk_sys 85.909091 MHz |
|---|---|---|
| clk_sys | 85.909091 MHz = 24 x 3.579545 | PLL from 50 MHz (`rtl/pll`, fractional) |
| Dot, 400 lines | 21.477 MHz | / 4, exact |
| Dot, 200 lines | 14.318 MHz | / 6, exact |
| CPU (MZ-2500 mode) | 6 MHz | accumulator (+6,000,000 per clk_sys), average exact, jitter one clk_sys |
| CPU (MZ-80B/2000 mode) | 4 MHz | accumulator |
| OPN | 2 MHz (jt03 cen = 2 MHz, or 4 MHz with its divider) | accumulator |
| 8253 CLK0 | 31.25 kHz | from the 2 MHz/1 MHz enables |
| SDRAM | clk_sys | same clock; SDRAM_CLK through altddio_out, as the usual MiSTer controllers |

An accumulator-generated CPU enable is what SharpMZ_MiSTer's `clkgen` does; it keeps one clock domain. Wait states
(one M1 wait at 6 MHz, VRAM waits during display) are added by holding `WAIT_n`, counted in CPU enables.

## Video

- One raster generator for both modes: 400 lines (864 x 448 dots, 24.86 kHz, 55.49 Hz) and 200 lines (896 x 262
  dots, 15.98 kHz, 60.99 Hz), from CSP and x1center.org measurements (hardware.md section 2). Text and graphics have
  separate display windows and blanking (text R03/R05/R07/R08; graphics GDEHS/GDEHE/GDEVS/GDEVE), and the CPU WAIT
  logic needs both.
- Follow CSP where MAME and CSP disagree (hardware.md section 13 lists 22 cases).
- Text and graphics layers are fetched in parallel per character cell and merged with the priority register.
- Graphics VRAM (128 KB, 4 planes x 32 KB) in block RAM, organised so one cycle reads all planes of an 8-pixel group.
- Text VRAM, PCG RAM and palette in block RAM. There is no separate character generator: the ANK fonts (8x8 at 6010h,
  8x16 at 6000h, the MZ-2000 font at 6018h, MZ-700 fonts) are in the kanji ROM (docs/roms.md), so the text raster
  reads the kanji ROM from the first milestone. Kanji glyphs come from SDRAM through a per-line prefetch into a small
  block RAM (FM-7_MiSTer had to do the same); the font region can stay in a block-RAM copy.
- Output: `video_mixer` with the scandoubler only in 200-line mode (400-line mode is already 24.86 kHz; analogue output
  needs `vga_scaler=1` or a 24 kHz monitor). HDMI goes through the framework scaler in both modes.

## Memory

| Item | Size | Where |
|---|---|---|
| Main RAM | 128 KB (256 KB max) | SDRAM |
| Graphics VRAM | 128 KB | block RAM (raster needs all planes every 8 dots) |
| Text VRAM, PCG, attributes | about 14 KB | block RAM |
| IPL | 32 KB | block RAM (loaded from SD at start, `boot.rom` style) |
| Kanji ROM | 256 KB | block RAM until the SDRAM phase (2.1 Mbit; the sim and the first builds), then SDRAM with the font region and a glyph prefetch in block RAM |
| Kanji2 128 KB, dictionary 256 KB, phone 16 KB | 400 KB | SDRAM, loaded from SD |

Final block RAM use about 1.5 Mbit of the DE10-Nano's 5.66 Mbit plus the framework's 0.64 Mbit; with the whole kanji
ROM in block RAM during bring-up about 3.6 Mbit, which still fits. ROMs are never embedded in the RBF (copyright): the menu
loads them from `games/SharpMZ2500/` (boot0.rom..boot3.rom or F entries; to be decided, see TODO).

A 6 MHz Z80 cycle is at least 500 ns, so the SDRAM serves the CPU in one slot and the kanji prefetch in another with
plenty of margin. Candidate controllers: sorgelig's `sdram.sv` family as used in the local FM-7_MiSTer, C64 and
Apple-IIgs cores (docs/references.md lists them with licences).

## Reuse from SharpMZ_MiSTer

SharpMZ_MiSTer (`../SharpMZ_MiSTer`) is the MZ-80K..MZ-2000 core. The MZ-2500 has an MZ-80B/2000 compatible mode, so these
parts carry over:

| SharpMZ_MiSTer file | Use here | Notes |
|---|---|---|
| `rtl/T80/*` | **copied** (`rtl/T80`) | Daniel Wallner / MikeJ, BSD-style. |
| `rtl/i8255/i8255.vhd` | **copied** | MikeJ / Philip Smart; port C bit set/reset needed by the tape and beeper. |
| `rtl/i8254/*` | **copied** | Philip Smart, GPL-3. Has a GHDL testbench in SharpMZ (`verilator/tests/tb_i8254.vhd`) to copy when wired. |
| `rtl/z8420/*` | **copied** | Nibbles Lab Z80 PIO ("partially compatible": port A output mode 0, port B input mode 0; no stated licence). Enough for the keyboard; needs the IM 2 daisy chain with the new interrupt block. |
| `rtl/wd1793.sv`, `rtl/wd1793_mem.v`, `rtl/mz_fdc.sv` | to copy in the floppy phase | Sorgelig (GPL-2+) with D88/D77 support from FM-7_MiSTer. Add 80-track 2DD, 4 drives, the DE density latch, inverted bus. |
| `rtl/cmt.vhd`, `rtl/tape_image.sv`, `rtl/tape_ddr.sv` | to copy in the tape phase | MZ-80B/2000 tape signalling and APSS; MZT images; tape buffer in DDR3. |
| `rtl/mz80b/mz80b.vhd` | reference only | MZ-80B/2000 decode and display rules for the MMU's 80B/2000 modes and the CRTC's 2000 drawing; on the 2500 those run through the 2500 MMU and CRTC, so it is not instantiated. |
| `rtl/direct_start.sv`, `rtl/mz_printer.sv` | maybe | Load-to-RAM debug path (useful for the two debugger-injected titles), printer to the MiSTer UART. |
| `verilator/` organisation, `fix_port_aliases.py`, `ps2_keys.h` | **copied** | GHDL synth flow and harness options. |
| `tools/triage.py`, `tools/mister_test.py` | later | Hardware test runner on the MiSTer. |

Licences: the core is GPL-3.0-or-later. GPL-2+ files (wd1793) are compatible. EmuZ-2500 (GPL-2) and MAME (BSD-3 for
this driver) are references for behaviour; don't translate their code line by line.

## New blocks from elsewhere

| Block | Source | Licence |
|---|---|---|
| YM2203 | jotego jt12 (`jt03`), already integrated in `../FM-7_MiSTer/rtl/jt12` | GPL-3 |
| RP5C15 | X68000_MiSTer `rtl/rtc/rp5c15.vhd` (closest fit, but no licence: ask the author), Suska RP5C15 (LGPL-2.1+), or written new (small). Not the MSX one (non-commercial clause). | docs/fpga_blocks.md |
| Z80 SIO | nothing reusable found; write a minimal channel B receiver + DTR for the mouse | |
| SDRAM controller | sorgelig-style `sdram.sv` from a local MiSTer core | GPL-2+/3 |

## Verification

1. Verilator sim first (`verilator/`), as SharpMZ did. Every milestone has a `run_tests.sh` test with an expected
   frame hash or trace.
2. Reference emulator side by side (BubiZ-2500 headless, MAME + Lua; docs/emulators.md): same ROMs, same disk, screenshot at a fixed frame and an
   instruction trace from reset. The IPL's first few thousand instructions are the first exit test.
3. Hardware on the MiSTer last, with the same images.
