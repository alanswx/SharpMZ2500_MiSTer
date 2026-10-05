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

ROM files the core and the emulators need (MAME name / CSP name):
`ipl.rom`/`IPL.ROM`, `kanji.rom`/`KANJI.ROM`, `dict.rom`/`DICT.ROM`, `phone.rom`/`PHONE.ROM`, `kanji2.rom`/`KANJI2.ROM`, `ipl2520.rom` (MZ-2520).
