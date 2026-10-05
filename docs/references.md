# References

Local copies are under the gitignored `refs/` (see `refs/README.md`); `tools/fetch_refs.sh` re-fetches them.

## Emulators

| Name | URL | Licence | Local |
|---|---|---|---|
| EmuZ-2500 / Common Source Code Project (Takeda Toshiya), official | https://takeda-toshiya.my.coocan.jp/mz2500/index.html, source https://takeda-toshiya.my.coocan.jp/common/source.7z (2026-01-01) | GPLv2 | `refs/csp/takeda/`, `refs/csp/source.7z` |
| CSP Qt port (K. Ohta / Artanejp) | https://github.com/Artanejp/common_source_project-fm7 | GPLv2 | `refs/csp/common_source_project-fm7/`, build `refs/csp/build/` |
| BubiZ-2500 (bubio, CSP core + Odin/Sokol, headless mode) | https://github.com/bubio/BubiZ-2500 (v1.0.0 release) | GPLv2 | `refs/csp/BubiZ-2500/`, `refs/csp/bubiz-release/` |
| youkan700 CSCP fork ("野良ビルド") | https://github.com/youkan700/CSCP, http://www.maroon.dti.ne.jp/youkan/CSCP/index.html | GPLv2 (CSP) | no |
| kuran-kuran CSP fork | https://github.com/kuran-kuran/CommonSourceCodeProject | GPLv2 (CSP) | no |
| MAME `mz2500`/`mz2520` driver (Angelo Salese) | https://github.com/mamedev/mame/blob/master/src/mame/sharp/mz2500.cpp | BSD-3-Clause (file); MAME GPL-2.0+ | `refs/mame/mz2500.cpp`, `.h`, full tree `refs/mame/src-tree/` (395cc09e) |
| MAME software lists | `hash/mz2500_flop.xml`, `hash/mz2000_flop.xml` (no `mz2500_cass.xml` exists) | CC0-1.0 | `refs/mame/` |
| Michael Franzen's emulators | https://original.sharpmz.org/mfranzenemu.htm | freeware | no |
| Zophar's Domain EmuZ-2500 page | https://www.zophar.net/sharpmzx/emuz-2500.html | | no |
| Batocera MZ-2500 (MAME) | https://wiki.batocera.org/systems:mz2500 | | no |
| SharpMZ_MiSTer prior research | `../SharpMZ_MiSTer/docs/mz2500.md` | | sibling repo |

## Hardware documentation

| Document | URL | Local |
|---|---|---|
| I/O map (youkan700, Japanese; primary register reference) | http://www.maroon.dti.ne.jp/youkan/mz2500/iomap.html | `refs/docs/maroon/iomap.html`, `iomap.txt` |
| Video output overview | http://www.maroon.dti.ne.jp/youkan/mz2500/disp.html | `refs/docs/maroon/disp.html`, `disp.txt` |
| Video timing (x1center.org measurements) | http://www.maroon.dti.ne.jp/youkan/mz2500/videotiming.html | `refs/docs/maroon/videotiming.html` |
| Keyboard protocol and USB adapter | http://www.maroon.dti.ne.jp/youkan/mz2500/kbd.html | `refs/docs/maroon/kbd.html`, images |
| System DIP switches | http://www.maroon.dti.ne.jp/youkan/mz2500/dipsw.html | `refs/docs/maroon/dipsw.html` |
| IOCS service calls (SVC.INC) / sector read | http://www.maroon.dti.ne.jp/youkan/mz2500/SVC.INC, sectorread.html | `refs/docs/maroon/` |
| eaw.app MZ-2500 specifications | https://eaw.app/sharpmz-2500-specifications/ | `refs/docs/web/` |
| eaw.app manuals page (Philip Smart's hosted scans) | https://eaw.app/sharpmz-2500-manuals/ | `refs/docs/eaw/*.pdf` |
| — I/O map (English translation of youkan's page) | https://eaw.app/Downloads/Manuals/Sharp/MZ2500_IO_Map.pdf | `refs/docs/eaw/MZ2500_IO_Map.pdf` (+ .txt) |
| — Schematics (24 pages) | .../MZ2500_Schematics.pdf | yes |
| — Keyboard protocol, video capabilities | .../MZ2500_Keyboard_Protocol.pdf, MZ2500_Video_Capabilities.pdf | yes (+ .txt) |
| — Technical document (28 pages), user manual, BASIC-M25 and S25 manuals, telephone manual, SuperMZ magazine | .../MZ2500_Document.pdf, MZ2500_UserManual.pdf, MZ2500_BASIC_M25_Manual.pdf, MZ2500_BASIC_S25_Manual.pdf, MZ2500_Telephone_Manual.pdf, MZ2500_SuperMZ_Magazine.pdf | yes (scans, 24-166 MB) |
| Takeda's EmuZ-2500 page and development diary | https://takeda-toshiya.my.coocan.jp/mz2500/ (diary.txt, diary1-3.txt) | `refs/docs/takeda/` |
| CSP top page, history | https://takeda-toshiya.my.coocan.jp/common/index.html | `refs/docs/takeda/takeda_common.html`, `refs/csp/takeda/source/history.txt` |
| Wikipedia | https://en.wikipedia.org/wiki/MZ-2500, https://ja.wikipedia.org/wiki/MZ-2500 | `refs/docs/web/` |
| AKIBA PC Hotline retro column | https://akiba-pc.watch.impress.co.jp/docs/column/retrohard/1371267.html | no |
| x1center.org (timing measurements) | http://www.x1center.org/ | no |
| MZ LAN boards (DIY W3100A) | http://cwaweb.bai.ne.jp/~ohishi/zakki/mzlan_final.htm | no |
| Fujitsu MB8876A/MB8877A datasheet | https://archive.org/details/Fujitsu-MB8876a-MB8877-FDC-datasheet | `../SharpMZ_MiSTer/refs/docs/fdc/` |
| archive.org Sharp promo material | https://archive.org/details/SuperMZ, https://archive.org/details/product_mz2500, https://archive.org/details/mz25_1st, https://archive.org/details/softlist | no |

## ROM information

| Item | URL |
|---|---|
| MAME ROM definitions | `ROM_START( mz2500 )` in mz2500.cpp (docs/roms.md) |
| idealine.info sharpmz mirror (our ROM source) | https://www.idealine.info/sharpmz/ |
| Mr. Tago's ROM dump tool 「アルゴの記憶」 (dead GeoCities) | http://www.geocities.co.jp/SiliconValley-Sunnyvale/2521/ |
| MZ-1E32 kanji ROM dump tool (youkan700) | http://www.maroon.dti.ne.jp/youkan/mz2500/Sui1E32.7z |

## Software archives

| Archive | URL |
|---|---|
| archive.org `mz-2500` (Hoshikuzu-bako set + Ys III) | https://archive.org/details/mz-2500 |
| Hoshikuzu-bako publisher site (dead) | http://www2.odn.ne.jp/~caf98150/index.html |
| forum.sharpmz.org disk image thread | https://forum.sharpmz.org/viewtopic.php?t=41 |
| LaunchBox game list (titles only) | https://gamesdb.launchbox-app.com/platforms/games/205-sharp-mz-2500 |

## FPGA blocks

See `docs/fpga_blocks.md`.

| Block | URL | Licence |
|---|---|---|
| jt12 / jt03 (YM2203) | https://github.com/jotego/jt12 | GPL-3.0 |
| jt49 (SSG) | https://github.com/jotego/jt49 | GPL-3.0 |
| X68000_MiSTer RP5C15 | https://github.com/MiSTer-devel/X68000_MiSTer/tree/master/rtl/rtc | none stated |
| MSX_MiSTer RTC (RP5C01) | https://github.com/MiSTer-devel/MSX_MiSTer/blob/master/rtl/peripheral/rtc.vhd | BSD-style, non-commercial |
| sorgelig sdram.sv / wd1793.sv | https://github.com/MiSTer-devel/MSX1_MiSTer/tree/master/rtl (and local cores) | GPL-3.0+ / GPL-2.0+ |
| T80 | https://github.com/MiSTer-devel/T80 | T80 licence (BSD-style) |
| Template_MiSTer | https://github.com/MiSTer-devel/Template_MiSTer | GPL |
| NibblesLab MZ-80B on DE0 (z8420 PIO) | https://github.com/NibblesLab/mz80b_de0 | see repo |
| SharpMZ v2.0 (eaw.app) | https://eaw.app/sharpmz-emulator/ | GPL-3.0 |
