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

## Milestone 1: the IPL's first screen in the sim, matching the reference emulator (done)

Goal: power on with the real `ipl.rom` and reach the IPL's first screen (boot menu / "Make ready" prompt), with the
CPU trace from reset matching the reference emulator for the first few thousand instructions.

- [x] Reference emulator runs headless: BubiZ-2500 (CSP core) `-headless N -screenshot`, MAME `-video none` + Lua
      (docs/emulators.md); golden IPL frames in refs/compare/
- [x] I/O trace from reset out of MAME (Lua read/write taps on the I/O space): the list of ports the IPL touches
      on the way to its first screen drove what was built
- [ ] PC trace from reset out of the reference (MAME debugger `trace`, or a harness around BubiZ's CSP core) and
      an instruction-by-instruction diff with `--trace-cpu`. Not needed to reach the screen; useful for timing
- [x] ROM loading: IPL (32 KB) and kanji ROM (256 KB) into block RAM through ioctl (boot.rom layout:
      `tools/make_bootrom.sh`), `--rom` / `--ipl` / `--kanji` in the sim harness
- [x] T80 at 6 MHz with CSP's waits: M1 +1, page waits (GVRAM/RMW/TVRAM/PCG), I/O waits (FDC, PIO, OPN, RTC),
      display-period WAIT for text VRAM/PCG and GVRAM
- [x] MMU: B4/B5 (read and write, auto-increment), B7 mode bits, IPL reset map, special reset (8255 PC1 rising: map
      00-07 + CPU reset; the IPL copies itself to RAM and restarts there this way), IPL reset (PC3 low 100 us);
      128 KB main RAM in block RAM
- [x] 8255 (E0-E3, own SV: mode word clears the outputs, port C bit set/reset), 8253 (`rtl/mz_pit8253.sv`, own SV;
      CLK0 31.25 kHz, CLK1 = OUT0, CLK2 = OUT1, F0-F3 gate pulses), Z80 PIO ports A/B for the keyboard (E8-EB,
      no PIO interrupts yet), keyboard matrix from PS/2 (`rtl/mz2500_kbd.sv`)
- [x] OPN register stub: C8/C9 register file, port B = mode/200-400-line switches (CSP 37h); no sound
- [x] Interrupt block C6/C7 (`rtl/mz2500_int.sv`, CSP semantics), IM 2 acknowledge, RETI detection; sources CRTC
      (graphics V-blank) and 8253 OUT0
- [x] Video (`rtl/mz2500_video.sv`): text CRTC registers, 80/40 columns, 25/20 rows, 8/16-line fonts from the kanji
      ROM, PCG (mono and 8-colour), attributes (blink, reverse), text window, vertical scroll; graphics controller
      registers, RMW window with REPLACE/PSET/compare read/latches, clear screen, 4-colour MMU remap; graphics display
      640x200x16, 320x200x16 (2 screens, priority), 640x400x4, 640x400x16 with SAD0/SAD1/SAD2/SLN1 and HSCRL;
      16-colour palette, priority, background colour, F6 mask; CPU-visible text/graphics blanking per CSP
- [x] MB8876 stub (status "not ready"), phone unit idle (CA = 30h: FFh makes the IPL loop powering it off),
      joystick idle (EF)
- [x] `ipl_400` / `ipl_200` tests: the "loading error / Press F or C" screen, identical pixel for pixel to BubiZ-2500's
      (400 lines) and MAME's (200 lines) screenshots. It appears at frame 381 here and about 372 in BubiZ.
- [ ] First Quartus build with the new machine (block RAM: kanji ROM 2 Mbit + main RAM 1 Mbit + GVRAM 1 Mbit)

## Milestone 2: a commercial title boots (done in the sim)

- [x] Ys III (Falcom) boots from its D88 disks to the copyright screen and the scrolling intro with music driver
- [x] Fixes found on the way: OPN port A read-back, 4096-colour palette, interrupt requests latched until acknowledged
      (a withdrawn request gave an acknowledge without a vector: CPU jumped through the FFh table entry), T80 v350
- [x] Harness: save/load state, RAM dump at a CPU cycle, layer switches, interrupt trace, WAV, `make fast`
- [ ] Hardware build that fits: the design needs more than the 553 M10K blocks with the kanji ROM in block RAM

## Phase 2: memory and MMU, complete

- [ ] All MMU pages: main RAM 00-1F (256 KB), graphics VRAM 20-2F, VRAM read-modify-write window 30-33 (CSP layout:
      32 KB per plane), IPL 34-37, text VRAM 38, kanji/PCG 39, dictionary 3A (bank port CE), phone ROM 3C-3F
- [ ] Special reset vs IPL reset maps; mode register B7 for the MZ-80B/2000 layouts
- [ ] Memory test program (assembled in `verilator/tests/`, loaded through a debug load path like SharpMZ's
      `direct_start`)

## Phase 3: video, text

- [x] 80/40 columns, 25/20 rows, attributes (reverse, blink) (milestone 1; untested beyond the IPL screen)
- [ ] 64 colours in 40 columns (text R00 CP = 00), text in 256-colour mode (dimmed colours)
- [x] PCG RAM, mono and 8-colour (milestone 1; untested)
- [ ] 40-column combine modes checked against CSP
- [x] Vertical scroll (R09), text window (milestone 1; untested)
- [ ] 200-line timing and the front-panel switch (OSD), 400-line timing values confirmed from the CRTC registers
- [x] Display-period WAIT for text VRAM/PCG (text CRTC blanking) and GVRAM (graphics blanking), page and I/O waits

## Phase 4: video, graphics

- [x] Graphics VRAM in block RAM, 4 planes read per 8-pixel group
- [x] Modes 03, 93, 14/15/94/95, 17/97 with split scroll (SAD0-2, SLN1) and HSCRL (milestone 1; untested)
- [ ] 256-colour modes 1D/9D/19/99 (palette from text R0A, background R0B/R0C, priority256)
- [ ] Windowed display, dot scroll in X and Y, text/graphics priority
- [x] Plane latches and compare read (BC-BF), the plane window pages 30-33, clear screen
- [x] 16-colour palette (CSP analogue monitor levels), priority bit, background colour, F6 mask
- [x] 4096-colour board (AE, OPN port A bit 2): Ys III fades through it
- [ ] Digital-monitor option, 256-colour `GGRRBBII`
- [ ] Tests: game title screens compared with the reference emulator

## Phase 5: keyboard

- [x] PS/2 to MZ-2500 matrix through the PIO, including KANA, GRAPH, HENKAN, MUHENKAN, function keys, keypad (untested)
- [ ] `kb_*` tests typing at the IPL / BASIC prompt (harness `--type`)
- [ ] Joysticks (port EF, Atari/MSX type) from MiSTer joystick 1/2

## Phase 6: floppy

- [x] `wd1793.sv`, `wd1793_mem.v` from SharpMZ_MiSTer, new `rtl/mz2500_fdc.sv`; MB8876 inverted bus at D8-DB
- [x] Drive select DC (with the OPN DRSEL swap), side DD, density DE latch; D88 via the track table, 2 drives
- [ ] Drives 3 and 4; density check against the D88 sector flag (CSP 2023)
- [ ] OSD S slots for D88 (and raw 2D/2DD if needed), write back
- [x] Harness `--fdd`/`--fdd-b`; Ys III boots to its intro
- [ ] Regression test for a disk boot (frame hash), OSD S slots in SharpMZ2500.sv

## Phase 7: sound

- [x] jt03 (YM2203) from jt12 (FM-7_MiSTer copy) at 2 MHz; port A output read back (the IPL does read-modify-write), port B switches; timers polled by Ys III
- [x] Beeper (8255 PC2) mixed in
- [ ] Volume levels and SSG/FM pitch against BubiZ `-wav`
- [x] `--wav` in the harness
- [ ] Frequency tests as SharpMZ's `beep_*`/`psg_*`

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

- [x] SDRAM controller (Sorgelig's, from FM-7_MiSTer) for the CPU; behavioural model in the sim
- [ ] Raster slot (kanji glyph prefetch) so the kanji ROM can leave block RAM
- [x] Main RAM 256 KB and the IPL in SDRAM, IPL loaded through ioctl_wait
- [ ] Kanji 256 KB, kanji2 128 KB, dictionary 256 KB, phone 16 KB in SDRAM
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
