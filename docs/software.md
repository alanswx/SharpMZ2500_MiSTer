# Software

Where MZ-2500 software is preserved, the image formats the core must read, and the test titles. Images live only in the gitignored
`software/` (see `software/README.md`); nothing here is redistributed.

## Archives

| Source | What | Notes |
|---|---|---|
| MAME software list `mz2500_flop` (`hash/mz2500_flop.xml`, CC0) | 75 disks: 31 supported, 26 partial, 18 not supported in MAME | names, CRC32/SHA1 of each D88. The acceptance list. `mz2500` also accepts `mz2000_flop` |
| archive.org item `mz-2500` (https://archive.org/details/mz-2500) | "MZ 1500, 2500 同人自作フリーゲームセット (起動確認済)": a RAR with the Hoshikuzu-bako / Dust Box disk magazine (16 issues + 3 specials) and Ys III (2 disks) | downloaded to `software/archive.org/mz-2500/`; every D88 matches a MAME softlist entry (below). Ys III is a commercial Falcom title, mislabelled as doujin in the set: keep it local only |
| archive.org Sharp promotional scans | 冊子「Super MZ」 (SuperMZ), Super MZ 新製品紹介資料 (product_mz2500), MZ-2500 pamphlet (mz25_1st), software development request list (softlist) | documents, not software |
| Hoshikuzu-bako (星くずばこ) disk magazine | Kawano's site `http://www2.odn.ne.jp/~caf98150/index.html` published almost every issue (Takeda's page; the link is now struck out, site gone; try the Wayback Machine) | freely distributed by its authors; same images as the archive.org set |
| maroon.dti.ne.jp/youkan/mz2500/ | youkan700's tools: HDD image with OBJ launcher (`HDD_BootSel.zip`), `MZDiskFile.zip` (HDD image file tool), `Sui1E32.7z`, keyboard/joypad test programs | author-published freeware |
| idealine.info / sharpmz.org mirror | ROMs and some MZ-2000/80B material; little MZ-2500 software | ROMs used here |
| forum.sharpmz.org "Lots of disk images" thread | community collection links | check provenance before using |
| `SharpMZ_MiSTer/software/Sharp Mz-2500.zip` (copied to `software/`) | Champion Pro-Wrestling Special and Flicky: loader MZT/CAS plus raw `*.DAT` memory dumps injected with EmuZ-2500's debugger (`command.txt`: `N file`, `L addr`, `R PC`, `G`) | not runnable as tapes; needs a "load at address and jump" debug path |
| Commercial disk sets ("TOSEC"-style, ROM sites) | most of the MAME list | availability noted only; not downloaded |

The MZ-2000 software list (`mz2000_flop`) and MZ-2000/80B tapes run in the 2500's compatibility modes.

## Formats

### D88 (main floppy format)

Header 2B0h bytes (CSP `disk.cpp`, MAME `d88_dsk`):

| Offset | Size | Field |
|---|---|---|
| 00 | 17 | disk name (NUL-terminated) |
| 11 | 9 | reserved |
| 1A | 1 | write protect (10h = protected) |
| 1B | 1 | media type: 00 = 2D, 10h = 2DD, 20h = 2HD |
| 1C | 4 | total image size (little endian) |
| 20 | 4 x 164 | track offsets (track = cylinder*2 + head), 0 = no track |

Each sector: 16-byte header + data: C, H, R, N (1 each), sectors in this track (2), density (1: 00 = MFM, 40h = FM), deleted mark (1: 00 or
10h), FDC status (1, e.g. CRC error A0h), reserved (5), data size (2), then the data. Sectors in a track are stored in their physical order.
Multi-disk files concatenate D88 images.

MZ-2500 standard disk: 2DD, 80 cylinders x 2 heads x 16 sectors x 256 bytes = 655360 bytes data; the D88 is 697008 bytes
(2B0h + 160 x 16 x (16 + 256)). Larger images (784048, 830144 bytes) hold extra/odd tracks (copy protection, 82+ cylinders) and must be
handled through the offsets, not by assuming a geometry. Example: Dust Box vol. 1 header: media type 10h, size 000AA2B0h.

`rtl/wd1793.sv` in SharpMZ_MiSTer / FM-7_MiSTer already parses D88 (FM-7 D77 is the same format) and handles the per-sector status/
density; CSP checks per-sector density against port DE since 2023.

### Raw images (.2dd, .dsk)

`.2dd`: raw sector dump, 80 x 2 x 16 x 256 = 655360 bytes in C/H/R order (youkan700's tools convert D88 → "ベタ形式 *.2DD").
Convert to D88 for the core (or support raw images with a fixed geometry). MAME accepts many others (mfi, hfe, td0, imd, dfi).

### Tape: MZT / CAS / WAV

- **MZT**: one or more MZF-style records: 128-byte header (attribute, 17-byte name, size, load address, exec address, comment) followed by the
  data; the MZ-80B/2000 format. Same as SharpMZ_MiSTer's `.mzf/.mzt` handling and `tape_image.sv`.
- **CAS** (CSP): a 1-bit-per-sample or pulse recording of the data track (CSP `datarec.cpp` reads `.cas`, `.mzt`, `.wav`, `.mti`, `.mtw`).
- **WAV**: real recordings. MZ-2500 data rate 2000 bps, same signalling as the MZ-2000.

### Hard disk (MZ-1E30 SASI, optional)

CSP `SASI0.DAT`/`SASI1.DAT` (`create_hd` tool in CSP), 33 x 256-byte sectors per track. youkan700 provides a bootable HDD image with an OBJ
launcher.

## Test titles

All are in MAME's list. **Local** = present in `software/archive.org/mz-2500/extracted/` (CRC matches MAME).

| Title | MAME name | MAME | Exercises | Local |
|---|---|---|---|---|
| Hoshikuzu-bako / Dust Box vol. 1-16, '91 Special | `dustbx01`-`dustbx16`, `dustbx91` | partial | BASIC-M25 boot, 320x200 graphics (title: 16/256 colours), PCG, mouse in the menu | yes (CRCs 170fc283 …) |
| Hoshikuzu-bako Special 2, 3 | `unk3`, `unk4` | partial / no | | yes |
| Ys III - Wanderers from Ys (Falcom, 1989) | `ys3` (2 disks) | yes | text window + graphics priority, scrolling, OPN music | yes (9df096d2, 56e42bcd) |
| BASIC-M25 V1.0A / V2.0B | `basicv1`, `basicv2` | partial | BASIC, kanji text, HELP-at-boot for S25 | no |
| Super MZ Demo 1 | `mzdemo1` | yes | 8253 channel 2, demo effects | no |
| Kaleidoscope Demo (Hot-B) | `kaleidos` | yes | | no |
| The Black Onyx | `blckonyx` | yes | 8253 channel 2 (MAME comment) | no |
| The Tower of Druaga | `druaga` | yes | interrupt enable behaviour ("activeness is trusted, see Tower of Druaga"), text colour 0 | no |
| Xevious, Mappy, Galaga (Dempa) | `xevious`, `mappy`, `galaga` | yes | 8-colour PCG over kanji (Xevious), reverse attribute (Mappy) | no |
| Back to the Future | `backtof` | yes | kanji text in 8-line mode (MAME TODO) | no |
| Nobo | `nobo` | yes | 8255 PB0 vblank polling | no |
| Yukar K2 | `yukark2` | no | 640x400 4-colour mode | no |
| Personal CP/M | `pcpm` | yes | CP/M boot, 80-column text | no |
| Relics | `relics` | partial | MB8877 quirk (CSP had a Relics-specific FDC patch, since removed) | no |
| Sorcerian (unofficial port), MAGIC, 紅玉伝 (Kugyokuden) | not in list | | CSP timing fixes mention them (Z80 cycle events, VBLANK start == end, 400-line R03/R05 patch) | no |
| Hydlide, Xanadu | not in the MAME list | | candidates if images turn up | no |

Golden reference frames: see `docs/emulators.md` (BubiZ-2500 headless) and `refs/compare/`.
