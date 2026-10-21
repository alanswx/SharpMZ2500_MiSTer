# Release notes

Builds in `releases/` are tester builds: copy one to `/media/fat/_Computer/` on the MiSTer SD card (setup in the
[README](README.md#getting-started-on-a-mister)). Newest first. Builds not listed here were intermediate and are not
in the repository.

## 20261021b

- Dictionary ROM (page 3A, bank port CE), phone ROM (pages 3C-3F) and the MZ-1R13 kanji ROM (ports B8/B9), loaded from
  a longer `boot.rom` (736 KB: `tools/make_bootrom.sh` takes them as arguments 5-7). A 320 KB `boot.rom` keeps working;
  the optional ROMs then read FFh, as in the emulators when the file is missing.
- `tools/blank_d88.py` makes blank formatted 2DD disks for games that want a user or data disk (Moon Child's
  MAKE CHARACTER formats and fills one; checked byte for byte against the emulator).
- Built with fitter seed 2: the default placement missed timing by 0.09 ns in the MiSTer framework's HDMI scaler.

## 20261020b

- OSD **Load RAM image (MZ-2000)**: MAME `mz2000_snap` images (`.bin`, MZ-2000 memory from 0000) start at once, in
  MZ-2000 mode whatever the Boot mode setting. All 14 game images run, including Binary Land, Front Line, Wild
  Western and Xetter 2000, which never finished loading as tapes (they overwrite the IPL's loader). A reset goes back
  to the IPL.
- Floppy controller: sector register writes during the head settle after a seek are no longer dropped.
- 29 disk titles play-tested past their title prompts.

## 20261019b

- Main RAM is cleared when the core loads (the SDRAM keeps the previous core's data). Fixes the MZ-80B games disk,
  whose start-up program hung or drew garbage.
- Sangokushi's title (RMW plane latches), the MAME 0.289 software list disks, tapes and MZ-80B software.

## 20261017

- Disk rotation modelled as in the reference emulator (CSP's MB8877): sector timing, READ ADDRESS, density per
  sector. Laydock, Macadam, Märchen Veil and Mugen II, whose copy protection depends on it, now boot. Loading is no
  longer faster than the real machine.
- Harvest and Bomberman tapes; sound mixed at the emulator's levels (SSG volume table, no wrap-around on loud sums).

## 20261009 (first tester build)

- MZ-2500 and MZ-2520 models; IPL in 400 and 200 lines; D88 disks in drives 1-2 with write-back (Ys III saves);
  MZT tapes in MZ-2500, MZ-2000 and MZ-80B modes; keyboard (Japanese positional or US symbols), mouse, joystick;
  YM2203 sound, RTC from the MiSTer clock; 16-, 256- and 4096-colour graphics.
