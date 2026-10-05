# Verilator simulation

Headless simulation of the MZ-2500 core, organised like SharpMZ_MiSTer's `verilator/`: one harness binary that runs a
number of frames, types keys, writes PNG screenshots and logs a hash of every frame, plus a regression script.

```
make            # build ./obj_dir_headless/Vtop
make test       # run_tests.sh: build, then the regression tests (out/test/)
make netlist    # only the GHDL step (gen/*.v)
make clean
```

Requires `verilator` 5.x, `ghdl` 5.x with `synth` (Homebrew's `ghdl` has it) and `python3`.

## How it is built

- `sim.v` is the simulation top (`top`). It stands in for `SharpMZ2500.sv` and instantiates the same machine,
  `rtl/mz2500.sv`, so the core and the sim share all machine RTL. The C++ harness plays the part of hps_io.
- The machine RTL is SystemVerilog. The only VHDL leaf is the T80, shared with SharpMZ_MiSTer; it is converted by `ghdl synth --out=verilog`, one netlist per entity in `gen/`.
  GHDL fixes the generics at synthesis time, so the Makefile passes the same `-g` values as the RTL instance, and
  `rtl/mz2500.sv` leaves the generic map out under `` `ifdef VERILATOR ``. Keep the two in step.
- `fix_port_aliases.py` (from SharpMZ_MiSTer) restores port-alias assignments that ghdl's Verilog writer drops;
  VHDL identifiers that are Verilog keywords (`do`, `config`) get a `_v` suffix.
- PNGs are written with `stb_image_write.h` (public domain).

## Harness options

```
./obj_dir_headless/Vtop --help
  --lines 400|200        front-panel display switch (default 400: 24.86 kHz; 200: 15.98 kHz)
  --stop-at-frame N      exit after frame N (default 60)
  --type FRAME:TEXT      type TEXT from FRAME (PS/2 events through ps2_key, as hps_io)
  --type-rate P:R        frames per key press:release
  --screenshot N         PNG of frame N (repeatable); --dump-frames A:B; --dump-every K; --out DIR
  --frame-log FILE       frame,fb_hash,cpu_cycles,pc per frame (fb_hash = FNV-1a over the RGB888 picture)
  --trace-cpu FILE       PC at each M1; --trace-io FILE: each I/O write; --trace-from/--trace-to N
  --rom FILE             boot.rom (IPL at 0, kanji at 10000h); or --ipl FILE --kanji FILE
                         (default ../software/roms/extracted/IPL/IPL.ROM and KANJI/KANJI.ROM)
```

Frames are counted from the first full frame after reset and end when vertical blanking starts. A PNG is the active
picture as the core outputs it: 640x400 in 400-line mode, 640x200 in 200-line mode.

The ROMs go in through the same ioctl download port the MiSTer uses (one byte per 4 clocks, machine in reset), so
frame 0 starts after that.

Speed: about 2.3 frames per second (3.8 M clk_sys cycles per second of CPU) on an M4 Max: 400 frames, the IPL's first
screen, take 3 minutes. A `make fast` build at a reduced clk_sys, as SharpMZ has, or Verilator threads are options.

## Tests

`run_tests.sh` runs each test in parallel and compares against `tests/expected/`. `UPDATE=1 ./run_tests.sh` rewrites
the expected files (check the PNGs first).

| Test | Checks |
|---|---|
| `ipl_400` | real IPL, 400 lines, no media: frame 400 hash; the picture equals BubiZ-2500's screenshot pixel for pixel |
| `ipl_200` | the same at 200 lines, frame 450; equals MAME's 640x200 screenshot |

The tests need the ROMs (`software/roms/extracted/`, or `ROM=boot.rom make test`).

Planned, in TODO.md order: keyboard, floppy boot, graphics, sound and the MZ-80B/2000 modes.

## Comparing with a reference emulator

The plan (docs/emulators.md) is the one SharpMZ used with mz800emu: run the reference emulator headless to the same
point, save a screenshot and an instruction trace, and diff them against `--screenshot` and `--trace-cpu` here.
