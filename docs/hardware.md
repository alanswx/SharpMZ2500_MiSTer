# MZ-2500 hardware reference

The implementation reference for the core. Register-level detail comes from reading the two emulators' source:

- **CSP**: Takeda Toshiya's EmuZ-2500, official source of 2026-01-01 (`refs/csp/takeda/source/src/vm/mz2500/`). Treated as the primary
  truth. Same code as the core of BubiZ-2500.
- **MAME**: `src/mame/sharp/mz2500.cpp` at MAME commit 395cc09e (2026-10-05) (`refs/mame/mz2500.cpp`).
- **iomap**: 紅茶羊羹 (youkan700)'s I/O map, `http://www.maroon.dti.ne.jp/youkan/mz2500/iomap.html` (`refs/docs/maroon/iomap.html`,
  plain text in `iomap.txt`). It was written from hardware tests and agrees with CSP almost everywhere (its author contributes to CSP).
  An English machine translation is on eaw.app as `MZ2500_IO_Map.pdf` (`refs/docs/eaw/`).
- **disp**: the same author's video overview, `disp.html`. **timing**: `videotiming.html` (x1center.org measurements).

Sections give their sources. Where MAME and CSP disagree, it is flagged **[MAME≠CSP]**. Section 13 lists every disagreement.

Notation: `R`/`W` = read/write; bit 7 is the MSB; "active low" means 0 = asserted.

## 1. Overview

| Item | Value | Source |
|---|---|---|
| CPU | Z80B, 6 MHz (24 MHz / 4) in MZ-2500 mode; 4 MHz in MZ-80B/2000 modes | CSP `CPU_CLOCKS`, MAME `24_MHz_XTAL / 4` |
| Main RAM | 128 KB standard (pages 00-0F), 256 KB with expansion (10-1F) | iomap B5h |
| Graphics VRAM | 64 KB standard (pages 20-27), 128 KB with MZ-1R27 (28-2F) | iomap, disp |
| Text VRAM | 6 KB (page 38: char 2 KB, attribute 2 KB, char-high 2 KB) | CSP `tvram[0x1800]` |
| PCG RAM | 8 KB, four 2 KB banks PCG0-PCG3 (page 39) | CSP, MAME |
| IPL ROM | 32 KB (pages 34-37) | |
| Kanji ROM | 256 KB, JIS level 1 + 2, also holds the ANK fonts (window at page 39, bank port CF) | |
| Dictionary ROM | 256 KB (page 3A, bank port CE). Standard on the MZ-2531, MZ-1R28 option otherwise | |
| Phone ROM | 16 KB (MZ-1E26), pages 3C-3F (32 KB window, upper 16 KB reads FF) | CSP `phone[0x8000]` |
| Sound | YM2203 (OPN) at 2 MHz + 1-bit beeper | |
| FDC | MB8876 (inverted data bus), 3.5" 2DD 640 KB, up to 4 drives | |
| Others | i8255, i8253, Z80 PIO (keyboard), Z80 SIO (RS-232C, mouse), RP5C15 RTC, 2 joystick ports, Centronics printer, built-in data recorder (not on the MZ-2520) | |

Models: MZ-2511 (1 drive), MZ-2521 (2 drives), MZ-2531 (Super MZ V2: dictionary ROM, TV control port AF), MZ-2520 (no data recorder,
no MZ-80B/2000 modes, own IPL `ipl2520.rom`, 8-way DIP switch, see 10.10).

## 2. Clocks and timing

| Clock | Value | Source |
|---|---|---|
| Crystal | 24 MHz | MAME |
| CPU | 6 MHz (/4); 4 MHz in 80B/2000 boot modes | CSP `config.boot_mode ? CPU_CLOCKS_LOW : CPU_CLOCKS` |
| OPN φM | 2 MHz (/12) | MAME `24_MHz_XTAL / 12`, CSP `initialize_sound(rate, 2000000, ...)`, iomap |
| 8253 CLK0 | 31.25 kHz (24 MHz / 768) | MAME, CSP `set_constant_clock(0, 31250)` |
| SIO baud clocks | (4 MHz / 13) / 2^n, n = 0..7 (307 kHz .. 2.4 kHz) | CSP serial.cpp, MAME `sio_setup_w`, iomap CDh |
| FDC | MB8876 at 1 MHz (8 MHz / 8, via MB4107 VFO) | MAME |
| RTC | 32.768 kHz | MAME |
| Dot clock, 400 lines (24 kHz, CRT switch "H") | 21.47727 MHz (6 x 3.579545) | disp, timing |
| Dot clock, 200 lines (15 kHz, CRT switch "L") | 14.31818 MHz (4 x 3.579545) | disp, timing |

Video timing (x1center.org via `videotiming.html`; CSP uses the same numbers: `FRAMES_PER_SEC 55.49`, `LINES_PER_FRAME 448`,
`CHARS_PER_LINE 108` for 400 lines and 60.99 / 262 / 112 for 200 lines):

| | 15 kHz (200 lines) | 24 kHz (400 lines) |
|---|---|---|
| Dot clock | 14.318180 MHz | 21.477250 MHz |
| H total | 896 dots (112 chars) = 62.58 us, 15.980 kHz | 864 dots (108 chars) = 40.23 us, 24.858 kHz |
| H display / blank | 664 / 232 dots (as measured) | 664 / 200 dots |
| V total | 262 lines, 60.993 Hz | 448 lines, 55.486 Hz |
| V display / blank | 200 / 62 | 400 / 48 |
| CPU clocks per line | 375.47 | 241.37 |
| GVRAM CPU access window per line (display period) | memory write + 91 clocks + memory write | memory write + 50 clocks + memory write |

The 664-dot "display" figure is the measured active span; the visible bitmap is 640 dots. MAME's screen setup (`set_raw(42.954545 MHz / 2,
748, 0, 640, 480, 0, 200)`) is a placeholder **[MAME≠CSP]**.

### Wait states (CSP `memory.cpp`, `mz2500.cpp`; iomap B5h table)

| Access | 6 MHz (MZ-2500 mode) | 4 MHz (80B/2000 modes) |
|---|---|---|
| Every M1 (opcode fetch) | +1 | 0 |
| GVRAM pages 20-2F | +1 | 0 |
| RMW pages 30-33 | +2 | +1 |
| Text VRAM page 38 | +1 | 0 |
| PCG / kanji page 39 | +2 | 0 |
| I/O D8-DF (FDC), E8-EB (PIO) | +1 (only in 2500 mode) | 0 |
| I/O C8-C9 (OPN) | +1 | +1 |
| I/O CC (RTC) | +3 | +3 |

Display-time wait: an access to text VRAM/PCG (pages 38/39) while the **text** CRTC is in its display period (not H- or V-blank), or to
GVRAM/RMW (20-33) while the **graphics** controller is in its display period, asserts WAIT until the next blanking. The two blank
signals are separate (CSP keeps `hblank_t/vblank_t` and `hblank_g/vblank_g`). iomap: GVRAM pages may not be used for M1 fetches.
MAME has no wait states at all **[MAME≠CSP]**.

CSP's per-line blank events (`crtc.cpp event_vline`): with `cpc` = CPU clocks per character (CPU clock / fps / lines / chars per line):

- text H display from `cpc * (R07 & 0x7F) - 2` to `cpc * (R08 & 0x7F) + 6` clocks after line start (if R07 < R08, else always blank);
- graphics H display from `cpc * (GDEHS + 10) - 2` to `cpc * (GDEHE + 10) + 4` (if GDEHS < GDEHE);
- text V display: starts at line `R03 * k`, ends at line `R05 * k` (k = 2 in 400-line mode, 1 in 200-line mode);
- graphics V display: starts at line GDEVS, ends at line GDEVE (line counter 0..447 / 0..261). If start == end, always blank.

## 3. Memory map and MMU

Source: CSP `memory.cpp`, MAME `bank_window_map`, iomap B4h/B5h.

The 64 KB Z80 space is eight 8 KB windows (window n = n*2000h..n*2000h+1FFFh). Each window holds a 6-bit page number into a
512 KB physical space (page p at p*2000h).

| Port | R/W | Function |
|---|---|---|
| B4h | W | `MRSEL` (bits 2-0): window index for B5h |
| B4h | R | current index (CSP; MAME too) |
| B5h | W | page number (bits 5-0) for window `MRSEL`; then `MRSEL = (MRSEL+1) & 7` |
| B5h | R | page of window `MRSEL`; then `MRSEL++` |
| B7h | W | mode register, bits 1-0 (MZ-80B/2000 compatibility, see 3.3). MAME ignores it **[MAME≠CSP]** |

### 3.1 Physical pages

| Page | Contents | Notes |
|---|---|---|
| 00-0F | main RAM 128 KB | |
| 10-1F | expansion RAM 128 KB | CSP always fits 256 KB |
| 20-2F | graphics VRAM, direct, one plane per page pair | layout below |
| 30-33 | VRAM read-modify-write (RMW) window | through the graphics controller, see 5.6 |
| 34-37 | IPL ROM 32 KB | read only |
| 38 | text VRAM: 0000-07FF char, 0800-0FFF attribute, 1000-17FF char-high, 1800-1FFF unmapped (reads FF in CSP; MAME has RAM) | |
| 39 | 0000-07FF PCG0, or the kanji ROM when port CF bit 7 = 1 (2 KB bank `CF & 7F`); 0800 PCG1; 1000 PCG2; 1800 PCG3 | kanji is read only |
| 3A | dictionary ROM, 8 KB bank `CE & 1F` | read only |
| 3B | nothing (reads FF) | |
| 3C-3F | phone ROM (MZ-1E26), 16 KB in a 32 KB window | read only |

GVRAM page mapping (iomap "B/R/G/I", CSP `ofs_table`, MAME linear `cgram`):

| Pages | Plane |
|---|---|
| 20-21 | B, standard VRAM (16 KB) |
| 22-23 | R |
| 24-25 | G |
| 26-27 | I |
| 28-29 | B, extended VRAM (MZ-1R27) |
| 2A-2B | R, extended |
| 2C-2D | G, extended |
| 2E-2F | I, extended |

So each plane is 32 KB: graphics-controller address 0000-3FFF = standard VRAM, 4000-7FFF = extended VRAM (CSP stores plane B
as `vram[0x0000..0x7FFF]` with B-std at 0000 and B-ext at 4000; MAME stores standard B,R,G,I at 0000/4000/8000/C000 and the extended
set at +10000h; the CPU view is identical).

**4-colour mode** (graphics mode 03h/93h with bit 4 = 0, i.e. `(R0E & 0x13) == 0x03`, CSP `is_4color_mode`): pages 28-29 (B-ext) and 2A-2B
(R-ext) are redirected to the standard G and I planes (24-25, 26-27); direct accesses to G/I and to G-ext/I-ext are ignored (CSP maps
them to dummy). Software sees a 640x400 16-colour layout without G/I planes (iomap note). CSP re-applies the maps when R0E bit 4
changes (`refresh_map`).

### 3.2 Reset maps

| Reset | Windows 0-7 | Trigger |
|---|---|---|
| IPL reset (power on, IPL button) | 34 35 36 37 04 05 06 07 | power-up; 8255 PC3 (BST) held low (CSP: falling edge + 100 us, then full VM reset) |
| "Special"/work-RAM reset | 00 01 02 03 04 05 06 07 | 8255 PC1 (NST) rising edge: map reset + CPU reset only (CSP `special_reset`, MAME `reset_banks(WRAM_RESET)` + reset pulse) |

MAME times the IPL reset with a 100 Hz timer after PC3 goes low; CSP uses 100 us.

### 3.3 MZ-80B / MZ-2000 compatibility (CSP only)

- B7h bits 1-0 = `mode`: 0 = MZ-2500, 2 = MZ-80B, 3 = MZ-2000. On a 0→1 transition of bit 1, all eight windows are set to 00-07.
- In mode 3 (MZ-2000), Z80 PIO port A bits 7-6 (`DISP`, `HCLG`) select VRAM like the MZ-2000: `0x80` maps GVRAM (32 KB bank
  `vram_page`) at C000-FFFF; `0xC0` maps text VRAM at D000-DFFF.
- In mode 2 (MZ-80B), `0x80` maps text VRAM at D000-DFFF and GVRAM (page `vram_page & 1`) at E000-FFFF; `0xC0` maps them at 5000-5FFF and
  6000-7FFF.
- While text register 0Fh bits 1-0 (MOD) = 1 (2000) or 2 (80B), writes to F4-F7 are MZ-2000/80B registers (F4 background colour / VRAM
  page, F5 text colour, F6 VRAM mask, F7 page) instead of the 2500 CRTC.
- CPU 4 MHz, different wait table (section 2). CSP draws these screens with `draw_screen_2000` / `draw_screen_80b`; the MZ-2000 font is the
  kanji ROM's ANK set at 6018h (one 8-byte glyph every 32 bytes, CSP `CRTC::reset`).
- The boot mode is a front-panel switch read through OPN port B bits 5/4 (section 7).

## 4. I/O map

All ports decode A7-A0 only unless marked "16-bit" (then A15-A8 carry an index; use `OUT (C),r` with B = index).

| Port | R/W | Device | Function | Sources |
|---|---|---|---|---|
| 60-63 | R/W | W3100A LAN (DIY, optional) | | CSP option |
| 90-9C | R/W | CMU-800 (optional) | | CSP option |
| 98-99 | R/W | MZ-1E35 ADPCM (Y8950, optional) | | iomap |
| 9A-9F | R/W | MZ-1E32 parallel I/F + 24x24 kanji ROM (optional) | | iomap, CSP |
| A0-A3 | R/W | Z80 SIO (when CD bit 7 = 0): A0 ch A data, A1 ch A ctrl, A2 ch B data, A3 ch B ctrl | RS-232C / mouse | all |
| A4-A5, A8-A9 | R/W | MZ-1E30 SASI + BIOS ROM (optional) | | iomap, CSP |
| AC-AD | R/W | MZ-1R37 640 KB EMM (optional, 16-bit) | | iomap, CSP |
| AE | W | 16-bit: 4096-colour palette (MZ-1M10 board) | 5.8 | all |
| AF | R/W | TV control (MZ-2531 only) | | iomap |
| B0-B3 | R/W | Z80 SIO (when CD bit 7 = 1) | | all |
| B4, B5 | R/W | MMU | 3 | all |
| B7 | W | MMU mode | 3.3 | CSP |
| B8-B9 (BA-BB) | R/W | MZ-1R13 kanji/dictionary board (optional) | 9 | CSP, MAME **[differ]** |
| BC-BF | R/W | graphics controller | 5.5 | all |
| C6, C7 | W | interrupt controller | 6 | all |
| C8, C9 | R/W | YM2203 address/status, data | 7 | all |
| CA | R/W | MZ-1E26 phone unit | reads 30h (CSP and MAME) | iomap |
| CC | R/W | 16-bit: RP5C15, A11-A8 = register | 10.4 | all |
| CD | W | SIO address select + baud rates | 10.5 | all |
| CE | W | dictionary ROM bank (bits 4-0) | 3 | all |
| CF | W | kanji ROM / PCG0 select (bit 7) + kanji bank (bits 6-0) | 3 | all |
| D8-DB | R/W | MB8876: D8 status/command, D9 track, DA sector, DB data (data bus inverted) | 10.8 | all |
| DC | W | drive select / motor | 10.8 | all |
| DD | W | side select | 10.8 | all |
| DE | W | density | 10.8 | all |
| E0-E3 | R/W | i8255 | 10.1 | all |
| E4-E7 | R/W | i8253 | 10.2 | all |
| E8-EB | R/W | Z80 PIO: E8 port A data, E9 A ctrl, EA port B data, EB B ctrl | 10.3 | all |
| EF | R/W | joystick | 10.7 | all |
| F0-F3 | W | 8253 GATE0/GATE1 low pulse | 10.2 | all |
| F4-F7 | R/W | text CRTC | 5.2 | all |
| F8-FA | R/W | MZ-1R12 (32 KB battery RAM, optional) | | CSP |
| FE, FF | R/W | printer | 10.9 | CSP, iomap |

Unmapped ports read FFh (MAME `unmap_value_high`, CSP default).

## 5. Video

Two independent controllers: a **text CRTC** (F4-F7, own register file, owns the raster timing registers and the palette/priority
registers) and a **graphics controller** "GDE" (BC-BF, VRAM drawing logic, graphics window/scroll). The text layer is drawn over the
graphics layer; palette priority bits can put graphics colours on top.

### 5.1 Text VRAM format (page 38)

Per character cell at address `a` (0-7FF):

| Byte | Bits | Meaning |
|---|---|---|
| `tvram1[a]` (0000+a) | 7-0 | character code: kanji ROM address A10-A3, or PCG character number |
| `attrib[a]` (0800+a) | 7 `BL` | blink (about 1 Hz; CSP toggles every 500 ms) |
| | 6 `RV` | reverse |
| | 5-4 `S` | monochrome PCG select: 00 PCG0, 01 PCG1, 10 PCG2, 11 PCG3 |
| | 3 `P` | 1 = 8-colour PCG (PCG1 = B, PCG2 = R, PCG3 = G) |
| | 2-0 | colour GRB (G = bit 2, R = bit 1, B = bit 0) for kanji / monochrome PCG |
| `tvram2[a]` (1000+a) | 7 `K` | 1 = kanji ROM, 0 = PCG |
| | 6 `L` | 0 = level 1 (kanji ROM 00000-1FFFF), 1 = level 2 (20000-3FFFF) |
| | 5-0 | kanji ROM address A16-A11 |

Glyph source (CSP `draw_80column_font`, `sel = (tvram2 & 0xC0) | (attr & 0x38)`):

| sel | Source |
|---|---|
| attr bit 3 = 1 | 8-colour PCG: pattern bits from PCG1 (B), PCG2 (R), PCG3 (G), colour = GRB of the three bits, 0 = transparent |
| 00h, 40h | PCG0 |
| 80h | kanji ROM level 1 (`kanji + 0x00000`) |
| C0h | kanji ROM level 2 (`kanji + 0x20000`) |
| x0h with S = 01/10/11 | PCG1/2/3 |

Glyph address: 8-line font (F7 bit 0 = 1): `code = t1 << 3` (+ `(t2 & 3F) << 11` for kanji), 8 bytes, each line drawn twice in 400-line
mode. 16-line font (F7 bit 0 = 0): `code = (t1 & FE) << 3` (+ kanji high bits), 16 consecutive bytes. Text glyph bits are MSB = leftmost
(GVRAM is the opposite). Attribute order: blink, then reverse, then colour (iomap). Blink with reverse shows a solid colour cell.

Kanji ROM layout (iomap; value to write into tvram2:tvram1 is `addr / 8`):

| Character set | ROM address | tvram2:tvram1 |
|---|---|---|
| non-kanji JIS row 21-2F | 0000h + ((JIS_H-21h)*60h + (JIS_L-20h))*20h | 8000h + ((JIS_H-21h)*60h + (JIS_L-20h))*4 |
| JIS level 1 | 8000h + ... | 9000h + ((JIS_H-30h)*60h + (JIS_L-20h))*4 |
| JIS level 2 | 20000h + ... | C000h + ((JIS_H-50h)*60h + (JIS_L-20h))*4 |
| ANK 8x16 | 6000h + ASCII*20h | 8C00h + ASCII*4 |
| ANK 8x8 | 6010h + ASCII*20h | 8C02h + ASCII*4 |
| MZ-2000 CG | 6018h + ASCII*20h | 8C03h + ASCII*4 |
| MZ-700 CG 00-7F | 4400h + code*8 | 8880h + code |
| MZ-700 CG 80-FF | 5C00h + ... | 8B80h + (code-80h) |

A 16x16 kanji occupies 32 bytes: left half 16 bytes, right half 16 bytes, so a kanji uses two consecutive cells (addresses `x*4` and
`x*4+2`). The ANK fonts are inside the kanji ROM, which is why CSP never loads `CG.ROM` (see roms.md).

### 5.2 Text CRTC ports (F4-F7)

| Port | R/W | Function |
|---|---|---|
| F4 | W | register index (no auto-increment) |
| F4-F7 | R | bit 0 `VB` (0 = text V-blank), bit 1 `HB` (0 = text H-blank); others 0 (CSP: `(vblank_t?0:1) | (hblank_t?0:2)`). MAME reads the screen's blank state **[MAME≠CSP: source signal]** |
| F5 | W | register data |
| F6 | W | graphics output mask: bit 0 `BE` (B, and I in 16-colour mode), bit 1 `RE`, bit 2 `GE`, bit 3 `MG` (mono output only). CSP: `cg_mask = (d & 7) | (d & 1 ? 8 : 0)`. MAME stores it and does not use it |
| F7 | W | bit 0 `C`: 1 = 8-line font (each line doubled in 400-line mode), 0 = 16-line font |

### 5.3 Text CRTC registers

| Reg | Bits | Meaning | Standard / reset |
|---|---|---|---|
| 00 | 4 `K` | 1 = 20 rows (character height 10/20 lines: blank lines below each glyph), 0 = 25 rows (8/16) | |
| | 3-2 `CP` | text function: 00 = 40-column 64 colours (screen 1 colour → RGB bit 2, screen 2 → bit 1); 01 = screen 1 only (use for 80 columns); 10 = screen 2 only; 11 = screens 1 + 2 overlaid, screen 1 in front | |
| | 1 `WM` | 0 = graphics shows through transparent text; 1 = background colour shows (graphics only where its palette priority is high). Only inside the text window | |
| | 0 `G16` | 1 = graphics 16 colours / text 8 colours; 0 = graphics 256 colours / text 64 colours (text then dimmed, see disp) | |
| 01, 02 | 02 bits 2-0 : 01 | text start address SA (0-7FF, wraps) | 0 |
| 03 | 7-0 | text V display start (SL), in 2-line units at 400 lines | 38 (200) / 17 (400) |
| 05 | 7-0 | text V blank start (EL) | 238 (200) / 217 (400) |
| 07 | 6-0 | text H display start column (SC) | 80 col: 11 (200) / 9 (400); 40 col: 10 / 8 |
| 08 | 6-0 | text H blank start column (EC) | 80 col: 91 / 89; 40 col: 90 / 88 |
| 09 | 3-0 | vertical line scroll VD (0-7 in 25-row mode, 0-9 in 20-row); in 2-line units at 400 lines (CSP `vd = (R09 & 0F) << 1`) | |
| 0A | 5-0 | 256-colour mode: low bit of each output component, 2 bits each: bits 1-0 BIC, 3-2 RIC, 5-4 GIC: 00 = I0 plane (pixel bit 7), 01 = I1 (bit 3), 10 = 1, 11 = 0 | |
| 0B, 0C | 0C bit 0 : 0B | background colour, 9 bits GGG RRR BBB (0B bits 7-6 = G1-0, 5-3 = R, 2-0 = B; 0C bit 0 = G2). In 16-colour mode the MSBs (0C b0 = G, 0B b5 = R, 0B b2 = B) and 0B b0 = I form an IGRB code | |
| 0F | 3 `200` | 1 = 200-line (15 kHz) timing, 0 = 400-line; must match the CRT switch; set by the IPL | |
| | 2 | reads/writes as 1 (iomap) | |
| | 1-0 `MOD` | 00 = MZ-2500, 01 = switch to MZ-2000 display, 10 = MZ-80B, 11 = lock in MZ-2500 mode. Once MOD ≠ 0, later writes keep the old MOD bits (CSP) | |
| 80-8F | 4 `PR` | palette entry n: 1 = this graphics colour is in front of text | identity, PR = 0 |
| | 3-0 | colour code IGRB for graphics palette code n | |

CSP reset values: R03 = 38/17, R05 = R03 + 200, R07 = 11/9, R08 = R07 + 80; palette n = n. The 4096-colour board register is separate (AE).
CSP has a hack: if R03/R05 are written as 26h/EEh by code at PC = C27Eh in 400-line mode, it substitutes 11h/D9h ("kugyokuden").

MAME describes R00 bit 1 as "related to the transparent pen" and implements line height, 40-column modes and the window; it
calculates the window with fixed offsets (`x_offs` 64/72/80/88, `y_offs` 34/76) instead of the CSP formulas below **[MAME≠CSP]**.

Text display window in screen pixels (CSP `draw_text`, 640x400 output):

- 400-line: `SL = (R03 - 17) * 2`, `EL = (R05 - 17) * 2`; 80 col `SC = R07 - 9`, `EC = R08 - 9`; 40 col `SC = R07 - 8`, `EC = R08 - 8` (columns of 8 dots).
- 200-line: `SL = (R03 - 38) * 2`, `EL = (R05 - 38) * 2`; 80 col `R07 - 11`, 40 col `R07 - 10`.
- Outside the window the text is transparent (graphics always shows there, regardless of WM).

Layout: 80 columns use Z80 PIO port A bit 5 (`CH80`) = 1; 40 columns have two text screens, screen 2 at `address ^ 400h` (CSP `src2 = src1
+ 0x400`, wrapping at 7FFh). Each text row is 16 output lines (400-line mode), or 20 in 20-row mode; in 20-row mode CSP starts the first row
at output line 2 (`line = (R00 & 0x10) ? 2 : 0`) and the extra lines are blank but take the attributes (disp: only reverse is visible). The 64-colour mode combines screen 1 (bit 2 of each component) and screen 2 (bit 1); a
pixel is transparent only if both are.

### 5.4 Graphics modes (graphics register 0Eh)

| Bit | Name | Meaning (iomap) |
|---|---|---|
| 7 | EX | 1 = OR 4000h into every display fetch (show extended VRAM without changing scroll registers). Ignored at 640x400 |
| 4 | 4C | 0 = 4-colour mode (640x400 only), 1 = 16/256 colours |
| 3 | 256C | 1 = 256 colours (both 320-dot screens combined) |
| 2 | V200 | 1 = 200 lines, 0 = 400 lines |
| 1 | H640 | 1 = 640 dots, 0 = 320 dots |
| 0 | PRI | 320x200x16 two-screen priority: 0 = screen 0 behind, 1 = screen 0 in front; set 1 in other modes |

Values handled (CSP `draw_cg`; MAME `draw_cg_screen`):

| R0E | Mode | CSP | MAME |
|---|---|---|---|
| 00 | off | yes | yes |
| 03 | 640x400, 4 colours (B,R planes; G/I = upper half) | yes | "very preliminary" |
| 93 | 640x400, 16 colours (needs extended VRAM) | yes | no |
| 14 / 15 | 320x200x16, two screens, screen 1 / screen 0 in front | yes | yes |
| 94 / 95 | same, extended VRAM | yes | no |
| 17 / 97 | 640x200x16 (standard / extended) | yes | yes |
| 1D / 9D | 320x200, 256 colours | yes | 1D only |
| 19 / 99 | 320x400, 256 colours | yes | no |

Pixel format: 1 bit per plane per pixel, **LSB = leftmost pixel** (opposite to text glyphs). A 16-colour pixel is `B | R<<1 | G<<2 | I<<3`
(IGRB). In 320-dot modes each pixel is doubled to 640 output dots; 200-line graphics is line-doubled in 400-line output.
Screen 1 of the 320-dot modes is at `address ^ 2000h` (CSP `subplane`); in 640x200 mode the second page is `^ 4000h`.

256-colour mode (CSP `draw_320x200x256screen`): the pixel byte is
`B0 | R0<<1 | G0<<2 | I0<<3 | B1<<4 | R1<<5 | G1<<6 | I1<<7`, where `x1` = screen at `addr` and `x0` = screen at `addr ^ 2000h`, each
plane enabled by its bit of R18 (and by F6). Output colour is 3 bits per component: B = (bit 4, bit 0, low bit), R = (bit 5, bit 1, low),
G = (bit 6, bit 2, low), the low bit chosen by text R0A (I0 = bit 7, I1 = bit 3, 1, 0). Palette/priority apply to screen 1 only
(`priority256[c16 | i]` uses the upper nibble).

### 5.5 Graphics controller ports and registers (BC-BF)

| Port | R/W | Function |
|---|---|---|
| BC | W | register index: bits 4-0 = REGNO (00-18h), bit 7 `INC` = after each BD write, increment only the low 2 bits of REGNO |
| BC | R | direct read: last latched B plane byte; select read (R07 bit 4): compare result |
| BD | W | register data |
| BD | R | direct read: R latch; select read: bit 7 = 1 in graphics display period (0 = V-blank), bit 0 = clear-in-progress flag |
| BE | R | G latch (undefined in select read) |
| BF | R | I latch |

| Reg | Meaning |
|---|---|
| 00-03 | pattern registers B, R, G, I (RMW data masks). Reset FFh |
| 04 | colour register: bits 3-0 I G R B (which planes receive data) |
| 05 | bits 7-6 function: 00 REPLACE, 01 PSET, 10 clear screen; bits 3-0 plane select I G R B |
| 06 | bit mask (REPLACE). Reset FFh |
| 07 | bit 4 = select (compare) read; bits 3-0 compare colour IGRB; bits 1-0 = direct-read plane (00 B, 01 R, 10 G, 11 I) |
| 08, 09 | GDEVS: graphics V display start line, 9 bits (09 bit 0). Writing 08 clears 09 |
| 0A, 0B | GDEVE: V display end line. Writing 0A clears 0B. Reset 400 (or 200) |
| 0C | GDEHS, bits 6-0, in 8-dot (640) / 4-dot (320) units, 0-50h |
| 0D | GDEHE. Reset 80 |
| 0E | mode, 5.4 |
| 0F | bits 2-0 HSCRL: 0-7 white(blank) pixels inserted at the left (screen 0 only; doubled in 320-dot modes: CSP `HDSC <<= 1` when R0E bit 1 = 0) |
| 10, 11 | SAD0: display start address (11 bits 6-0 : 10) |
| 12, 13 | SAD1: wrap address; after fetching SAD1 the next fetch is 0000 |
| 14, 15 | SAD2: display address after the split line |
| 16, 17 | SLN1: split line (9 bits); from this line on, fetch from SAD2 and HSCRL = 0 |
| 18 | display plane enable: bits 3-0 = I0 G0 R0 B0 (screen 0), bits 7-4 = I1 G1 R1 B1 (screen 1) |

Display address generation (CSP `create_addr_map`): for lines `y < SLN1`, addresses run from SAD0, one byte per 8 pixels, wrapping
to 0 after SAD1 (`addr = (addr == SAD1) ? 0 : (addr + 1) & 7FFF`); lines `y >= SLN1` run from SAD2 with the same wrap. 40 bytes per line in
320-dot modes, 80 in 640-dot modes. MAME masks the addresses differently and doesn't do the split **[MAME≠CSP]**.

Window: graphics is shown only between lines GDEVS..GDEVE (x2 in 200-line modes for the 400-line output) and columns GDEHS*8..GDEHE*8
(if start <= end and < 80). Outside, the text palette/background shows (CSP `draw_screen`).

The graphics V-blank (line GDEVE until GDEVS) drives: the CRTC interrupt request, 8255 port B bit 0 and the BD select-read bit 7.

### 5.6 VRAM read-modify-write (pages 30-33)

Window pages 30, 31, 32, 33 map RMW offsets 0000, 2000, 4000, 6000 (a 32 KB window = one plane's full 32 KB address range).
Every access goes to all four planes at `offset & 7FFF` (CSP `CRTC::read_data8/write_data8`).

Read: latch B, R, G, I = VRAM bytes. Return: if R07 bit 4: the compare byte (bit n = 1 where pixel n's IGRB equals R07 bits 3-0);
otherwise latch[R07 & 3].

Write, for each plane p with R05 bit p = 1:

- REPLACE (R05 bits 7-6 = 00): `vram_p = (vram_p & ~R06) | (R04.p ? (data & PAT_p & R06) : 0)`
- PSET (01): `vram_p = (vram_p & ~data) | (R04.p ? (data & PAT_p) : 0)`

In 4-colour mode (R0E = 03) offsets with bit 14 set address the G/I planes as "B/R" of the lower half: `B := addr&4000 ? G : B`, `R := addr&4000 ? I : R`,
only planes 0-1 apply.

Clear screen (write R05 with bits 7-6 = 10): CSP clears the selected planes, range by mode: modes 03/14/15/17/1D clear 0000-3FFF; 94/95/97/9D
clear 4000-7FFF; others 0000-7FFF. Sets the CLR flag, which reads 1 until the next graphics V-blank. CSP clears instantly; real hardware
takes time (unknown). MAME clears 16 KB per plane at bank 0 or +10000h **[MAME≠CSP]**.

MAME's RMW handler indexes planes 16 KB apart with offsets up to 7FFF, so offsets 4000-7FFF hit the next plane **[MAME bug]**.
MAME returns FFh / ignores writes when R0E = 03.

### 5.7 Colours and palettes

**Graphics 16 colours** (disp): codes 0, 9-15 = digital 8 colours at full level; 1-7 = the same hues at 4/7; 8 = grey 3/7. CSP (analogue RGB
monitor): R = 255 if `(i & 0A) == 0A`, 127 if `== 02`, else 0 (same for G with mask 0C, B with 09); code 8 = (152,152,152).
Digital monitor: 1-bit RGB from bits 1/2/0.

Palette flow (CSP `draw_screen`): graphics pixel code `c` → `palette_reg[c] & 0F` (if 0 → background colour) → `& cg_mask` (F6) → colour.
Text pixels use fixed digital 8 colours (indices 16-23); text colour 0 in a glyph = "non-transparent black" (index 8 in CSP), glyph
background = transparent. Priority: if `palette_reg[c]` bit 4 = 1 the graphics colour wins over text.

**Text 64-colour mode**: component = screen1 bit << 2 | screen2 bit << 1 (0 for the LSB); maximum brightness 6/7.
In 256-colour graphics with text not in 64-colour mode, text colours are dimmed the same way (only screen 1 = bit 2).

**4096-colour board MZ-1M10** (port AE, 16-bit): A15-A8: bits 4-1 = palette number, bit 0: 0 = write R (D7-4) and B (D3-0), 1 = write G (D3-0).
Enabled when OPN port A bit 2 = 0 (`PLT`). Applies to the final 16-colour code after text/graphics mixing (disp); code 0 is fixed black.
CSP: `num = (haddr & 1F) >> 1`, 4-bit components shifted to 8 bits; MAME the same.

**256-colour background**: R0B/R0C 9-bit GRB (5.3). A pixel with palette-mapped screen-1 code 0 and screen-0 code 0 shows the background.

## 6. Interrupts

Sources (CSP `interrupt.cpp`, MAME `irq_sel_w/irq_data_w`, iomap C6h):

| Port | Bits | Meaning |
|---|---|---|
| C6 W | 7 / 6 / 5 / 4 `VSEN` | select which vector C7 writes: 7 = CRTC (graphics V-blank), 6 = 8253, 5 = printer, 4 = RTC (one bit at a time) |
| | 3 VBLKIE, 2 TMIE, 1 PRTIE, 0 RTCIE | enables |
| C7 W | 7-0 | vector for the selected source(s) |

Mode 2 (IM 2) vectors. Priority inside the block: CRTC > 8253 > printer > RTC.

Daisy chain (CSP): **Z80 PIO (highest) → Z80 SIO → this interrupt block**. MAME's daisy chain has only the SIO; the PIO isn't chained
and the custom block answers through `irq_ack_cb` **[MAME≠CSP]**.

Request lines (CSP):

- CRTC: level, high from line GDEVE to line GDEVS (graphics V-blank).
- 8253: OUT0 level (the request follows OUT0; MAME latches on OUT0 high).
- Printer: (not driven in CSP's wiring; the PRINTER device doesn't signal it).
- RTC: RP5C15 ALARM output.

Acknowledge: the first enabled pending source returns its vector, clears its request and goes "in service"; RETI clears in-service
(CSP models IEI/IEO). iomap note: if a source is disabled while its request is pending, the acknowledge cycle drives no vector
(the CPU reads a floating bus).

The OPN's IRQ output is not connected in either emulator.

## 7. Sound

- **YM2203** at C8 (W address / R status: bit 7 BUSY, 1 timer B, 0 timer A) and C9 (data). 2 MHz. One I/O wait.
  jotego jt03 is the FPGA implementation (fpga_blocks.md). Mixing in MAME: FM 0.25, each SSG 0.25/0.5 relative; CSP level `-8 dB` FM/PSG.
- **SSG register 07**: the IPL sets port A = output, port B = input.
- **OPN port A (output, reg 0Eh)**: 7 `VACL` voice board reset, 6 `VOE` voice ROM, 5 `VBUSY`, 4 `VDATA` (voice board), 3 `MOUSE` (1 = SIO
  channel B goes to the mouse, 0 = 9-pin RS-232C), 2 `PLT` (0 = 4096-colour board output, 1 = main board output), 1 `DRSEL` (1 = swap FDD
  units: external 0-1 / internal 2-3; CSP `drive ^= 2`, MAME the same), 0 `READYA` (RS-232C RR, 25-pin pin 11).
- **OPN port B (input, reg 0Fh)**: 7 `VACK` voice board, 6 `RASTER` (1 = 200-line / 15 kHz CRT switch, 0 = 400-line), 5 `80B` (0 = MZ-80B
  mode), 4 `2000` (0 = MZ-2000 mode), 3 `ALARM` RTC pulse output (active low in CSP), 2 `CDB` (9-pin CD), 1 `CIA` (25-pin CI), 0 `CDA` (25-pin CD).
  CSP value at reset: `0x37`, bit 4 cleared for MZ-2000 boot, bit 5 cleared for MZ-80B boot, bit 6 set for a 200-line monitor; bit 3 follows
  the RTC pulse. MAME's DSW1: bit 6 "Monitor Interlace" (default 1 = 200 line), bits 5-4 labelled "IPLPRO" (they are the 80B/2000 mode
  bits), bit 0 "HD loader" **[MAME labels wrong]**.
- **Beeper**: 8255 port C bit 2 (`SOUND`), 1-bit level, added to the mix (CSP `PCM1BIT`, MAME `SPEAKER_SOUND`).
- Tape audio (voice track) and FDD/CMT noise are mixed by CSP; not needed in the core.

## 8. Kanji and dictionary ROM access

- Raster: the text CRTC reads glyphs straight from the 256 KB kanji ROM (5.1). One glyph row per cell per line: 80 bytes/line plus the
  PCG RAM. The core needs a per-line prefetch from SDRAM or a cache.
- CPU: window page 39 with port CF bit 7 = 1 maps a 2 KB kanji bank `CF & 7F` at the window's first 2 KB (PCG0 position); PCG1-3 stay.
  CSP and MAME agree.
- Dictionary: page 3A, 8 KB bank `CE & 1F`.
- **B8-B9** (MZ-1R13 option, CSP `mz1r13.cpp`, only B8-B9 wired in `mz2500.cpp`): write B8 = address low, B9 = address high (word address);
  read B8/B9 = byte `kanji2[(address << 1) | (port & 1)]`, reading B9 increments the address. BA/BB (bit-reversed data, select kanji/dic,
  increment) exist in the device but aren't mapped. ROM: `KANJI2.ROM` (128 KB) and `DICT2.ROM` (MZ-1R13 dictionary, 16 KB).
  MAME maps B8-B9 always: write sets a 16-bit index, read returns `kanji2[(index << 1) | (offset & 1)]`, no increment **[MAME≠CSP]**.

## 9. MZ-1E26 phone unit (CA)

Read: bit 7 POWER (1 = powered on from the phone), 5 CONEC (0 = voice line connected), 4 CMSTB, 3-0 command. Write: bit 4 `TOFF` 0→1→0 = power
off. Both emulators read 30h (idle). Not needed for games.

## 10. Peripherals

### 10.1 i8255 (E0-E3), mode word 82h (A out, B in, C out)

Port A (W, data recorder control, MZ-2500/2000 functions; iomap, CSP `cmt.cpp`):

| Bit | Name | Meaning |
|---|---|---|
| 7 | APSS-P | 0 = APSS on FF/REW |
| 6 | APLAY | 0 = play when rewind ends |
| 5 | AREW | 0 = rewind at tape end |
| 4 | VID | 0 = reverse the monochrome screen (CSP `SIG_CRTC_REVERSE`) |
| 3 | STOP | 1→0 = stop |
| 2 | PLAY | 1→0 = play/record |
| 1 | FF | 1→0 = fast forward |
| 0 | REW | 1→0 = rewind |

(In MZ-80B mode the bits are level/edge as on the MZ-80B: CSP `is_mz80b` branch.)

Port B (R):

| Bit | Name | Meaning |
|---|---|---|
| 7 | PB7 | Z80 PIO port B bit 7 (keyboard data bit 7, CSP `keyboard.cpp`) |
| 6 | READ | tape read data (and APSS gap detect) |
| 5 | TREADY | 0 = cassette loaded |
| 4 | WREADY | 0 = writable (1 = write protected or no tape) |
| 3 | TEND | 0 = recorder running, 1 = stopped |
| 0 | VBLANK | 0 = graphics V-blank, 1 = display |

MAME returns `FEh | vblank` only **[MAME≠CSP]**. Port B is also written (W) for the voice track: bit 7 MIC, bit 6 REC1 (iomap).

Port C (W):

| Bit | Name | Meaning |
|---|---|---|
| 7 | WRITE | tape write data |
| 6 | REC2 | 0 = record data track |
| 5 | KINH | 1 = disable the recorder's buttons |
| 4 | OPEN | 1→0→1 = eject |
| 3 | BST | 0 = IPL reset (like the front-panel IPL button) |
| 2 | SOUND | beeper |
| 1 | NST | 0→1 = "normal start": special reset (map 00-07, CPU reset) |
| 0 | VGATE | 1 = blank the screen (CSP `screen_mask`; MAME `m_screen_enable`) |

### 10.2 i8253 (E4-E7) and gate port (F0-F3)

CLK0 = 31.25 kHz; CLK1 = OUT0; CLK2 = OUT1 (CSP and MAME). OUT0 also drives the 8253 interrupt. Writing any value to F0-F3 pulses
GATE0 and GATE1 high→low→high (CSP `timer.cpp`, MAME `timer_w`). The IPL/BASIC use it as a clock/timer; The Black Onyx and the Super MZ
demo use channel 2 (MAME comment).

### 10.3 Z80 PIO (E8-EB) and keyboard

Port A (output): bits 3-0 `STB` row select; bit 4 `STB4`: 0 = return the AND of all rows (any key), 1 = the row in bits 3-0; bit 5 `CH80`
(1 = 80 columns); bit 6 `HCLG` and bit 7 `DISP` (MZ-2000/80B VRAM selects, 3.3). Port B (input): key data, active low.
CSP: `val = keys[(column & 0x10) ? (column & 0x0F) : 0x0F]` where `keys[0F]` = AND of rows 0-13. MAME also treats row 0F as "all".
The PIO is mode-3/bit mode in practice; it can interrupt (highest in the daisy chain).

Keyboard matrix (iomap table, CSP `key_map`, MAME `KEY0-KEYD`). Rows 0-13, data bits 0-7, active low:

| Row | D0 | D1 | D2 | D3 | D4 | D5 | D6 | D7 |
|---|---|---|---|---|---|---|---|---|
| 0 | F1 | F2 | F3 | F4 | F5 | F6 | F7 | F8 |
| 1 | F9 | F10 | KP 8 | KP 9 | KP , | KP . | KP + | KP - |
| 2 | KP 0 | KP 1 | KP 2 | KP 3 | KP 4 | KP 5 | KP 6 | KP 7 |
| 3 | TAB | SPACE | RETURN | UP | DOWN | LEFT | RIGHT | BREAK |
| 4 | / | A | B | C | D | E | F | G |
| 5 | H | I | J | K | L | M | N | O |
| 6 | P | Q | R | S | T | U | V | W |
| 7 | X | Y | Z | ^ | ¥ | _ | . | , |
| 8 | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| 9 | 8 | 9 | : | ; | - | @ | [ | (none) |
| 10 | ] | COPY | CLR/HOME | INST/DEL | BS | ESC | KP * | KP / |
| 11 | GRAPH | LOCK | SHIFT | KANA | CTRL | | | |
| 12 | 無変換 (MUHENKAN / KJ1) | 変換 (HENKAN / KJ2) | | | | | | |
| 13 | LOGO (アルゴ) key | HELP | | | | | | |

CSP PC mapping (useful for the PS/2 table): COPY = F12, HELP = F11, LOGO = Kanji key, BREAK = Pause, LOCK = Caps Lock, GRAPH = Alt,
KANA = Kana key. The adapter on maroon's `kbd.html` maps: 全角/半角 → ESC, PrintScreen → COPY, Home → CLR, Del → INST/DEL, PageDown → KP ",",
Windows/Menu → LOGO.

Physical keyboard link (kbd.html, `MZ2500_Keyboard_Protocol.pdf`): Mini-DIN 8, signals RTSN, KD4, MPX from the main unit and KD3-0 bidirectional,
about 1.2 us per cycle; the main unit sends the row while RTSN = H, the keyboard returns the nibble (MPX selects high/low) while RTSN = L.
Only relevant for a real-keyboard adapter.

### 10.4 RP5C15 RTC (CC, 16-bit)

A11-A8 → RTC A3-A0 (`OUT (C)` with B = register). 3 I/O waits. Standard RP5C15 register map (mode register D selects bank 0 time / bank 1
alarm). CSP implements it with its RP5C01 model; outputs: ALARM → interrupt source 3; the 1 Hz / 16 Hz / alarm pulse output → OPN port B bit 3
(inverted). MAME: alarm interrupt TODO. Seed from MiSTer's RTC (hps_io `RTC[64:0]`).

### 10.5 Z80 SIO and CD port

CD (W): bit 7 `A`: 0 = SIO at A0-A3, 1 = at B0-B3 (the other range is unmapped); bits 5-3 channel A clock, bits 2-0 channel B clock:
`(4 MHz / 13) / 2^n` (000 = 307 kHz = 19200 baud at x16 ... 111 = 2400 Hz = 150 baud). Channel A = 25-pin RS-232C; channel B = 9-pin RS-232C
or mouse (OPN port A bit 3).

### 10.6 Mouse (SIO channel B)

CSP `mouse.cpp`: when OPN port A bit 3 = 1 and SIO channel B DTR goes high→low, the mouse sends 3 bytes into channel B's receiver:
`d0 = (dx >= 128 ? 10h : dx < -128 ? 20h : 0) | (dy >= 128 ? 40h : dy < -128 ? 80h : 0) | left (bit 0) | right (bit 1)`, `d1 = dx`, `d2 = dy`
(X68000 mouse format). MAME uses its X68000 mouse on the RS-232 port with RTS; the select line is missing (MAME TODO) **[MAME≠CSP]**.
The core can model only channel B receive + DTR, not a full SIO.

### 10.7 Joysticks (EF)

Two Atari/MSX-type ports. Write (iomap; CSP initial 0Fh, MAME resets to 3Fh): bit 0 TRGA1O, 1 TRGB1O, 2 TRGA2O, 3 TRGB2O (0 = drive that
trigger pin low), 4 COM1, 5 COM2 (common pins), 6 SEL (0 = read port 1, 1 = port 2). To just read: write 0Fh (port 1) or 4Fh (port 2).

Read (CSP): start `3Fh`; for the selected port, a trigger output bit = 0 forces its input low (port 1: bit 0 → bit 5, bit 1 → bit 4;
port 2: bits 2/3); if COMx = 0, direction bits are read (bit 0 up/FWD, 1 down/BACK, 2 left, 3 right), active low; trigger A (button 1) →
bit 5, trigger B → bit 4. iomap names bit 5 TRGB and bit 4 TRGA (flag: naming only). MAME reads FFh base, so bits 7-6 = 1 **[MAME≠CSP]**.

### 10.8 Floppy (MB8876, D8-DE)

| Port | Function |
|---|---|
| D8-DB | MB8876 registers. The MB8876 has an inverted data bus: CSP inverts command/track/sector/data on write and on read (`~data`) |
| DC (W) | bit 7 M-ON motor (1 = on); bit 2 DSEN (drive select enable, iomap); bits 1-0 drive number (XOR 2 when OPN port A bit 1 = 1) |
| DD (W) | bit 0 head select |
| DE (W) | bit 0: 0 = MFM (double density), 1 = FM (CSP 2023/5/29: needed because CSP's MB8877 checks per-sector density) |

Drives are 3.5" 2DD: 80 cylinders x 2 sides x 16 sectors x 256 bytes (640 KB). CSP sets all four drives to `DRIVE_TYPE_2DD`. The FDC IRQ/DRQ
aren't connected to interrupts; software polls the status register. One I/O wait in 2500 mode.

### 10.9 Printer (FE-FF)

FE W: bit 7 STB (strobe), bit 6 PRIM (reset/IPRIM). FE R: `F2h | BUSY` (bit 0 BUSY; iomap: bit 1 STA). FF W: data. Polarity of STB/PRIM depends on
system DIP switches 1-2 (MZ method non-inverted vs Centronics inverted). The printer interrupt (C6 source 2) exists but isn't driven in CSP.

### 10.10 System DIP switches (dipsw.html)

MZ-2521: SW1 printer reset polarity, SW2 strobe polarity, SW3 RS-232C channel A clock source, SW4 superimpose (15 kHz only).
MZ-2520: SW1-2 as above, **SW3 display resolution (ON = 400 lines / 24 kHz, OFF = 200 lines)**, SW4 superimpose, SW5-6 RS-232C sync/async/clock,
SW7-8 unused. (On the 2500 the 200/400-line choice is the CRT switch in the "kangaroo pocket".)

### 10.11 Data recorder

Built-in, software controlled through the 8255 (10.1), same scheme as the MZ-2000 (CSP shares `cmt.cpp` between EmuZ-80B/2000/2200/2500).
APSS: FF/REW with PA7 = 0 searches for the next gap; CSP raises PB6 for 350 ms when it detects one. End-of-tape auto-rewind (PA5) and
start-of-tape auto-play (PA6). Data rate 2000 bps (eaw spec). Tape images: MZT (MZF-style header + data) and CAS/WAV.

## 11. Boot and IPL behaviour

- Power on: IPL map, CPU at 0000h in IPL ROM. The IPL reads OPN port B to pick MZ-2500/2000/80B mode and 200/400 lines, sets text R0F,
  then looks for a boot floppy (drive 1), then tape, and shows "loading error / Press F or C" without media (seen in both MAME and EmuZ).
- With D88 disks the IPL loads the boot sectors; Dust Box (Hoshikuzu-bako) and Ys III boot to their title screens in both emulators
  (refs/compare/).

## 12. Software-visible video summary (for a quick start)

400-line mode, 80x25 text, 640x200x16 graphics (R0E = 17h), F7 = 0 (16-line font), R00 = 05h (25 rows, screen 1, G16): this is the mode
BASIC-M25 and most games start in. Note the graphics is 200-line (doubled) under 400-line text.

## 13. MAME vs CSP disagreements

| # | Topic | MAME | CSP (follow this) |
|---|---|---|---|
| 1 | Wait states | none | M1 +1, VRAM page waits, display-period WAIT, I/O waits (section 2) |
| 2 | Video timing | 21.477 MHz, 748 x 480 placeholder | 864 x 448 @ 55.49 Hz / 896 x 262 @ 60.99 Hz |
| 3 | RMW window | planes 16 KB apart, offsets ≥ 4000h overlap the next plane | 32 KB per plane (standard + extended) |
| 4 | Graphics modes | 00, 03 (prelim), 14, 15, 17, 1D, 97 | adds 93, 94, 95, 9D, 19, 99, EX bit, 4-colour MMU remap |
| 5 | Scroll | SAD0/SAD1 + HSCRL partly; no split (SAD2/SLN1) | full split scroll |
| 6 | Clear screen | 16 KB of each plane at bank 0/10000h | range depends on mode |
| 7 | Text window | fixed offsets | formulas from R03/R05/R07/R08 |
| 8 | Text attributes | reverse/blink not implemented (TODO), 20-row/64-colour partial | implemented |
| 9 | Kanji in 8-line mode | "cut in half" (TODO) | `t1 << 3` addressing, 8-byte glyph |
| 10 | VBLANK interrupt | screen vblank, latched per frame | graphics V-blank level (GDEVE..GDEVS) |
| 11 | Daisy chain | SIO only; PIO not chained | PIO → SIO → interrupt block |
| 12 | 8255 port B | `FEh | vblank` | tape signals, PB7 = key bit 7, vblank |
| 13 | F4 read | screen blanking | text-CRTC blanking |
| 14 | B8-B9 kanji2 | always present, no auto-increment | MZ-1R13 option, read B9 increments |
| 15 | Mouse | X68000 mouse on RS-232, no select | 3-byte packet on DTR falling, gated by OPN PA3 |
| 16 | MZ-2000/80B modes, B7 | not implemented | implemented |
| 17 | OPN port B labels | bits 5-4 "IPLPRO" | 80B / 2000 mode bits (iomap agrees) |
| 18 | Printer FE/FF | not mapped | mapped |
| 19 | Joystick read | bits 7-6 = 1 | bits 7-6 = 0 |
| 20 | Palette | 16 pens + 4096 board; no priority bit use for 4096 | priority16/256 tables, background colour, analogue/digital monitor |
| 21 | IPL-reset delay | 10 ms timer | 100 us |
| 22 | CG ROM | loads `cg.rom` ("hand made?") but never draws from it | doesn't load it; fonts come from the kanji ROM |

Visible effect: Ys III's intro text box in MAME is shifted/clipped, in CSP it is complete (refs/compare/mame_ys3_f3000.png vs
bubiz_ys3_f3000.png).

## 14. Open questions for hardware tests

- Exact clear-screen duration and CLR flag timing.
- Printer interrupt source and STA bit.
- Joystick trigger bit naming (iomap vs CSP).
- Text/graphics horizontal alignment offsets (CSP: text char 9 = graphics 0 at 400 lines; event timing uses GDEHS + 10).
- VBLANK interrupt edge vs level on real hardware (iomap says the source is the graphics controller's V-blank).
