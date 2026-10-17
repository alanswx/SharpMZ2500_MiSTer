# software/

ROMs and disk/tape images for testing. Everything here except this README is gitignored: the ROMs are Sharp's copyright and the
images belong to their authors. Nothing is redistributed. `tools/fetch_refs.sh --roms <dir>` copies ROMs from a local folder and checks
CRCs; it never downloads ROMs.

| Path | Source | Licence / status | Size |
|---|---|---|---|
| `roms/zips/*.zip`, `roms/zips/mz2200ipl/` | copied from `~/dev2/SharpMZ_MiSTer/software/idealine/mz-2x00/` (originally https://www.idealine.info/sharpmz/ ROM pages) | Sharp copyright, dumps | 772 KB |
| `roms/extracted/<zip>/` | unzipped; CRCs match MAME (docs/roms.md) | same | 1.1 MB |
| `Sharp Mz-2500.zip` | copied from `~/dev2/SharpMZ_MiSTer/software/` | Champion Pro-Wrestling Special and Flicky as loader + memory dumps for EmuZ's debugger | 100 KB |
| `archive.org/mz-2500/MZ2500_doujin_free_games.rar` | https://archive.org/download/mz-2500 ("MZ2500 同人自作フリーゲームセット (起動確認済).rar") | Hoshikuzu-bako/Dust Box disk magazine (freely distributed by its authors); also contains Ys III (commercial, Falcom) | 6 MB |
| `archive.org/mz-2500/extracted/` | unrar of the above: 19 Hoshikuzu-bako D88s + Ys III program/user D88s; all match MAME `mz2500_flop` CRCs | as above | 15 MB |
| `mame0228/<list>/*.zip`, `mame0228/extracted/<list>/<set>/` | https://archive.org/details/MAME_0.228_Software_List_ROMs_merged (fetched 2026-10-16): every `mz2500` (63, the list's 0.228 name for `mz2500_flop`), `mz2000_cass` (8), `mz2000_flop` (8) and `mz2200_cass` (9) set | mostly commercial; a few freeware/doujin | 39 MB |

Against the current MAME lists (refs/mame/src-tree/hash), still missing (all added to MAME after 0.228): `mz2500_flop` balonfgt,
f2gp, galaga, kingflap, lizard, marvels, mclown, rebirth, sangoku, scobol, scpmwm; all of `mz80b_cass`, `mz80b_flop` and
`mz2000_snap`; and some of `mz2000_cass` by CRC. Gang Man, Zero Fighter, Itasandrias and Super Doors were tested from other dumps.
Newer software-list sets on archive.org (searched 2026-10-16): `mame-sl` has `mz2500.zip` and the MZ-2000/2200 lists but is
access-restricted (HTTP 401); the 0.185/0.193/0.202 sets are older than 0.228; the full ROM sets (0.26x-0.289) hold arcade/machine
ROMs, not software lists; `sharp-mz-2500-1` ("Wizardry #1") is only saved auction pages.

Tapes that MAME marks as not working (2026-10-17): Harvest loads from the IPL (C) on its own, despite the list's "mz1z002
MON" note (one 47 KB record at 0000, title after about 7 minutes). Bomberman's WAV has one dropout (two short cycles read
as one long one) at data byte 5657: `tools/wav2mzt.py` repairs it, and the game runs. The Spider's "checksum error" is
the 16-bit 1-bit count wrapping: the data is good. Jelda and Jelda 2 lack their Monitor TS-2000 bootstrap (MAME: bad
dump) and can't load.

ROM files the core and the emulators need (MAME name / CSP name):
`ipl.rom`/`IPL.ROM`, `kanji.rom`/`KANJI.ROM`, `dict.rom`/`DICT.ROM`, `phone.rom`/`PHONE.ROM`, `kanji2.rom`/`KANJI2.ROM`, `ipl2520.rom` (MZ-2520).
