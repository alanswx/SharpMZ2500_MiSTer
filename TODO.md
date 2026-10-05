# TODO

Phased plan for the MZ-2500 / MZ-2520 core. Each phase ends with a test in `verilator/run_tests.sh` (frame hash or
trace) and, where it makes sense, the same check against the reference emulator (docs/emulators.md). Hardware facts:
docs/hardware.md. Architecture: docs/design.md. Effort estimates are for part-time work and come from the first
feasibility study (SharpMZ_MiSTer `docs/mz2500.md`): about 17-26 weeks to "runs most of the MAME software list".

## Phase 0: bootstrap (done)

- [x] Repository, Template_MiSTer `sys/`, `SharpMZ2500.sv` top with placeholder OSD, `.qsf`/`.qpf`/`files.qip`
- [x] PLL: clk_sys 85.909091 MHz (24 x 3.579545 MHz: dot clocks /4 and /6, CPU and OPN by accumulator)
- [x] `rtl/mz2500.sv`: clock enables, 400/200-line raster with a test pattern, T80 running a stub program
- [x] Shared RTL copied from SharpMZ_MiSTer: T80, i8255, i8254, z8420 (in `files.qip`, only T80 instantiated)
- [x] Verilator: GHDL synth flow for the VHDL leaves, headless harness (PNG, frame log, CPU/IO trace, typing), `run_tests.sh`
- [x] Research: refs/ (MAME driver, CSP EmuZ-2500, documents), software/README.md, docs/hardware.md, references.md
- [x] First Quartus build of the skeleton
- [ ] Try the RBF on the MiSTer: test pattern in both line modes over HDMI and (200 lines) analogue

## Milestone 1: the IPL's first screen in the sim, matching the reference emulator

Goal: power on with the real `ipl.rom` and reach the IPL's first screen (boot menu / "Make ready" prompt), with the
CPU trace from reset matching the reference emulator for the first few thousand instructions.

- [ ] Reference emulator runs headless: screenshot at frame N and a PC trace from reset (docs/emulators.md)
- [ ] ROM loading: IPL (32 KB) and CG (2 KB) into block RAM from ioctl (hps_io index 0 / boot.rom), and from
      `--rom` / `--cg` in the sim harness
- [ ] T80 at 6 MHz with the M1 wait state; clock enable module `mz2500_clocks`
- [ ] MMU, minimal: page registers B4/B5, mode B7, IPL reset map (pages 34-37 at 0000-7FFF), main RAM in block RAM
      for now (128 KB fits while nothing else is there; move to SDRAM in the SDRAM phase)
- [ ] I/O decode skeleton with a trace of unhandled ports (`--trace-io` lists them)
- [ ] 8255 (E0-E3), 8253 (E4-E7), Z80 PIO (E8-EB) wired; OPN port B returning the mode and 200/400-line switches
      (stub OPN until the sound phase)
- [ ] Interrupt vector registers C6/C7, IM 2 acknowledge
- [ ] Text CRTC, enough for the IPL: 80 x 25 in 400-line mode, CG ROM glyphs, 8 colours, cursor
- [ ] `ipl_boot` test: trace equal to the reference for N instructions; screenshot compared by eye, then hashed

## Phase 2: memory and MMU, complete

- [ ] All MMU pages: main RAM 00-1F (256 KB), graphics VRAM 20-2F, VRAM plane window 30-33, IPL 34-37, text VRAM 38,
      kanji/PCG 39, dictionary 3A (bank port CE), phone ROM 3C-3F
- [ ] Special reset vs IPL reset maps; mode register B7 for the MZ-80B/2000 layouts
- [ ] Memory test program (assembled in `verilator/tests/`, loaded through a debug load path like SharpMZ's
      `direct_start`)

## Phase 3: video, text

- [ ] 80/40 columns, 25/20/12 rows, attributes (reverse, blink), 64 colours in 40 columns
- [ ] PCG RAM and combine modes
- [ ] Hardware scroll, text window
- [ ] 200-line timing and the front-panel switch (OSD), 400-line timing values confirmed from the CRTC registers
- [ ] VRAM wait states during display

## Phase 4: video, graphics

- [ ] Graphics VRAM in block RAM, 4 (8) planes read per 8-pixel group
- [ ] Modes: 640 x 400 x 4, 640 x 200 x 16 (2 screens), 320 x 200 x 16 (2 screens), 320 x 200 x 256
- [ ] Windowed display, dot scroll in X and Y, text/graphics priority
- [ ] Plane latches and compare read (BC-BF), the plane window pages 30-33
- [ ] Palettes: 16-colour digital, 256-colour `GGRRBBII` with plane enables, 4096-colour analogue (AE)
- [ ] Tests: game title screens compared with the reference emulator

## Phase 5: keyboard

- [ ] PS/2 to MZ-2500 matrix through the PIO, including KANA, GRAPH, HENKAN, MUHENKAN, function keys, keypad
- [ ] `kb_*` tests typing at the IPL / BASIC prompt (harness `--type`)
- [ ] Joysticks (port EF, Atari/MSX type) from MiSTer joystick 1/2

## Phase 6: floppy

- [ ] Copy `wd1793.sv`, `wd1793_mem.v`, `mz_fdc.sv` from SharpMZ_MiSTer; MB8876 inverted bus at D8-DB
- [ ] Drive select DC, side DD, density DE; 80-track 2DD (640 KB, 16 x 256-byte sectors), up to 4 drives
- [ ] OSD S slots for D88 (and raw 2D/2DD if needed), write back
- [ ] Harness `--fdd`/`--fdd-b`; tests: boot BASIC-M25 / a game disk to its title

## Phase 7: sound

- [ ] jt03 (YM2203) from jt12 (GPL-3, see docs/references.md) at 2 MHz; port A (mouse select) and port B (switches)
- [ ] Beeper (8255), mixer, volume levels against the reference emulator
- [ ] `--wav` in the harness; frequency tests as SharpMZ's `beep_*`/`psg_*`

## Phase 8: RTC

- [ ] RP5C15 at CC-CD (registers, banks, alarm), seeded from hps_io's RTC bus; interrupt through C6/C7
- [ ] Test: the IPL/BASIC clock shows the MiSTer time

## Phase 9: mouse

- [ ] Z80 SIO channel B (async receive only to start), serial mouse protocol (docs/hardware.md) from MiSTer's PS/2 mouse
- [ ] OPN port A mouse select line

## Phase 10: MZ-80B / MZ-2000 compatibility mode

- [ ] Boot mode switch in the OSD (OPN port B), 4 MHz CPU, MMU 80B/2000 maps, CRTC 2000/80B drawing (use
      SharpMZ_MiSTer `rtl/mz80b/mz80b.vhd` as the reference for the decode and display rules)
- [ ] Data recorder: copy `cmt.vhd`, `tape_image.sv`, `tape_ddr.sv`; APSS; MZT images in an S slot
- [ ] Tests: MZ-2000 tapes load through the 2500 IPL (SharpMZ's `software/mz2200` titles)

## Phase 11: SDRAM

- [ ] SDRAM controller (sorgelig-style, see docs/references.md), CPU slot plus raster slot
- [ ] Main RAM 256 KB, kanji 256 KB, kanji2 128 KB, dictionary 256 KB, phone 16 KB in SDRAM; ROMs loaded from SD
- [ ] Kanji glyph prefetch per text line into block RAM for the raster (FM-7_MiSTer did the same)
- [ ] Kanji and dictionary access through pages 39/3A and ports B8-B9, CE-CF; kanji on the text layer
- [ ] Sim model of the SDRAM in the harness (C++ side) so the sim keeps working

## Phase 12: OSD and MiSTer integration

- [ ] Final CONF_STR: ROM loading (boot0..3.rom or F entries; decide), drives, tape, boot mode, model 2500/2520
      (MZ-2520: `ipl2520.rom`, no data recorder, no 80B/2000 modes), RAM size, line mode, mouse, joysticks
- [ ] MGL files for hardware tests; port `tools/mister_test.py` / `tools/triage.py` from SharpMZ_MiSTer
- [ ] Release notes, docs for users (ROM file names and where to put them)

## Later / optional

- [ ] SASI HDD (MZ-1E30), EMM (MZ-1R37), MZ-1R12/1R13
- [ ] RS-232C on SIO channel A to the MiSTer UART
- [ ] Printer port (FE-FF) to the MiSTer UART (SharpMZ's `mz_printer.sv` and mister_printerd)
- [ ] Debug load path for the two debugger-injected titles in `software/` (Champion Pro-Wrestling Special, Flicky)
