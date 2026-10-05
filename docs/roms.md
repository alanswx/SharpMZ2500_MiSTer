# ROMs

The MZ-2500 ROMs are Sharp's copyright. They are **not** in this repository and are never embedded in the RBF: the core loads them
from the SD card. Local copies (from idealine.info's sharpmz.org mirror) are in the gitignored `software/roms/` and all match MAME.

## MAME ROM set

From `ROM_START( mz2500 )` / `ROM_START( mz2520 )` in `src/mame/sharp/mz2500.cpp` (MAME 395cc09e, 2026-10-05). Both sets share everything
except the IPL.

| MAME file | Size | CRC32 | SHA1 | Region / use |
|---|---|---|---|---|
| `ipl.rom` (mz2500) | 32 KB | 7a659f20 | ccb3cfdf461feea9db8d8d3a8815f7e345d274f7 | IPL, pages 34-37 |
| `ipl2520.rom` (mz2520) | 32 KB | 0a126eb2 | faf71236b3ad82d30184adea951d43d10ced663d | MZ-2520 IPL |
| `cg.rom` | 2 KB | a082326f | dfa1a797b2159838d078650801c7291fa746ad81 | "hand made?"; not used by MAME's renderer, not used by CSP |
| `kanji.rom` | 256 KB | dd426767 | cc8fae0cd1736bc11c110e1c84d3f620c5e35b80 | kanji ROM: JIS level 1 + 2 and the ANK fonts |
| `kanji2.rom` | 128 KB | eaaf20c9 | 771c4d559b5241390215edee798f3bce169d418c | MZ-1R13 kanji ROM (read through B8/B9) |
| `dict.rom` | 256 KB | aa957c2b | 19a5ba85055f048a84ed4e8d471aaff70fcf0374 | dictionary ROM, page 3A |
| `phone.rom` | 16 KB | 8e49e4dc | 2589f0c95028037a41ca32a8fd799c5f085dab51 | MZ-1E26 phone ROM, pages 3C-3F |

## Local files (verified 2026-10-05)

`software/roms/zips/` holds the original idealine zips, `software/roms/extracted/<zip>/` the contents. CRC32 and SHA1 computed locally:

| Local file | Size | CRC32 | SHA1 | Matches |
|---|---|---|---|---|
| `IPL/IPL.ROM` | 32768 | 7a659f20 | ccb3cfdf…d274f7 | `ipl.rom` |
| `MZ-2531_IPL/IPL.ROM` | 32768 | 7a659f20 | same | `ipl.rom` (the MZ-2531 uses the same IPL) |
| `MZ-2520_IPL/IPL.ROM` | 32768 | 0a126eb2 | faf71236…d663d | `ipl2520.rom` |
| `MZ-2521_IPL/IPL.ROM`, `MZ-2521_IPL2/IPL.ROM` | 825 | 3842065a | 1e2c4891… | none: truncated, ignore |
| `CG/CG.ROM` | 2048 | a082326f | dfa1a797…ad81 | `cg.rom` |
| `KANJI/KANJI.ROM` | 262144 | dd426767 | cc8fae0c…b80 | `kanji.rom` |
| `KANJI2/KANJI2.ROM` | 131072 | eaaf20c9 | 771c4d55…418c | `kanji2.rom` |
| `DICT/DICT.ROM`, `MZ-1R28/DICT.ROM` | 262144 | aa957c2b | 19a5ba85…0374 | `dict.rom` |
| `MZ-1E26/PHONE.ROM` | 16384 | 8e49e4dc | 2589f0c9…ab51 | `phone.rom` |
| `MZ-1E30/FILE.ROM` | 32768 | a7bf39ce | 3f4a237f…0081 | not in MAME; CSP SASI BIOS (`MZ1E30.ROM`/`FILE.ROM`) |
| `MZ-1R13DIC/1R13DIC.ROM` | 16384 | 6efec275 | 9a1586cf…2f13 | not in MAME; CSP `DICT2.ROM` / `MZ1R13_DIC.ROM` |
| `2000font400/2000FONT400.BMP` | 4158 | 60a624c8 | | a bitmap of the MZ-2000 400-line font, not a ROM |
| `mz-1z001/MZ-1Z001.dat`, `mz-1z002/MZ-1Z002.dat` | | | | MZ-2000/2200 BASIC tapes, not 2500 ROMs |
| `mz2200ipl/mz2200ipl.bin` | 2048 | 476801e8 | | MZ-2200 IPL, not used here |

Run `tools/fetch_refs.sh --roms <dir>` to copy and re-verify them.

## Names used by the emulators

| Content | MAME | CSP / BubiZ-2500 (in the data folder) |
|---|---|---|
| IPL | `ipl.rom` / `ipl2520.rom` | `IPL.ROM` |
| Kanji | `kanji.rom` | `KANJI.ROM` |
| Dictionary | `dict.rom` | `DICT.ROM` |
| Phone | `phone.rom` | `PHONE.ROM` |
| MZ-1R13 kanji / dictionary | `kanji2.rom` / — | `KANJI2.ROM` (or `MZ1R13_KAN.ROM`) / `DICT2.ROM` (or `MZ1R13_DIC.ROM`) |
| SASI BIOS | — | `MZ1E30.ROM`, `MZ-1E30.ROM`, `SASI.ROM` or `FILE.ROM` |
| CG | `cg.rom` | not used |

**CG ROM**: CSP never loads a CG ROM: every text font (ANK 8x8 at 6010h, 8x16 at 6000h, the MZ-2000 font at 6018h, MZ-700 fonts at 4400h/5C00h)
is inside the kanji ROM. MAME's `cg.rom` is marked "hand made?" and isn't referenced by its drawing code; it doesn't match a simple slice of
the kanji ROM (checked: under 12% of bytes agree with the 6000h/6010h/6018h sets). The core doesn't need it.

## Where they come from

- Dumped from real machines. Takeda's page recommends Mr. Tago's "MZ-2500 シリーズ ROM 作成テスト版" dump tool from his site 「アルゴの記憶」
  (`http://www.geocities.co.jp/SiliconValley-Sunnyvale/2521/`, GeoCities Japan is closed; try the Wayback Machine).
- idealine.info (sharpmz.org mirror) ROM pages: https://www.idealine.info/sharpmz/ (frameset; MZ-2500 ROM page). Our copies come from there.
- MAME ROM sets for `mz2500` circulate on ROM sites; availability noted only, we don't download from them.
- MZ-1E32 kanji ROM (24x24, optional): youkan700's `Sui1E32.7z` dumping tool on maroon.dti.ne.jp.

## How the core loads them

Plan (to be finalised with `docs/design.md`):

| Content | Size | Destination | Needed |
|---|---|---|---|
| IPL | 32 KB | block RAM (or SDRAM) | yes |
| Kanji | 256 KB | SDRAM; the text raster prefetches glyph rows | yes (all text fonts) |
| Dictionary | 256 KB | SDRAM, page 3A | optional (MZ-2531 / MZ-1R28; Japanese input) |
| Phone | 16 KB | SDRAM, pages 3C-3F | optional |
| MZ-1R13 kanji2 | 128 KB | SDRAM, ports B8/B9 | optional |
| MZ-2520 IPL | 32 KB | replaces the IPL | for the MZ-2520 model |

Delivery from the SD card through hps_io `ioctl` downloads: either one `boot.rom` concatenation in `games/SharpMZ2500/` loaded at start
(as many MiSTer computer cores do), or separate `F` OSD entries / `bootN.rom` indices. A simple fixed layout for a single `boot.rom`:

| Offset | Size | Content |
|---|---|---|
| 000000 | 32 KB | IPL (`IPL.ROM`) |
| 008000 | 32 KB | MZ-2520 IPL or FFh |
| 010000 | 256 KB | `KANJI.ROM` |
| 050000 | 256 KB | `DICT.ROM` (or FFh) |
| 090000 | 32 KB | `PHONE.ROM` padded with FFh |
| 098000 | 128 KB | `KANJI2.ROM` (or FFh) |
| 0B8000 | | end (736 KB) |

A small script in `tools/` can build it from the user's dumps after checking CRCs against the table above. Missing optional ROMs read FFh,
as in CSP (`memset(..., 0xff)`).
